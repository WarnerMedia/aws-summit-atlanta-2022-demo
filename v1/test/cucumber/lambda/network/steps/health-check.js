const assert = require('assert');
const { Given, When, Then } = require('cucumber');
const { exec } = require("child_process");
const fs = require('fs');

When('we request the health check path {string}', {timeout: 90 * 1000}, (string,done) => {
  exec("./test/script/run-lambda.sh hc", (error, stdout, stderr) => {
    if (error) {
      console.error(`error: ${error.message}`);
    }
    if (stderr) {
      console.error(`stderr: ${stderr}`);
    }
    console.log(stdout);
    done();
  });
});

Then('we should receive a {int} response', (code,done) => {
  fs.readFile('./test/output/hc.json', 'utf8', (err,data) => {
    if (err) {
      console.log(err);
      done(err);
    }
    let response = JSON.parse(data);
    assert.strictEqual(response.statusCode, 200);
    done();
  });
});