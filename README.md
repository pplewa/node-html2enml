# node-html2enml #

node-html2enml is a node.js module to convert HTML to ENML (Evernote Markup Language).

Unlike other implementations, html2enml parses the DOM tree of the HTML document and converts it to valid ENML, which results in a robust and reliable conversion

## Usage ##

Install html2enml via npm:

        npm install html2enml

Call html2enml from a node.js script as follows:

        var html2enml = require('html2enml');
        // the htmldata variable should contain HTML string
        // base_uri contains uri to be prepended to convert relative URLs to absolute URLs
        // base_uri can be an empty string if base url is unknown
        html2enml.fromString(htmlString, base_uri, function(err, enml, resources) {
          if (err) {
            // handle conversion error
            console.error(err);
          } else {
            // Your ENML string:
            console.log(enml, resources);
          }
        }) ;

        html2enml.fromFile('path/to/your/file.html', base_uri, function(err, enml, resources) {
          if (err) {
            // handle conversion error
            console.error(err);
          } else {
            // Your ENML string:
            console.log(enml, resources);
          }
        }) ;

## Features ##

- en-media tag support, with download and calculation of MD5 Hash(hash attribute) and mime-type(type attribute)
- validates converted ENML against ENML DTD
- case-insensitive tag and attribute conversions
- DOM based tag scanning and replacement

## License ##

GPLv3
