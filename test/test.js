const { expect } = require('chai')
const html2enml = require('../src/html2enml')
const path = require('path')
const fs = require('fs')

describe('html2enml', function() {
	const options = { baseUrl: 'http://www.google.com/' }

	describe('.fromString()', function() {
		const resource = {
			mime: 'image/png',
			data: {
				bodyHash: 'd0ad09ba8fe3801ac437d06ba62740d2',
				body:
					'�PNG\r\n\u001a\n\u0000\u0000\u0000\rIHDR\u0000\u0000\u0000 \u0000\u0000\u0000 \u0002\u0003\u0000\u0000\u0000\u000e\u0014�g\u0000\u0000\u0000\u0004gAMA\u0000\u0001��1��_\u0000\u0000\u0000\u0003sBIT\u0001\u0001\u0001|.w�\u0000\u0000\u0000\fPLTE\u0000�\u0000�\u0000\u0000��\u0000\u0000\u0000�e?+�\u0000\u0000\u0000"IDATx�c�\u001f��\u0001�\u0019�0���\u0018��,|\f����\u0018��=\u0000�I�ꉎ\u001b\u0000\u0000\u0000\u0000IEND�B`�'
			}
		}

		it('converts basic HTML to ENML', function(done) {
			const plainHTML = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <a href="http://www.google.com">And a link.</a></p> \
</body> \
</html>`
			return html2enml.fromString(plainHTML, options, function(err, enml) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. <a href="http://www.google.com">And a link.</a></p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				return done()
			})
		})

		it("converts relative URL's to absolute URL's", function(done) {
			const relativeHTML = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <a href="resource">And a link.</a></p> \
</body> \
</html>`
			return html2enml.fromString(relativeHTML, options, function(err, enml) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. <a href="http://www.google.com/resource">And a link.</a></p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				return done()
			})
		})

		it("converts internal Evernote URL's", function(done) {
			// Pseudo Evernote notebook url
			const relativeHTML = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p> \
</body> \
</html>`
			return html2enml.fromString(relativeHTML, options, function(err, enml) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> <p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				return done()
			})
		})

		it.skip('converts files to ENML resouces', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <img src=\"file:${path.join(
				__dirname,
				'assets',
				'testImg.png'
			)}\"></p> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, options, function(
				err,
				enml,
				resources
			) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. <en-media hash="d0ad09ba8fe3801ac437d06ba62740d2" type="image/png"></en-media></p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				expect(resources.length).to.equal(1)
				expect(resources[0].data.bodyHash).to.equal(resource.data.bodyHash)
				expect(resources[0].data.body).to.equal(
					new Buffer(resource.data.body, 'binary')
				)
				expect(resources[0].mime).to.equal(resource.mime)
				return done()
			})
		})

		it('discards files if ignoreFiles flag is set', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <img src=\"file:${path.join(
				__dirname,
				'assets',
				'testImg.png'
			)}\"></p> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, { ignoreFiles: true }, function(
				err,
				enml,
				resources
			) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. </p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				expect(resources.length).to.equal(0)
				return done()
			})
		})

		it('discards comments by default', function(done) {
			// Pseudo Evernote notebook url
			const commentedHTML = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p><!--This is a comment.--> \
</body> \
</html>`
			return html2enml.fromString(commentedHTML, options, function(err, enml) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				return done()
			})
		})

		it('includes comments if includeComments flag set', function(done) {
			// Pseudo Evernote notebook url
			const commentedHTML = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p> \
<!--This is a comment.--> \
</body> \
</html>`
			return html2enml.fromString(
				commentedHTML,
				{ includeComments: true },
				function(err, enml) {
					const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p> \
<!--This is a comment.--> \
</en-note>`
					expect(err).to.be.null
					expect(enml).to.equal(enmlExpected)
					return done()
				}
			)
		})

		it('discards files if resources not found and not in strict mode', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <img src=\"file:${path.join(
				__dirname,
				'assets',
				'testImg'
			)}\"></p> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, options, function(
				err,
				enml,
				resources
			) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. </p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				expect(resources.length).to.equal(0)
				return done()
			})
		})

		it('throws error if resources not found and in strict mode', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <img src=\"file:${path.join(
				__dirname,
				'assets',
				'testImg'
			)}\"></p> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, { strict: true }, function(
				err,
				enml,
				resources
			) {
				expect(err).to.not.be.null
				expect(enml).to.be.undefined
				expect(resources).to.be.undefined
				return done()
			})
		})

		it('discards files if resource invalid and not in strict mode', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <img src=\"file:${path.join(
				__dirname,
				'assets',
				'testImg.unknown'
			)}\"></p> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, options, function(
				err,
				enml,
				resources
			) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1> \
<p>Some text. </p> \
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				expect(resources.length).to.equal(0)
				return done()
			})
		})

		it('throws error if resource invalid and in strict mode', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<p>Some text. <img src=\"file:${path.join(
				__dirname,
				'assets',
				'testImg.unknown'
			)}\"></p> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, { strict: true }, function(
				err,
				enml,
				resources
			) {
				expect(err).to.not.be.null
				expect(enml).to.be.undefined
				expect(resources).to.be.undefined
				return done()
			})
		})

		it('discards element if encountering invalid tag when not in strict mode', function(done) {
			// form element not permitted in ENML
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<form>Some text.</form> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, options, function(
				err,
				enml,
				resources
			) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> \
<h1>A Heading</h1>  </en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				expect(resources.length).to.equal(0)
				return done()
			})
		})

		it('throws error if encountering invalid tag in strict mode', function(done) {
			// form element not permitted in ENML
			const fileHtml = `<!DOCTYPE html> \
<html> \
<body> \
<h1>A Heading</h1> \
<form>Some text.</form> \
</body> \
</html>`
			return html2enml.fromString(fileHtml, { strict: true }, function(
				err,
				enml,
				resources
			) {
				expect(err).to.not.be.null
				expect(enml).to.be.undefined
				expect(resources).to.be.undefined
				return done()
			})
		})

		it('throws error if HTML lacks body element', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<h1>A Heading</h1> \
<p>Some text. <img src=\"file:${path.join(
				__dirname,
				'assets',
				'testImg'
			)}\"></p> \
</html>`
			return html2enml.fromString(fileHtml, { strict: true }, function(
				err,
				enml,
				resources
			) {
				expect(err).to.not.be.null
				expect(enml).to.be.undefined
				expect(resources).to.be.undefined
				return done()
			})
		})

		return it('throws error if HTML cannot be parsed', function(done) {
			const fileHtml = `<!DOCTYPE html> \
<html> \
<h1 att=3D\"att\">A Heading</h1> \
<p>Some text.</p> \
</html>`
			return html2enml.fromString(fileHtml, { strict: true }, function(
				err,
				enml,
				resources
			) {
				expect(err).to.not.be.null
				expect(enml).to.be.undefined
				expect(resources).to.be.undefined
				return done()
			})
		})
	})

	return describe('.fromFile()', () =>
		it('converts file at given path', function(done) {
			const filepath = path.join(__dirname, 'assets', 'testHtml.html')
			return html2enml.fromFile(filepath, options, function(err, enml) {
				const enmlExpected = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note>
<h1>A Heading</h1>
<p>Some text. <a href="http://www.google.com">And a link.</a></p>
</en-note>`
				expect(err).to.be.null
				expect(enml).to.equal(enmlExpected)
				return done()
			})
		}))
})
