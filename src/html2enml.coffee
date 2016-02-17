fs = require 'fs'
async = require 'async'
mime = require 'mime'
XMLHttpRequest = require('xmlhttprequest').XMLHttpRequest
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

      resources = @resources.map (e) ->
        e.resource

      if errors.length
        callback(new Error('Failed to parse'))
      else
        callback null, enml, resources

  _convertMedia: (element, url, callback) ->
    # Test if resource already loaded
    resource = @resources.find (resource) ->
      resource.url is url

    if resource
      element.tagName = 'en-media'
      element.setAttribute 'hash', resource.hash
      element.setAttribute 'type', resource.mime
      element.removeAttribute 'src'
      return callback()

    # Resource not present: Send new request
    xhr = new XMLHttpRequest
    xhr.element = element
    xhr.responseType = 'arraybuffer'
    _this = this
    xhr.onreadystatechange = ->
      if @readyState is 4
        if @status is 200
          # Identify mime type
          mimeType = @getResponseHeader('content-type') or mime.lookup url
          # TODO: Only accept certain file types
          if !mimeType
            # TODO: Handle error here: Mime type could not be identified
            return callback()

          # Create file hash
          spark = new SparkMD5.ArrayBuffer
          spark.append @responseText
          hash = spark.end()

          # Create new Evernote resource
          resource = new Evernote.Resource
            mime: mimeType
          resource.data = new Evernote.Data
          resource.data.body = @responseText
          resource.data.bodyHash = hash

          # Prepare ENML element
          @element.tagName = 'en-media'
          @element.setAttribute 'hash', hash
          @element.setAttribute 'type', mimeType
          @element.removeAttribute 'src'

          # Add resource to resource lookup table
          _this.resources.push
            url: url
            hash: hash
            mime: mimeType
            resource: resource
          callback()
        else
          # TODO: Handle case when resource not found here
          callback()
    xhr.open 'GET', url
    xhr.send()

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

    # Discard element if not permitted in ENML
    if tagName in PROHIBITEDTAGS
      domNode.parentNode.removeChild domNode
      callback()
    else if domNode.attributes or domNode.childNodes
      async.parallel [
        (callback) =>
          # Handle element attributes
          unless domNode.attributes
            return callback()
          async.each domNode.attributes, (attribute, callback) =>
              attributeName = attribute.name.toLowerCase()
              if attributeName in PROHIBITEDATTR
                # Discard attribute since not allowed in ENML
                domNode.attributes.removeNamedItem attribute.name
                callback()
              else if attributeName is 'href' and tagName is 'a'
                # Convert relative links to absolute links
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
                  # Convert images to Evernote resources
                  @_convertMedia domNode, attribute.value, callback
              else
                callback()
            , callback
        (callback) =>
          # Handle element children
          unless domNode.childNodes
            return callback()
          async.each domNode.childNodes, (childNode, callback) =>
              # Recursively convert children
              @_convertNodes childNode, baseUrl, callback
            , callback
        ], callback
    else
      callback()


module.exports.fromString = (htmlString, baseUrl, callback) ->
  new htmlEnmlConverter().convert htmlString, baseUrl, callback

module.exports.fromFile = (file, baseUrl, callback) ->
  # Read file to string
  fs.readFile file, 'utf8', (err, htmlString) ->
    if err
      callback err
    new htmlEnmlConverter().convert htmlString, baseUrl, callback
