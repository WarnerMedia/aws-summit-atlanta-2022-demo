#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Main Logic
#------------------------------------------------------------------------

if [ -n "$APP_BASE_FOLDER" ]; then
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
fi

echo "Current path: $(pwd)"

echo "Making sure the run.sh script has the correct permissions..."
chmod u+x ./local/run.sh

echo "Run the Lambda tests..."
npm run test-lambda

#------------------------------------------------------------------------
# END: Main Logic
#------------------------------------------------------------------------