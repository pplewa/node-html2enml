const fs = require('fs')
const path = require('path')
const async = require('async')
const mime = require('mime')
const nodeFetch = require('node-fetch')
const fileType = require('file-type')
const SparkMD5 = require('spark-md5')
let { DOMParser, NodeType, XMLSerializer } = require('xmldom')
const Evernote = require('evernote')

const fetch = function(url, options) {
	const Request = nodeFetch.Request
	const Response = nodeFetch.Response
	const request = new Request(url, options)
	if (request.url.substring(0, 5) === 'file:') {
		return new Promise((resolve, reject) => {
			const filePath = path.normalize(url.substring('file:///'.length))
			if (!fs.existsSync(filePath)) {
				reject(`File not found: ${filePath}`)
			}
			const readStream = fs.createReadStream(filePath)
			readStream.on('open', function() {
				resolve(
					new Response(readStream, {
						url: request.url,
						status: 200,
						statusText: 'OK',
						size: fs.statSync(filePath).size,
						timeout: request.timeout
					})
				)
			})
		})
	} else {
		return nodeFetch(url, options)
	}
}

mime.default_type = ''

// Helper to check the head of our URL strings
if (String.prototype.startsWith == null) {
	String.prototype.startsWith = function(s) {
		return this.slice(0, s.length) === s
	}
}
if (String.prototype.startsWithAny == null) {
	String.prototype.startsWithAny = function(s) {
		for (let x of Array.from(s)) {
			if (this.startsWith(x)) {
				return true
			}
		}
		return false
	}
}

