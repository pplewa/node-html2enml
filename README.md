# node-htmltoenml #

node-htmltoenml is a node.js module to convert HTML to ENML (Evernote Markup Language).

Unlike other implementations, htmltoenml parses the DOM tree of the HTML document and converts it to valid ENML, which results in a robust and reliable conversion

## Usage ##

Install htmltoenml via npm:

        npm install htmltoenml

Call htmltoenml from a node.js script as follows:

        var htmltoenml = require('htmltoenml');

        options = {
          baseUrl: 'http://www.google.com', // Base url for relative URLs,
                                            //     default is ''.
          strict: true,                     // In strict mode, converter returns
                                            //     error when encountering invalid
                                            //     resources or invalid HTML tags.
                                            //     When strict is set to false,
                                            //     it discards invalid elements.
                                            //     Default is false.
          includeComments: false,           // Default is false
          ignoreFiles: false                // If ignoreFiles flag is set, files
                                            //      are not converted to Evernote
                                            //      resources. Default is false.
        }

        htmltoenml.fromString(htmlString, options, function(err, enml, resources) {
          if (err) {
            // handle conversion error
            console.error(err);
          } else {
            // Your ENML string:
            console.log(enml, resources);
          }
        }) ;

        htmltoenml.fromFile('path/to/your/file.html', options, function(err, enml, resources) {
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
