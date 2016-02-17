expect = require('chai').expect
html2enml = require '../lib/html2enml'
path = require 'path'
fs = require 'fs'

describe 'html2enml', ->
  describe '.fromString()', ->
    it 'should convert basic HTML to ENML', (done) ->
      plainHTML = '<!DOCTYPE html>
                   <html>
                   <body>
                   <h1>A Heading</h1>
                   <p>Some text. <a href="http://www.google.com">And a link.</a></p>
                   </body>
                   </html>'
      html2enml.fromString plainHTML, 'http://www.google.com', (err, enml) ->
        enmlExpected = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> <h1>A Heading</h1> <p>Some text. <a href="http://www.google.com">And a link.</a></p> </en-note>'
        expect(err).to.be.null
        expect(enml).to.equal(enmlExpected)
        done()

    it 'should convert relative links to absolute links', (done) ->
      relativeHTML = '<!DOCTYPE html>
                      <html>
                      <body>
                      <h1>A Heading</h1>
                      <p>Some text. <a href="resource">And a link.</a></p>
                      </body>
                      </html>'
      html2enml.fromString relativeHTML, 'http://google.com/', (err, enml) ->
        enmlExpected = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> <h1>A Heading</h1> <p>Some text. <a href="http://google.com/resource">And a link.</a></p> </en-note>'
        expect(err).to.be.null
        expect(enml).to.equal(enmlExpected)
        done()

    it 'should convert internal Evernote URLs', (done) ->
      # Pseudo Evernote notebook url
      relativeHTML = '<!DOCTYPE html>
                      <html>
                      <body>
                      <h1>A Heading</h1>
                      <p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p>
                      </body>
                      </html>'
      html2enml.fromString relativeHTML, 'http://google.com/', (err, enml) ->
        enmlExpected = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> <h1>A Heading</h1> <p>Some text. <a href="evernote:///view/2127483637/s161/01344ac2-be5a-454b-8e01-a0b487cda7e4/01344ac2-be5a-454b-8e01-a0c987cda7e4/">And a link.</a></p> </en-note>'
        expect(err).to.be.null
        expect(enml).to.equal(enmlExpected)
        done()

    it 'should convert local files to ENML resouces', (done) ->
      fileHtml = "<!DOCTYPE html>
                      <html>
                      <body>
                      <h1>A Heading</h1>
                      <p>Some text. <img src=\"file:#{path.join __dirname, 'assets', 'testImg.png'}\"></p>
                      </body>
                      </html>"
      html2enml.fromString fileHtml, '', (err, enml, resources) ->
        enmlExpected = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> <h1>A Heading</h1> <p>Some text. <en-media hash="d0ad09ba8fe3801ac437d06ba62740d2" type="image/png"></en-media></p> </en-note>'
        expect(err).to.be.null
        expect(enml).to.equal(enmlExpected)
        done()

    it 'should convert remote files to ENML resouces', (done) ->
      remoteHTML = "<!DOCTYPE html>
                      <html>
                      <body>
                      <h1>A Heading</h1>
                      <p>Some text. <img src=\"http://www.schaik.com/pngsuite/basn3p02.png\"></p>
                      </body>
                      </html>"
      html2enml.fromString remoteHTML, '', (err, enml, resources) ->
        enmlExpected = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note> <h1>A Heading</h1> <p>Some text. <en-media hash="d0ad09ba8fe3801ac437d06ba62740d2" type="image/png"></en-media></p> </en-note>'
        expect(err).to.be.null
        expect(enml).to.equal(enmlExpected)
        done()

        # webHTML = "<!DOCTYPE html>
        #                 <html>
        #                 <body>
        #                 <h1>A Heading</h1>
        #                 <p>Some text. <img src=\"http://www.schaik.com/pngsuite/basn3p02.png\"></p>
        #                 </body>
        #                 </html>"

    # it 'should convert HTML entities', ->
#
#   describe '.fromFile()', () ->
#     it 'should convert file at given path', () ->