const NOTE_HEADER = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM \
"http://xml.evernote.com/pub/enml2.dtd">`

const PERMITTED_ELEMENTS = [
	'a',
	'abbr',
	'acronym',
	'en-todo',
	'address',
	'area',
	'b',
	'bdo',
	'big',
	'blockquote',
	'br',
	'caption',
	'center',
	'cite',
	'code',
	'col',
	'colgroup',
	'dd',
	'del',
	'dfn',
	'div',
	'dl',
	'dt',
	'em',
	'font',
	'h1',
	'h2',
	'h3',
	'h4',
	'h5',
	'h6',
	'hr',
	'i',
	'img',
	'ins',
	'kbd',
	'li',
	'map',
	'ol',
	'p',
	'pre',
	'q',
	's',
	'samp',
	'small',
	'span',
	'strike',
	'strong',
	'sub',
	'sup',
	'table',
	'tbody',
	'td',
	'tfoot',
	'th',
	'thead',
	'title',
	'tr',
	'tt',
	'u',
	'ul',
	'var',
	'xmp'
]

const PROHIBITED_ATTR = [
	'id',
	'class',
	'onclick',
	'ondblclick',
	'on',
	'accesskey',
	'data',
	'dynsrc',
	'tabindex'
]

// Node types as given in xmldom
NodeType = {}
const ELEMENT_NODE = (NodeType.ELEMENT_NODE = 1)
const ATTRIBUTE_NODE = (NodeType.ATTRIBUTE_NODE = 2)
const TEXT_NODE = (NodeType.TEXT_NODE = 3)
const CDATA_SECTION_NODE = (NodeType.CDATA_SECTION_NODE = 4)
const ENTITY_REFERENCE_NODE = (NodeType.ENTITY_REFERENCE_NODE = 5)
const ENTITY_NODE = (NodeType.ENTITY_NODE = 6)
const PROCESSING_INSTRUCTION_NODE = (NodeType.PROCESSING_INSTRUCTION_NODE = 7)
const COMMENT_NODE = (NodeType.COMMENT_NODE = 8)
const DOCUMENT_NODE = (NodeType.DOCUMENT_NODE = 9)
const DOCUMENT_TYPE_NODE = (NodeType.DOCUMENT_TYPE_NODE = 10)
const DOCUMENT_FRAGMENT_NODE = (NodeType.DOCUMENT_FRAGMENT_NODE = 11)
const NOTATION_NODE = (NodeType.NOTATION_NODE = 12)

const PERMITTED_URLS = ['http', 'https', 'file', 'evernote']

class htmlEnmlConverter {
	constructor(options) {
		this._convertNode = this._convertNode.bind(this)
		this.baseUrl = options.baseUrl || ''
		this.strict = options.strict || false
		this.includeComments = options.includeComments || false
		this.ignoreFiles = options.ignoreFiles || false
		this.resources = []
		this.warnings = []
		this.errors = []
		this.fatalErrors = []
		this.parser = new DOMParser({
			errorHandler: {
				warning: mess => this.warnings.push(mess),
				error: mess => this.errors.push(mess),
				fatalError: mess => this.fatalErrors.push(mess)
			}
		})
		this.serializer = new XMLSerializer()
	}

	convert(htmlString, callback) {
		const doc = this.parser.parseFromString(htmlString, 'text/html')
		if (this.fatalErrors.length) {
			// Catching non-recoverable errors
			return callback(new Error(this.fatalErrors))
		}
		let body = doc.getElementsByTagName('body')
		if (!body.length) {
			return callback(new Error('Body element not found'))
		} else {
			body = body[0]
		}
		return this._convertBody(body, err => {
			if (err) {
				return callback(err)
			}
			const enml =
				NOTE_HEADER +
				this.serializer
					.serializeToString(body)
					.replace(' xmlns="http://www.w3.org/1999/xhtml"', '')
			const resources = this.resources.map(e => e.resource)

			return callback(null, enml, resources)
		})
	}

	_convertBody(domNode, callback) {
		domNode.tagName = 'en-note'
		return async.series(
			[
				callback => {
					return async.each(
						domNode.attributes,
						(attribute, callback) => {
							const attributeName = attribute.name.toLowerCase()
							if (Array.from(PROHIBITED_ATTR).includes(attributeName)) {
								// Discard attribute since not allowed in ENML
								domNode.attributes.removeNamedItem(attribute.name)
							}
							return callback()
						},
						callback
					)
				},
				callback => {
					// Handle element children
					return async.each(domNode.childNodes, this._convertNode, callback)
				}
			],
			callback
		)
	}

	_convertNode(domNode, callback) {
		// We only need to process element nodes:
		// unless domNode.nodeType is ELEMENT_NODE
		//   return callback()
		switch (domNode.nodeType) {
			case ELEMENT_NODE:
				return this._convertElementNode(domNode, callback)
			case TEXT_NODE:
				return callback()
			case COMMENT_NODE:
				if (!this.includeComments) {
					domNode.parentNode.removeChild(domNode)
				}
				return callback()
			default:
				domNode.parentNode.removeChild(domNode)
				return callback()
		}
	}

	_convertElementNode(domNode, callback) {
		const tagName = domNode.tagName ? domNode.tagName.toLowerCase() : ''
		if (!Array.from(PERMITTED_ELEMENTS).includes(tagName)) {
			// Discard element if not permitted in ENML
			domNode.parentNode.removeChild(domNode)
			const err = this.strict ? new Error(`Illegal element (${tagName})`) : null
			return callback(err)
		}

		return async.parallel(
			[
				callback => {
					// Handle element attributes
					return async.each(
						domNode.attributes,
						(attribute, callback) => {
							const attributeName = attribute.name.toLowerCase()
							if (Array.from(PROHIBITED_ATTR).includes(attributeName)) {
								// Discard attribute since not allowed in ENML
								domNode.attributes.removeNamedItem(attribute.name)
								return callback()
							} else if (attributeName === 'href' && tagName === 'a') {
								// Convert relative links to absolute links
								attribute.value = this._adjustUrl(attribute.value)
								if (!attribute.value) {
									domNode.attributes.removeNamedItem(attribute.name)
								}
								return callback()
							} else if (attributeName === 'src' && tagName === 'img') {
								if (this.ignoreFiles) {
									domNode.parentNode.removeChild(domNode)
									return callback()
								}
								attribute.value = this._adjustUrl(attribute.value)
								if (!attribute.value) {
									domNode.parentNode.removeChild(domNode)
									return callback()
								} else {
									// Convert images to Evernote resources
									return this._convertMedia(domNode, attribute.value, callback)
								}
							} else {
								return callback()
							}
						},
						callback
					)
				},
				callback => {
					// Handle element children
					return async.each(domNode.childNodes, this._convertNode, callback)
				}
			],
			callback
		)
	}

	_createResource(url, arrayBuffer, resource, element, mime) {
		const spark = new SparkMD5.ArrayBuffer()
		spark.append(arrayBuffer)
		const hash = spark.end()

		// Create new Evernote resource
		resource = Evernote.Types.Resource({ mime })
		resource.data = Evernote.Types.Data()
		resource.data.body = arrayBuffer
		resource.data.bodyHash = hash

		// Prepare ENML element
		element.tagName = 'en-media'
		element.setAttribute('hash', hash)
		element.setAttribute('type', mime)
		element.removeAttribute('src')

		return { url, hash, mime, resource }
	}

	_convertMedia(element, url, callback) {
		// Test if resource already loaded
		let resource = this.resources.find(resource => resource.url === url)

		// Resource already present
		if (resource) {
			element.tagName = 'en-media'
			element.setAttribute('hash', resource.hash)
			element.setAttribute('type', resource.mime)
			element.removeAttribute('src')
			return callback()
		}

		const _this = this
		return fetch(url)
			.then(r => r.buffer())
			.then(buffer => {
				const mimeType = fileType(buffer).mime || mime.lookup(url)
				if (!mimeType) {
					// Mime type will be empty if it cannot be identified
					if (_this.strict) {
						// Throw error in strict mode
						return callback(
							new Error(`Mime type of resource ${url} could not be identified`)
						)
					} else {
						// when not in strict mode: ignore error and remove domNode
						element.parentNode.removeChild(element)
						return callback()
					}
				}

				// Add resource to resource lookup table
				this.resources.push(
					this._createResource(url, buffer, resource, element, mimeType)
				)
				return callback()
			})
			.catch(e => {
				// Handle case when resource not found here
				if (_this.strict) {
					// Throw error in strict mode
					return callback(new Error(`Resource ${url} not found`))
				} else {
					// Remove element otherwise
					element.parentNode.removeChild(element)
					return callback()
				}
			})
	}

	_adjustUrl(relative) {
		if (relative.startsWithAny(PERMITTED_URLS)) {
			return relative
		}
		const stack = this.baseUrl.split('/')
		const parts = relative.split('/')
		stack.pop()
		for (let part of Array.from(parts)) {
			if (part === '.') {
				continue
			}
			if (part === '..') {
				stack.pop()
			} else {
				stack.push(part)
			}
		}
		return stack.join('/')
	}
}

module.exports.fromString = (htmlString, options, callback) =>
	new htmlEnmlConverter(options).convert(htmlString, callback)

module.exports.fromFile = (file, options, callback) =>
	// Read file to string
	fs.readFile(file, 'utf8', function(err, htmlString) {
		if (err) {
			callback(err)
		}
		return new htmlEnmlConverter(options).convert(htmlString, callback)
	})
