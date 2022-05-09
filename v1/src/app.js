//Lets require/import the HTTP module
const aws = require('aws-sdk'),
      auth = require("basic-auth"); /* Basic Authentication Module */

//Lets define a port we want to listen on...
const APPLICATION_TITLE = process.env.APPLICATION_TITLE || "Default Title";
const ENVIRONMENT = process.env.ENVIRONMENT;
const GIT_COMMIT = process.env.GIT_COMMIT;
const HEALTH_CHECK_PATH = process.env.HEALTH_CHECK_PATH || "/hc/";
const API_HOMEPAGE_PATH = process.env.API_HOMEPAGE_PATH || "/v1/homepage";
const MAX_AGE = process.env.MAX_AGE || 300;
const REALM  = process.env.REALM || "Please Authenticate";
const REGION = process.env.REGION;
const SECRET_REGION = process.env.SECRET_REGION;
const SECRET_ARN = process.env.SECRET_ARN;
const VERSION = process.env.VERSION;

// Create a Secrets Manager client
var secretClient = new aws.SecretsManager({
  region: SECRET_REGION
});

exports.handler = (event, context, callback) => {

  context.callbackWaitsForEmptyEventLoop = false;

  function buildApiHomepage() {

    //Return a simple HTML page to return via the API.
    return '<!doctype html>\n<html lang="en">\n' +
           '<head>\n<meta charset="utf-8">\n<title>' + APPLICATION_TITLE + ' - [' + REGION + ']</title>\n' +
           '<style type="text/css">* {font-family:arial, sans-serif;}</style>\n' +
           '<link rel="icon" type="image/png" sizes="16x16" href="data:image/png;base64,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" />\n' +
           '</head>\n<body>\n' +
           '<h1>' + APPLICATION_TITLE + '</h1>\n' +
           '<div id="content"><p>The API Gateway homepage path for the "' + ENVIRONMENT + '" environment.  The "max-age" is set to "' + MAX_AGE + '" seconds.</p></div>\n' +
           '<div id="content"><p>The demo is live.</p></div>\n' +
           '</body>\n</html>';

  }

  function buildHealthCheck() {

    //Return JSON response.
    const output = {
      "API_HOMEPAGE_PATH": API_HOMEPAGE_PATH,
      "ENVIRONMENT": ENVIRONMENT,
      "GIT_COMMIT": GIT_COMMIT,
      "VERSION": VERSION
    };

    return JSON.stringify(output);

  }

  function buildLoadBalancerHomepage() {

    //Return a simple HTML page if we passed Basic Authentication.
    return '<!doctype html>\n<html lang="en">\n' +
           '<head>\n<meta charset="utf-8">\n<title>' + APPLICATION_TITLE + '</title>\n' +
           '<style type="text/css">* {font-family:arial, sans-serif;}</style>\n' +
           '<link rel="icon" type="image/png" sizes="16x16" href="data:image/png;base64,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" />\n' +
           '</head>\n<body>\n' +
           '<h1>' + APPLICATION_TITLE + '</h1>\n' +
           '<div id="content"><p>The Lambda Node.js boilerplate function is active in the "' + ENVIRONMENT + '" environment.  The "max-age" is set to "' + MAX_AGE + '" seconds.</p></div>\n' +
           '<div id="content"><p>The demo is live.</p></div>\n' +
           '</body>\n</html>';

  }

  function checkCredentials(request,secretObj) {
    //Get the credentials...
    var credentials = auth(request),
        body = "",
        response = {};

    //Checking credentials...
    if (!credentials || credentials.name !== secretObj.name || credentials.pass !== secretObj.pass) {

      console.warn("Not authorized...");

      var response = {
        statusCode: 401,
        statusDescription: 'Unauthorized',
        headers: {
          "WWW-Authenticate": "Basic realm="+REALM,
          "Content-Type": "text/plain; charset=UTF-8"
        },
        body: "Access Denied"
      };

      callback(null, response);

    } else {

      console.log("Authorized, loading ALB page...");

      var response = {
        statusCode: 200,
        headers: {
          "Content-Type": "text/html; charset=UTF-8",
          "Cache-Control": "max-age=" + MAX_AGE
        },
        body: buildLoadBalancerHomepage(),
        isBase64Encoded: false
      };

      callback(null, response);
  
    }
  }
    
  function checkPath(request) {
    var response = {};
  
    if (request.path == HEALTH_CHECK_PATH || request.path == "/hc") {
  
      var response = {
          statusCode: 200,
          headers: {
              "Content-Type": "application/json; charset=UTF-8"
          },
          body: buildHealthCheck(),
          isBase64Encoded: false
      };
  
      callback(null, response);

    } else if (request.path == API_HOMEPAGE_PATH) {

      console.log("Loading API page...");

      var response = {
        statusCode: 200,
        headers: {
          "Content-Type": "text/html; charset=UTF-8",
          "Cache-Control": "max-age=" + MAX_AGE
        },
        body: buildApiHomepage(),
        isBase64Encoded: false
      };

      callback(null, response);

    } else {
    
      console.log("Getting credentials...");
      getCredentials(request);
   
    }
  
  }
  
  function getCredentials(request) {
    var decodedBinarySecret = "",
        secretObj = {},
        response = {};
  
    secretClient.getSecretValue({SecretId: SECRET_ARN}, function(err, data) {
      if (err) {
        console.warn(`Secrets Manager Error: ${err.code}`);
        if (err.code === 'DecryptionFailureException')
          // Secrets Manager can't decrypt the protected secret text using the provided KMS key.
          // Deal with the exception here, and/or rethrow at your discretion.
          throw err;
        else if (err.code === 'InternalServiceErrorException')
          // An error occurred on the server side.
          // Deal with the exception here, and/or rethrow at your discretion.
          throw err;
        else if (err.code === 'InvalidParameterException')
          // You provided an invalid value for a parameter.
          // Deal with the exception here, and/or rethrow at your discretion.
          throw err;
        else if (err.code === 'InvalidRequestException')
          // You provided a parameter value that is not valid for the current state of the resource.
          // Deal with the exception here, and/or rethrow at your discretion.
          throw err;
        else if (err.code === 'ResourceNotFoundException')
          // We can't find the resource that you asked for.
          // Deal with the exception here, and/or rethrow at your discretion.
          throw err;
      } else {
        // Decrypts secret using the associated KMS CMK.
        // Depending on whether the secret is a string or binary, one of these fields will be populated.
        if ('SecretString' in data) {
          console.log("Getting secret value...");
          secretObj = JSON.parse(data.SecretString);
        } else {
          let buff = new Buffer(data.SecretBinary, 'base64');
          decodedBinarySecret = buff.toString('ascii');
        }
      }
      console.log("About to check credentials...");
      checkCredentials(request,secretObj);
    });
  }

  checkPath(event);

};