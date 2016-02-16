fs = require 'fs'
async = require 'async'
XMLHttpRequest = require 'xhr2'
SparkMD5 = require 'spark-md5'
{DOMParser, XMLSerializer} = require 'xmldom'
Evernote = require('evernote').Evernote

# Helper to check the head of our URL strings
String::startsWith ?= (s) -> @[...s.length] is s

NOTEHEADER = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">'

PROHIBITEDTAGS = [
  "applet", "base", "basefont", "bgsound", "blink", "button", "dir", "embed",
  "fieldset", "form", "frame", "frameset", "head", "iframe", "ilayer", "input",
  "isindex", "label", "layer", "legend", "link", "marquee", "menu", "meta",
  "noframes", "noscript", "object", "optgroup", "option", "param", "plaintext",
  "script", "select", "style", "textarea", "xml"
]

PROHIBITEDATTR = [
  "id", "class", "onclick", "ondblclick", "accesskey", "data", "dynsrc",
  "tabindex"
]

class htmlEnmlConverter
  constructor: ->
    @requests = []
    @resources = []
    @parser = new DOMParser
    @serializer = new XMLSerializer

  convert: (htmlString, baseUrl, callback) ->
    doc = @parser.parseFromString(htmlString, 'text/html')
    @_convertNodes doc, baseUrl, (err) =>
      doc = doc.getElementsByTagName('body')[0]
      doc.tagName = 'en-note'

      enml = NOTEHEADER + @serializer.serializeToString doc

      # TODO: improve error checking (not by reparsing!)
      testdoc = @parser.parseFromString enml
      errors = testdoc.getElementsByTagName 'parsererror'

      if errors.length
        callback(new Error('Failed to parse'))
      else
        callback null, enml, @resources

  # TODO: Check if inbuilt function covers this
  _toArrayBuffer: (buffer) ->
    ab = new ArrayBuffer buffer.length
    view = new Uint8Array ab
    for unit, i in buffer
      view[i] = unit
    return ab

  # TODO: Rewrite this from scratch
  _convertMedia: (element, url, callback) ->
    request = new XMLHttpRequest
    request.element = element
    request.open 'GET', url, true
    request.responseType = 'arraybuffer'

    request.onload = (e) =>
      response = e.target
      console.log request
      console.log response
      if response.status is 200
        spark = new SparkMD5.ArrayBuffer
        spark.append response.response
        hash = spark.end
        mime = response.getResponseHeader 'content-type'
        response.element.tagName = 'en-media'
        response.element.setAttribute 'hash', hash
        response.element.setAttribute 'type', mime
        str = @serializer.serializeToString response.element
        response.element.removeAttribute 'src'
        resource = new Evernote.Resource
          mime: mime
        resource.data = new Evernote.Data
        resource.data.body = response.response
        resource.data.bodyHash = hash
        @resources.push resource

      for request, i in @requests
        if request is response
          @requests.splice i, 1

      if @requests.length is 0
        callback()

    if url.indexOf 'http' is -1
      fileExists = fs.existsSync url
      request.onload
        target:
          status: if fileExists then 200 else 404
          response: if fileExists then @_toArrayBuffer fs.readFileSync url else null
          element: element
          getResponseHeader: ->
            'image/png'
    else
      @requests.push request
      request.send()

  _adjustUrl: (relative, base) ->
    if relative.startsWith('http:') or relative.startsWith('https:') or relative.startsWith('file:') or relative.startsWith('evernote:')
      return relative

    stack = base.split '/'
    parts = relative.split '/'
    stack.pop()

    for part in parts
      if part is '.'
        continue
      if part is '..'
        stack.pop()
      else
        stack.push(part)

    stack.join '/'

  _convertNodes: (domNode, baseUrl, callback) ->
    tagName = if domNode.tagName then domNode.tagName.toLowerCase() else ''

    if tagName in PROHIBITEDTAGS
      domNode.parentNode.removeChild domNode
      callback()
    else if domNode.attributes or domNode.childNodes
      async.parallel [
        (callback) =>
          unless domNode.attributes
            return callback()
          async.each domNode.attributes, (attribute, callback) =>
              attributeName = attribute.name.toLowerCase()
              if attributeName in PROHIBITEDATTR
                domNode.attributes.removeNamedItem attribute.name
                callback()
              else if attributeName is 'href' and tagName is 'a'
                attribute.value = @_adjustUrl attribute.value, baseUrl
                if !attribute.value
                  domNode.attributes.removeNamedItem attribute.name
                callback()
              else if attributeName is 'src' and tagName is 'img'
                attribute.value = @_adjustUrl attribute.value, baseUrl
                if !attribute.value
                  domNode.parentNode.removeChild domNode
                  callback()
                else
                  @_convertMedia domNode, attribute.value, callback
              else
                callback()
            , callback
        (callback) =>
          unless domNode.childNodes
            return callback()
          async.each domNode.childNodes, (childNode, callback) =>
              @_convertNodes childNode, baseUrl, callback
            , callback
        ], callback
    else
      callback()


module.exports.fromString = (htmlString, baseUrl, callback) ->
  new htmlEnmlConverter().convert htmlString, baseUrl, callback

module.exports.fromFile = (file, baseUrl, callback) ->
  fs.readFile file, 'utf8', (err, htmlString) ->
    if err
      callback err
    new htmlEnmlConverter().convert htmlString, baseUrl, callback
