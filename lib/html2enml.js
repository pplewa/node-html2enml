var DOMParser=require('xmldom').DOMParser;
var XMLSerializer=require('xmldom').XMLSerializer;
var XMLHttpRequest=require('xhr2');
var Evernote = require('evernote').Evernote;
var SparkMD5 = require('spark-md5');
var fs = require('fs');

var enml_prohibited_tags=[
	"applet","base","basefont","bgsound","blink","button","dir","embed","fieldset","form","frame","frameset",
	"head","iframe","ilayer","input","isindex","label","layer","legend","link","marquee","menu","meta","noframes",
	"noscript","object","optgroup","option","param","plaintext","script","select","style","textarea","xml" ];

var enml_prohibited_attributes=[ "id","class","onclick","ondblclick","accesskey","data","dynsrc","tabindex" ];

var requests = []
var resources = [];

function toArrayBuffer(buffer) {
    var ab = new ArrayBuffer(buffer.length);
    var view = new Uint8Array(ab);
    for (var i = 0; i < buffer.length; ++i) {
        view[i] = buffer[i];
    }
    return ab;
}

function convert_media(element, url, callback) {
	var request = new XMLHttpRequest();
	request.element = element;
	request.open("GET", url, true);	
	request.responseType = 'arraybuffer';
	// console.log("Fetching "+url);
	request.onload = function(e) {
		var response = e.target; // request that maps to appropriate XMLHTTPRequest object
		if(response.status == 200) {
			var spark = new SparkMD5.ArrayBuffer();
			spark.append(response.response);
			var hash = spark.end();
			var mime = response.getResponseHeader('content-type');
			response.element.tagName = "en-media";
			response.element.setAttribute("hash", hash);
			response.element.setAttribute("type", mime);
			var str = new XMLSerializer().serializeToString(response.element);

			response.element.removeAttribute('src');
			var resource = new Evernote.Resource({ 
				mime: mime,
				width: response.element.getAttribute('width') && parseInt(response.element.getAttribute('width'), 0),
				height: response.element.getAttribute('height') && parseInt(response.element.getAttribute('height'), 0)
			});
			resource.data = new Evernote.Data();
			resource.data.body = response.response;
			resource.data.bodyHash = hash;
			resources.push(resource);
			// console.log(str);
		} 
		for(var i=0; i<requests.length; i++) {
			if(requests[i] === response) {
				requests.splice(i, 1);
			}
		}
		// console.log(requests.length);
		if(requests.length == 0) {
			callback();
		}
	}
	if (url.indexOf('http') === -1) {
		request.onload({
			target: {
				status: 200,
				response: toArrayBuffer(fs.readFileSync(url)),
				element: element,
				getResponseHeader: function() {
					return 'image/png'
				}
			}
		});
	} else {
		requests.push(request);
		request.send(null);
	}
}

function adjust_url(url, base_uri) {
	if(url){
		if(url.indexOf("/")==0) // relative URL
			url=base_uri+url;
				
		// console.log("url is "+url);
		if(url.indexOf("http:")==0 || url.indexOf("https:")==0 || url.indexOf("/")==0 || url.indexOf("file:")==0 || url.indexOf("evernote:")==0) 
			return url;
	}
	return null;
} 



function convert_nodes(root, base_uri, callback) {
	var tag=root.tagName;
	
	if(tag && enml_prohibited_tags.indexOf(tag.toLowerCase())>-1) {
		// console.log("Deleting "+tag+" element");
		root.parentNode.removeChild(root);
		return;
	} 

	if(root.attributes) {
		// console.log("Processing tag "+root.tagName);
		for(var i=0;i<root.attributes.length;i++) {
			var attribute=root.attributes.item(i);

			if(enml_prohibited_attributes.indexOf(attribute.name.toLowerCase())>-1) {
				// console.log("Removing attribute "+attribute.name);
				root.attributes.removeNamedItem(attribute.name);
				i--;
			}
			if(root.tagName && root.tagName.toLowerCase()=="a" && 
				attribute.name.toLowerCase()=="href") {
				attribute.value=adjust_url(attribute.value, base_uri) ;	
				// console.log("converting "+attribute.name+" to "+attribute.value);
				if(!attribute.value) {
					root.parentNode.removeChild(root);
					return ;	
				}
			}
			if(root.tagName && root.tagName.toLowerCase()=="img" && 
				attribute.name.toLowerCase()=="src") {
				attribute.value=adjust_url(attribute.value, base_uri) ;	
				// console.log("converting "+attribute.name);
				if(!attribute.value) {
					root.parentNode.removeChild(root);
					return ;	
				} else {
					convert_media(root, attribute.value, callback);
				}
			}
		}
	}

	if(root.childNodes) {
		for(var i=0;i<root.childNodes.length;i++) {
			convert_nodes(root.childNodes[i], base_uri, callback) ;	
		}
	}
}

function html2enml(data, base_uri, success_callback, failure_callback) {
	var doc = new DOMParser().parseFromString(data);

	convert_nodes(doc, base_uri, function() {
		doc = doc.getElementsByTagName("body")[0];
		doc.tagName = "en-note";

		var str=new XMLSerializer().serializeToString(doc);
		var dtd='<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">\n';
		var enml=dtd+str;
		var testdoc=new DOMParser().parseFromString(enml);
		var errors=testdoc.getElementsByTagName("parsererror");

		if (errors.length==0)
			success_callback(enml, resources);
		else
			error_callback(enml);
	});
}

module.exports = {
	convert: function(htmldata, base_uri, success_callback, failure_callback) {
		return html2enml(htmldata, base_uri, success_callback, failure_callback);
	}
};