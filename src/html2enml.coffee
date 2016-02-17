fs = require 'fs'
async = require 'async'
mime = require 'mime'
mime.default_type = ''
XMLHttpRequest = require('xmlhttprequest').XMLHttpRequest
SparkMD5 = require 'spark-md5'
{DOMParser, XMLSerializer} = require 'xmldom'
Evernote = require('evernote').Evernote

# Helper to check the head of our URL strings
String::startsWith ?= (s) -> @[...s.length] is s

NOTEHEADER = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">'

PERMITTEDELEMENTS = [
  'a', 'abbr', 'acronym', 'address', 'area', 'b', 'bdo', 'big', 'blockquote',
  'br', 'caption', 'center', 'cite', 'code', 'col', 'colgroup', 'dd', 'del',
  'dfn', 'div', 'dl', 'dt', 'em', 'font', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'hr', 'i', 'img', 'ins', 'kbd', 'li', 'map', 'ol', 'p', 'pre', 'q', 's',
  'samp', 'small', 'span', 'strike', 'strong', 'sub', 'sup', 'table', 'tbody',
  'td', 'tfoot', 'th', 'thead', 'title', 'tr', 'tt', 'u', 'ul', 'var', 'xmp'
]

PROHIBITEDATTR = [
  'id', 'class', 'onclick', 'ondblclick', 'on', 'accesskey', 'data', 'dynsrc',
  'tabindex'
]

# PERMITTEDURLS = [
#   'http', 'https', 'file'
# ]

class htmlEnmlConverter

  constructor: (options) ->
    @baseUrl = options.baseUrl or ''
    @strict = options.strict or false
    @resources = []
    @parser = new DOMParser
    @serializer = new XMLSerializer

  convert: (htmlString, callback) ->
    doc = @parser.parseFromString(htmlString, 'text/html')
    doc = doc.getElementsByTagName('body')[0]
    @_convertBody doc, (err) =>
      if err
        return callback err
      enml = NOTEHEADER + @serializer.serializeToString doc
      resources = @resources.map (e) ->
        e.resource

      callback null, enml, resources

  _convertBody: (domNode, callback) ->
    domNode.tagName = 'en-note'

    async.series [
      (callback) =>
        async.each domNode.attributes, (attribute, callback) =>
            attributeName = attribute.name.toLowerCase()
            if attributeName in PROHIBITEDATTR
              # Discard attribute since not allowed in ENML
              domNode.attributes.removeNamedItem attribute.name
              callback()
          , callback
      (callback) =>
        # Handle element children
        async.each domNode.childNodes, (childNode, callback) =>
            # Recursively convert children
            @_convertNodes childNode, callback
          , callback
    ], callback

  _convertNodes: (domNode, callback) ->
    tagName = if domNode.tagName then domNode.tagName.toLowerCase() else ''

    if domNode.nodeName isnt '#text' and tagName not in PERMITTEDELEMENTS
      # Discard element if not permitted in ENML
      domNode.parentNode.removeChild domNode
      err = if @strict then new Error('Illegal element.') else null
      return callback(err)

    async.parallel [
      (callback) =>
        # Handle element attributes
        async.each domNode.attributes, (attribute, callback) =>
            attributeName = attribute.name.toLowerCase()
            if attributeName in PROHIBITEDATTR
              # Discard attribute since not allowed in ENML
              domNode.attributes.removeNamedItem attribute.name
              callback()
            else if attributeName is 'href' and tagName is 'a'
              # Convert relative links to absolute links
              attribute.value = @_adjustUrl attribute.value
              if !attribute.value
                domNode.attributes.removeNamedItem attribute.name
              callback()
            else if attributeName is 'src' and tagName is 'img'
              attribute.value = @_adjustUrl attribute.value
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
        async.each domNode.childNodes, (childNode, callback) =>
            # Recursively convert children
            @_convertNodes childNode, callback
          , callback
      ], callback

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
            # Mime type will be empty if it cannot be identified
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

  _adjustUrl: (relative) ->
    if relative.startsWith('http:') or relative.startsWith('https:') or relative.startsWith('file:') or relative.startsWith('evernote:')
      return relative
    stack = @baseUrl.split '/'
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

module.exports.fromString = (htmlString, options, callback) ->
  new htmlEnmlConverter(options).convert htmlString, callback

module.exports.fromFile = (file, options, callback) ->
  # Read file to string
  fs.readFile file, 'utf8', (err, htmlString) ->
    if err
      callback err
    new htmlEnmlConverter(options).convert htmlString, callback
