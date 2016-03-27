fs = require 'fs'
async = require 'async'
mime = require 'mime'
mime.default_type = ''
XMLHttpRequest = require('xmlhttprequest').XMLHttpRequest
SparkMD5 = require 'spark-md5'
{DOMParser, NodeType, XMLSerializer} = require 'xmldom'
Evernote = require('evernote').Evernote

# Helper to check the head of our URL strings
String::startsWith ?= (s) -> @[...s.length] is s
String::startsWithAny ?= (s) ->
  (return true if @startsWith x) for x in s
  return false

NOTE_HEADER = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">'

PERMITTED_ELEMENTS = [
  'a', 'abbr', 'acronym', 'address', 'area', 'b', 'bdo', 'big', 'blockquote',
  'br', 'caption', 'center', 'cite', 'code', 'col', 'colgroup', 'dd', 'del',
  'dfn', 'div', 'dl', 'dt', 'em', 'font', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'hr', 'i', 'img', 'ins', 'kbd', 'li', 'map', 'ol', 'p', 'pre', 'q', 's',
  'samp', 'small', 'span', 'strike', 'strong', 'sub', 'sup', 'table', 'tbody',
  'td', 'tfoot', 'th', 'thead', 'title', 'tr', 'tt', 'u', 'ul', 'var', 'xmp'
]

PROHIBITED_ATTR = [
  'id', 'class', 'onclick', 'ondblclick', 'on', 'accesskey', 'data', 'dynsrc',
  'tabindex'
]

# Node types as given in xmldom
NodeType = {}
ELEMENT_NODE                = NodeType.ELEMENT_NODE                = 1
ATTRIBUTE_NODE              = NodeType.ATTRIBUTE_NODE              = 2
TEXT_NODE                   = NodeType.TEXT_NODE                   = 3
CDATA_SECTION_NODE          = NodeType.CDATA_SECTION_NODE          = 4
ENTITY_REFERENCE_NODE       = NodeType.ENTITY_REFERENCE_NODE       = 5
ENTITY_NODE                 = NodeType.ENTITY_NODE                 = 6
PROCESSING_INSTRUCTION_NODE = NodeType.PROCESSING_INSTRUCTION_NODE = 7
COMMENT_NODE                = NodeType.COMMENT_NODE                = 8
DOCUMENT_NODE               = NodeType.DOCUMENT_NODE               = 9
DOCUMENT_TYPE_NODE          = NodeType.DOCUMENT_TYPE_NODE          = 10
DOCUMENT_FRAGMENT_NODE      = NodeType.DOCUMENT_FRAGMENT_NODE      = 11
NOTATION_NODE               = NodeType.NOTATION_NODE               = 12

PERMITTED_URLS = [
  'http', 'https', 'file', 'evernote'
]

class htmlEnmlConverter

  constructor: (options) ->
    @baseUrl = options.baseUrl or ''
    @strict = options.strict or false
    @includeComments = options.includeComments or false
    @ignoreFiles = options.ignoreFiles or false
    @resources = []
    @parser = new DOMParser
    @serializer = new XMLSerializer

  convert: (htmlString, callback) ->
    doc = @parser.parseFromString(htmlString, 'text/html')
    doc = doc.getElementsByTagName('body')[0]
    @_convertBody doc, (err) =>
      if err
        return callback err
      enml = NOTE_HEADER + @serializer.serializeToString doc
      resources = @resources.map (e) ->
        e.resource

      callback null, enml, resources

  _convertBody: (domNode, callback) ->
    domNode.tagName = 'en-note'

    async.series [
      (callback) =>
        async.each domNode.attributes, (attribute, callback) =>
            attributeName = attribute.name.toLowerCase()
            if attributeName in PROHIBITED_ATTR
              # Discard attribute since not allowed in ENML
              domNode.attributes.removeNamedItem attribute.name
              callback()
          , callback
      (callback) =>
        # Handle element children
        async.each domNode.childNodes, (childNode, callback) =>
            # Recursively convert children
            @_convertNode childNode, callback
          , callback
    ], callback

  _convertNode: (domNode, callback) ->
    # We only need to process element nodes:
    # unless domNode.nodeType is ELEMENT_NODE
    #   return callback()
    switch domNode.nodeType
      when ELEMENT_NODE
        @_convertElementNode domNode, callback
      when TEXT_NODE
        callback()
      when COMMENT_NODE
        if not @includeComments
          domNode.parentNode.removeChild domNode
        callback()
      else
        domNode.parentNode.removeChild domNode
        callback()

  _convertElementNode: (domNode, callback) ->
    tagName = if domNode.tagName then domNode.tagName.toLowerCase() else ''
    if tagName not in PERMITTED_ELEMENTS
      # Discard element if not permitted in ENML
      domNode.parentNode.removeChild domNode
      err = if @strict then new Error('Illegal element.') else null
      return callback(err)

    async.parallel [
      (callback) =>
        # Handle element attributes
        async.each domNode.attributes, (attribute, callback) =>
            attributeName = attribute.name.toLowerCase()
            if attributeName in PROHIBITED_ATTR
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
              if @ignoreFiles
                domNode.parentNode.removeChild domNode
                return callback()
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
            @_convertNode childNode, callback
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
    if relative.startsWithAny(PERMITTED_URLS)
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
