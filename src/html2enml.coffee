{DOMParser, XMLSerializer} = require 'xmldom'
XMLHttpRequest = require 'xhr2'
md5 = require 'md5'
async = require 'async'
parser = new DOMParser
serializer = new XMLSerializer
Evernote = require('evernote').Evernote

# Helper to check the head of our URL strings
String::startsWith ?= (s) -> @[...s.length] is s

enmlProhibitedTags = [
  "applet",
  "base",
  "basefont",
  "bgsound",
  "blink",
  "button",
  "dir",
  "embed",
  "fieldset",
  "form",
  "frame",
  "frameset",
  "head",
  "iframe",
  "ilayer",
  "input",
  "isindex",
  "label",
  "layer",
  "legend",
  "link",
  "marquee",
  "menu",
  "meta",
  "noframes",
  "noscript",
  "object",
  "optgroup",
  "option",
  "param",
  "plaintext",
  "script",
  "select",
  "style",
  "textarea",
  "xml"
]

enmlProhibitedAttributes = [
  "id",
  "class",
  "onclick",
  "ondblclick",
  "accesskey",
  "data",
  "dynsrc",
  "tabindex"
]

requests = []
resources = []

_convertMedia = (element, url, callback) ->
  request = new XMLHttpRequest
  request.element = element
  request.open 'GET', url, true

  request.onload = (e) ->
    response = e.target
    if response.status is 200
      hash = md5 response.response
      mime = response.getResponseHeader 'content-type'
      response.element.tagName = 'en-media'
      response.element.setAttribute 'hash', hash
      response.element.setAttribute 'type', mime
      str = serializer.serializeToString response.element
      response.element.removeAttribute 'src'
      resource = new Evernote.Resource
        mime: mime
      resource.data = new Evernote.Data
      resource.data.body = response.response
      resource.data.bodyHash = hash
      resources.push resource

    for request, i in requests
      if request is response
        requests.splice i, 1

    if requests.length is 0
      callback()

  requests.push request
  request.send null

_adjustUrl = (relative, base) ->
  if relative.startsWith 'http:' or relative.startsWith 'https:' or relative.startsWith 'file:' or relative.startsWith 'evernote:'
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

_convertNodes = (domNode, baseUrl, callback) ->
  tagName = if domNode.tagName then domNode.tagName.toLowerCase() else ''

  if tagName and tagName in enmlProhibitedTags
    domNode.parentNode.removeChild domNode
    callback()
  else if domNode.attributes or domNode.childNodes
    async.parallel [
      (callback) ->
        unless domNode.attributes
          return callback()
        async.each domNode.attributes, (attribute, callback) ->
            attributeName = attribute.name.toLowerCase()
            if attributeName in enmlProhibitedAttributes
              domNode.attributes.removeNamedItem attribute.name
              callback()
            else if attributeName is 'href' and tagName and tagName is 'a'
              attribute.value = _adjustUrl attribute.value, baseUrl
              if !attribute.value
                domNode.attributes.removeNamedItem attribute.name
              callback()
            else if attributeName is 'src' and tagName and tagName is 'image'
              attribute.value = _adjustUrl attribute.value, baseUrl
              if !attribute.value
                domNode.parentNode.removeChild domNode
                callback()
              else
                _convertMedia domNode, attribute.value, callback
            else
              callback()
          , callback
      (callback) ->
        unless domNode.childNodes
          return callback()
        async.each domNode.childNodes, (childNode, callback) ->
            _convertNodes childNode, baseUrl, callback
          , callback
      ], callback
  else
    callback()

module.exports = htmlToEnml = (htmlString, baseUrl, callback) ->
  doc = parser.parseFromString(htmlString, 'text/html')
  _convertNodes doc, baseUrl, (err) ->
    doc = doc.getElementsByTagName('body')[0]
    doc.tagName = 'en-note'

    str = serializer.serializeToString doc
    dtd = '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">\n'
    enml = dtd + str
    testdoc = parser.parseFromString enml
    errors = testdoc.getElementsByTagName 'parsererror'

    if errors.length
      callback(new Error('Failed to parse'))
    else
      callback null, enml, resources
