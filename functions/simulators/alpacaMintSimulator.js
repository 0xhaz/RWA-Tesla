const requestConfig = require("../configs/alpacaMintConfig.js");

const {
  simulateScript,
  decodeResult,
} = require("@chainlink/functions-toolkit");

async function main() {
  const { responseBytesHexstring, errorString, capturedTerminalOutput } =
    await simulateScript(requestConfig);

  if (responseBytesHexstring) {
    console.log(
      `Response: ${decodeResult(
        responseBytesHexstring,
        requestConfig.expectedReturnType
      ).toString()} \n`
    );
  }

  if (errorString) {
    console.error(`Error: ${errorString}`);
  }

  if (capturedTerminalOutput) {
    console.log(`Terminal Output: ${capturedTerminalOutput}`);
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
