#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

#Global variables.
BASE_LIST_PATH="env/cfn/codebuild/orchestrator/"
COMPARE_FOLDER="compare"
GIT_METADATA_FILE="git-metadata.json"
INSTALL_COMMAND="npm install --only=prod"
OUTPUT_FILE_FOLDER="tmp"
PACKAGE_FILE="package.json"
PREV_VERSION="NONE"
ZIP_FOLDER="archive"

#Template variables.
API_REST_TEMPLATE="iac/cfn/api-gateway/rest.yaml"
LAMBDA_FUNCTION_TEMPLATE="iac/cfn/lambda/function.yaml"

#Update the package file path if we have a base folder set...
if [ -n "$APP_BASE_FOLDER" ]; then
  PACKAGE_FILE="$APP_BASE_FOLDER/$PACKAGE_FILE"
fi

#Replace the install command if a custom command has been passed in.
if [ -n "$CUSTOM_INSTALL_COMMAND" ]; then
  echo "Custom install command has been set..."
  INSTALL_COMMAND="$CUSTOM_INSTALL_COMMAND"
  echo "Install command is now \"$INSTALL_COMMAND\"..."
fi

#Get the soure file base (sans extension)
ENV_FILE_BASE=$(echo "$ENV_ZIP_FILE" | rev | cut -d. -f2- | rev)
IAC_FILE_BASE=$(echo "$IAC_ZIP_FILE" | rev | cut -d. -f2- | rev)
LAMBDA_FILE_BASE=$(echo "$LAMBDA_ZIP_FILE" | rev | cut -d. -f2- | rev)
TEST_FILE_BASE=$(echo "$TEST_ZIP_FILE" | rev | cut -d. -f2- | rev)
SETUP_FILE_BASE=$(echo "$SETUP_ZIP_FILE" | rev | cut -d. -f2- | rev)

#Lists of files to include.
ENV_INCLUDE_LIST="$BASE_LIST_PATH${ENV_FILE_BASE}_include.list"
IAC_INCLUDE_LIST="$BASE_LIST_PATH${IAC_FILE_BASE}_include.list"
LAMBDA_INCLUDE_LIST="$BASE_LIST_PATH${LAMBDA_FILE_BASE}_include.list"
TEST_INCLUDE_LIST="$BASE_LIST_PATH${TEST_FILE_BASE}_include.list"
SETUP_INCLUDE_LIST="$BASE_LIST_PATH${SETUP_FILE_BASE}_include.list"

#Lists of files to exclude.
ENV_EXCLUDE_LIST="$BASE_LIST_PATH${ENV_FILE_BASE}_exclude.list"
IAC_EXCLUDE_LIST="$BASE_LIST_PATH${IAC_FILE_BASE}_exclude.list"
LAMBDA_EXCLUDE_LIST="$BASE_LIST_PATH${LAMBDA_FILE_BASE}_exclude.list"
TEST_EXCLUDE_LIST="$BASE_LIST_PATH${TEST_FILE_BASE}_exclude.list"
SETUP_EXCLUDE_LIST="$BASE_LIST_PATH${SETUP_FILE_BASE}_exclude.list"

#------------------------------------------------------------------------
# END: Set some default variables and files
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

check_cmd_exists () {

  local cmd="$1"
  local version_check="$2"

  echo "Check if the \"$cmd\" command is installed..."
  if exists "$cmd"; then
    echo "The command \"$cmd\" is installed..."
    echo "Check the version..."
    eval "$cmd $version_check"
  else
    echo "The \"$cmd\" command is not installed.  Please install this command."
    exit 1
  fi

}

#Check if we need to install the NPM modules.
check_execute_install_command () {

  if [ "$ENABLE_DEP_INSTALL" = "Yes" ]; then

    # If there is an application base folder, switch to it...
    if [ -n "$APP_BASE_FOLDER" ]; then
      cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
    fi

    echo "Running \"$INSTALL_COMMAND\" command..."
    eval "$INSTALL_COMMAND"

    echo "Do a directory listing..."
    ls -altr

    # If there is an application base folder, switch back to the original base folder...
    if [ -n "$APP_BASE_FOLDER" ]; then
      cd "$CODEBUILD_SRC_DIR" || exit 1;
    fi

  else

    echo "Not running \"$INSTALL_COMMAND\" command..."

  fi

}

#Check if the AWS command was successful.
check_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}
  local command="$2"

  if [ $prev -eq 0 ]; then
    echo "The $command command has succeeded."
  else
    echo "The $command command has failed."
    exit 1
  fi
}

#The following function is used when an option has a value.
check_option () {
  local key="$1"
  local value="$2"

  #Check if we have an empty value.
  if [ -z "$value" ] || [ "$(echo "$value" | cut -c1-1)" = "-" ]; then
    echo "Error: Missing value for argument \"$key\"."
    exit 64
  fi

  #Since none of the above conditions were met, we assume we have a valid value.
  SHIFT_COUNT=2
  return 0
}

check_version () {
  local version_filename="$1"

  echo "Try to get \"$version_filename\" version file from S3..."
  aws s3 cp "s3://$S3_BUCKET/$S3_FOLDER/compare/$version_filename" "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$version_filename" --region "$AWS_REGION"

  echo "Checking if version file \"$version_filename\" exists..."
  if [ -e "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$version_filename" ]; then
    PREV_VERSION=$(cat "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$version_filename")
  else
    echo "The version file doesn't exist, assuming this is the first time we are attempting a deployment..."
    PREV_VERSION="NONE"
  fi
}

#Compare two zip files...
#NOTE: zipcmp must be used for the comparison because zip creation metadata will change MD5 hashes.
compare_zip_file () {

  local zip_filename="$1"
  local codepipeline="$2"
  local add_git_info="$3"
  local pushfile="false"
  local status="fail"

  echo "Try to get \"$zip_filename\" compare ZIP file from S3..."
  aws s3 cp "s3://$S3_BUCKET/$S3_FOLDER/compare/$zip_filename" "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$zip_filename" --region "$AWS_REGION"

  #Doing a comparison to see if we should push the new ZIP file or not.
  echo "Checking if ZIP file \"$zip_filename\" exists on S3..."
  if [ -e "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$zip_filename" ]; then

    #Check if there is a difference between ZIP files.
    echo "Doing zipcmp compare..."
    zipcmp "/$OUTPUT_FILE_FOLDER/$ZIP_FOLDER/$zip_filename" "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$zip_filename"

    #If the exit code was 1, then we know there were changes to the ZIP file and it should be uploaded.
    if [ $? -eq 1 ]; then
      echo "Changes to ZIP file \"$zip_filename\"...will push to S3."
      pushfile="true"
    else
      echo "No changes to ZIP file \"$zip_filename\"...will not push ZIP file."
    fi
  else
    echo "ZIP file \"$zip_filename\" doesn't exist on S3...will push to S3."
    pushfile="true"
  fi

  #Push the file if the flag was set to "true" at some point in this run through the loop.
  if [ "$pushfile" = "true" ]; then

    status=$(push_file "/$OUTPUT_FILE_FOLDER/$ZIP_FOLDER/$zip_filename" "s3://$S3_BUCKET/$S3_FOLDER/compare/$zip_filename")

    echo "Current status is: $status"

    if [ "$status" = "success" ]; then
      echo "Successfully pushed compare file to S3."

      if [ "$add_git_info" = "true" ]; then
        create_deployment_zip "/$OUTPUT_FILE_FOLDER/$ZIP_FOLDER/$zip_filename"
      fi

      status=$(push_file "/$OUTPUT_FILE_FOLDER/$ZIP_FOLDER/$zip_filename" "s3://$S3_BUCKET/$S3_FOLDER/base/$zip_filename")

      if [ "$status" = "success" ]; then
        echo "Successfully pushed deployment file to S3."
        start_codepipeline "$codepipeline"
      else
        echo "Failed to push deployment file to S3."
        exit 1
      fi
    else
      echo "Failed to push compare file to S3."
      exit 1
    fi
  fi
}

#Create a ZIP archive file...
create_compare_zip () {
  local zip_folder="$1"
  local zip_filename="$2"
  local exclude_list="$3"
  local include_list="$4"

  if [ -n "$APP_BASE_FOLDER" ]; then
    exclude_list="$APP_BASE_FOLDER/$exclude_list"
    include_list="$APP_BASE_FOLDER/$include_list"
  fi

  echo "Zipping up files for the \"$zip_filename\" archive..."
  mkdir -p "/$OUTPUT_FILE_FOLDER/$zip_folder"
  zip -X -r "/$OUTPUT_FILE_FOLDER/$zip_folder/$zip_filename" -x@"$exclude_list" . -i@"$include_list"
}

create_deployment_zip () {
  local source_zip="$1"
  local filename="${2:-$GIT_METADATA_FILE}"
  local prev_tag="$(retrieve_github_latest_release)"

  jq -n --arg remoteUrl "$GIT_REMOTE_URL" \
        --arg fullRevision "$GIT_FULL_REVISION" \
        --arg shortRevision "$GIT_SHORT_REVISION" \
        --arg branch "$GIT_BRANCH" \
        --arg message "$GIT_COMMIT_MESSAGE" \
        --arg authorDate "$GIT_COMMIT_DATE" \
        --arg authorName "$GIT_COMMIT_AUTHOR_NAME" \
        --arg authorEmail "$GIT_COMMIT_AUTHOR_EMAIL" \
        --arg organization "$GITHUB_ORGANIZATION" \
        --arg repository "$GITHUB_REPOSITORY" \
        --arg release "v$VERSION" \
        --arg prevRelease "$prev_tag" \
        '{"remoteUrl":$remoteUrl,"fullRevision":$fullRevision,"shortRevision":$shortRevision,"branch":$branch,"commitMessage":$message,"authorDate":$authorDate,"authorName":$authorName,"authorEmail":$authorEmail,"organization":$organization,"prevRelease":$prevRelease,"release":$release,"repository":$repository}' > "./$filename"

  zip -X -r "$source_zip" "./$filename"
}

#Check if required commands exist...
exists () {
  command -v "$1" >/dev/null 2>&1
}

push_file () {
  local source="$1"
  local destination="$2"

  aws s3 cp "$source" "$destination" --region "$AWS_REGION" --quiet
  if [ $? -ne 0 ]; then
    echo "fail"
  else
    echo "success"
  fi
}

push_regular_environment () {

  echo "Creating the various ZIP files..."

  #Create Setup ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$SETUP_ZIP_FILE" "$SETUP_EXCLUDE_LIST" "$SETUP_INCLUDE_LIST"

  #Create Environment ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$ENV_ZIP_FILE" "$ENV_EXCLUDE_LIST" "$ENV_INCLUDE_LIST"

  #Create IaC ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$IAC_ZIP_FILE" "$IAC_EXCLUDE_LIST" "$IAC_INCLUDE_LIST"

  #Create Lambda ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$LAMBDA_ZIP_FILE" "$LAMBDA_EXCLUDE_LIST" "$LAMBDA_INCLUDE_LIST"

  #Create Test ZIP file.
  create_compare_zip "$ZIP_FOLDER" "$TEST_ZIP_FILE" "$TEST_EXCLUDE_LIST" "$TEST_INCLUDE_LIST"

  echo "Comparing the various ZIP files..."

  #Check setup ZIP file.
  compare_zip_file "$SETUP_ZIP_FILE" "$SETUP_CODEPIPELINE" "false"

  #Check Environment ZIP file.
  compare_zip_file "$ENV_ZIP_FILE" "NONE" "true"

  #Check Test ZIP file.
  compare_zip_file "$TEST_ZIP_FILE" "NONE" "true"

  #Check Lambda ZIP file.
  compare_zip_file "$LAMBDA_ZIP_FILE" "$LAMBDA_INITIAL_CODEPIPELINE" "true"

  #Check IaC ZIP file.
  compare_zip_file "$IAC_ZIP_FILE" "$IAC_CODEPIPELINE" "true"

}

push_unstable_environment () {
  local dev_push_flag="success"
  local base_path="/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH"

  echo "Pushing the ZIP files to the \"$UNSTABLE_BRANCH\" environment..."

  #Create environment ZIP file.
  create_compare_zip "$UNSTABLE_BRANCH" "$ENV_ZIP_FILE" "$ENV_EXCLUDE_LIST" "$ENV_INCLUDE_LIST"
  create_deployment_zip "$base_path/$ENV_ZIP_FILE"
  if [ "$(push_file "$base_path/$ENV_ZIP_FILE" "s3://$S3_BUCKET/$S3_FOLDER/$UNSTABLE_BRANCH/$ENV_ZIP_FILE")" = "fail" ]; then
    dev_push_flag="environment"
  fi

  #Create test ZIP file.
  create_compare_zip "$UNSTABLE_BRANCH" "$TEST_ZIP_FILE" "$TEST_EXCLUDE_LIST" "$TEST_INCLUDE_LIST"
  create_deployment_zip "$base_path/$TEST_ZIP_FILE"
  if [ "$(push_file "$base_path/$TEST_ZIP_FILE" "s3://$S3_BUCKET/$S3_FOLDER/$UNSTABLE_BRANCH/$TEST_ZIP_FILE")" = "fail" ]; then
    dev_push_flag="test"
  fi

  #Create Lambda ZIP file.
  create_compare_zip "$UNSTABLE_BRANCH" "$LAMBDA_ZIP_FILE" "$LAMBDA_EXCLUDE_LIST" "$LAMBDA_INCLUDE_LIST"
  create_deployment_zip "$base_path/$LAMBDA_ZIP_FILE"
  if [ "$(push_file "$base_path/$LAMBDA_ZIP_FILE" "s3://$S3_BUCKET/$S3_FOLDER/$UNSTABLE_BRANCH/$LAMBDA_ZIP_FILE")" = "fail" ]; then
    dev_push_flag="lambda"
  fi

  if [ "$dev_push_flag" = "success" ]; then
    start_codepipeline "$LAMBDA_UNSTABLE_CODEPIPELINE"
  else
    echo "Failed to push \"$dev_push_flag\" ZIP file to S3."
    exit 1
  fi
}

reject_approval () {
  local codepipeline="$1"
  local region="$2"

  echo "Checking if the initial CodePipeline Approval action is \"InProgress\"..."
  local status=$(aws --region "$region" codepipeline get-pipeline-state --name "$codepipeline" --query 'stageStates[?stageName==`Deploy`] | [].actionStates[?actionName==`Approval`].latestExecution.status' --output text)
  check_status $? "AWS CLI"

  if [ "$status" = "InProgress" ]; then
    aws --region "$region" codepipeline put-approval-result --pipeline-name "$codepipeline" --stage-name "Deploy" --action-name "Approval" --token "$(aws --region "$region" codepipeline get-pipeline-state --name "$codepipeline" --query 'stageStates[?stageName==`Deploy`] | [].actionStates[?actionName==`Approval`].latestExecution.token' --output text)" --result "summary=Automatic Rejection,status=Rejected"
    check_status $? "AWS CLI"
  else
    echo "The CodePipeline is not in the \"InProgress\" state, so nothing to reject..."
  fi

}

#Because of how CodeBuild does the checkout from GitHub, we have to get creative as to how to get the correct branch name.
retrieve_github_branch () {
  local branch=""
  local trigger="none"

  if [ -n "$CODEBUILD_WEBHOOK_TRIGGER" ]; then
    case "$(echo "$CODEBUILD_WEBHOOK_TRIGGER" | cut -c1-2)" in
      "br") trigger="branch" ; branch=$(echo "$CODEBUILD_WEBHOOK_TRIGGER" | cut -c8-) ;;
      "pr") trigger="pull-request" ;;
      "ta") trigger="tag" ;;
      *) trigger="unknown" ;;
    esac
  fi

  if [ "$trigger" = "branch" ]; then
    #This came from a branch trigger, so output the branch name we parsed.
    echo "$branch"
  elif [ -n "$CODEBUILD_SOURCE_VERSION" ]; then
    #This CodeBuild was triggered directly, most-likely using a branch.
    echo "$CODEBUILD_SOURCE_VERSION"
  else
    #If all else fails, try to get the branch name from git directly.
    git name-rev --name-only HEAD
  fi
}

retrieve_github_organization () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | cut -d/ -f1
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | cut -d/ -f1
  else
    echo "UNKNOWN"
  fi
}

retrieve_github_repository () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | rev | cut -c5- | rev | cut -d/ -f2-
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | rev | cut -c5- | rev | cut -d/ -f2-
  else
    echo "UNKNOWN"
  fi
}

retrieve_github_latest_release () {
  local full_path="repos/$GITHUB_ORGANIZATION/$GITHUB_REPOSITORY/releases/latest"

  local tag=$(curl -s -X GET https://api.github.com/$full_path \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_TOKEN" | jq -r .tag_name)

  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
      echo "none"
  else
      echo "$tag"
  fi
}

start_codepipeline () {
  local name="$1"
  local query="pipelines[?contains(name, \`$name\`)].name"
  local compare=""

  echo "Check if the \"$name\" CodePipeline exists..."

  compare=$(aws --region "$AWS_REGION" codepipeline list-pipelines --output text --query "$query")
  check_status $? "AWS CLI"

  if [ "$name" = "$compare" ]; then

    echo "The \"$name\" CodePipeline exists, starting CodePipeline..."

    if [ "$AUTOMATIC_REJECT" = "Yes" ]; then
      echo "Checking to see if there is a pending approval that we want to automatically reject..."
      reject_approval "$name" "$AWS_REGION"
    else
      echo "Automatic approval rejection is disabled..."
    fi

    aws --region "$AWS_REGION" codepipeline start-pipeline-execution --name "$name"
    check_status $? "AWS CLI"
  else
    echo "The \"$name\" CodePipeline doesn't exist in this environment, so nothing to trigger."
  fi
}

update_package_file () {
  local message="$1"
  local content=$(base64 --wrap=0 "./$PACKAGE_FILE")
  local sha="NONE"
  local full_path="repos/$GITHUB_ORGANIZATION/$GITHUB_REPOSITORY/contents/$PACKAGE_FILE"
  local put_response="NONE"

  echo "The git branch: $GIT_BRANCH"

  sha=$(curl -s -X GET https://api.github.com/$full_path?ref=$GIT_BRANCH -H "Authorization: token $GITHUB_TOKEN" | jq -r .sha)

  check_status $? "GitHub"

  echo "File SHA is: $sha"

  put_response=$(curl -s -X PUT https://api.github.com/$full_path \
  -H "Authorization: token $GITHUB_TOKEN" \
  -d @- << EOF
{
  "branch": "$GIT_BRANCH",
  "content": "$content",
  "message": "$message",
  "sha": "$sha"
}
EOF
)

  check_status $? "GitHub"

  echo "Get the updated SHA..."
  sha=$(echo "$put_response" | jq -r .commit.sha)

  echo "Updated SHA: $sha"

  if [ $(echo -n "$sha" | wc -m) -eq 40 ]; then
    echo "Updating the full git SHA to \"$sha\"..."
    GIT_FULL_REVISION="$sha"
    GIT_SHORT_REVISION=$(echo "$sha" | cut -c1-7)
  else
    echo "Didn't get a valid SHA back from GitHub..."
    exit 1
  fi

}

update_version () {
  local version_filename="${GIT_BRANCH}_version"

  check_version "$version_filename"

  VERSION=$(cat "$PACKAGE_FILE" | jq -r '.version')
  check_status $? "Get Current Package Version"

  mkdir -p "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER"

  if [ "$PREV_VERSION" = "$VERSION" ]; then

    echo "Automatically bumping the NPM patch version..."

    # If there is an application base folder, switch to it...
    if [ -n "$APP_BASE_FOLDER" ]; then
      cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
    fi

    TEMP_VERSION=$(npm version patch)
    check_status $? "NPM"

    # If there is an application base folder, switch back to the original base folder...
    if [ -n "$APP_BASE_FOLDER" ]; then
      cd "$CODEBUILD_SRC_DIR" || exit 1;
    fi

    #Remove the "v" from the version...
    VERSION=$(echo "$TEMP_VERSION" | cut -c2-)

    update_package_file "Automatic patch version update to: $VERSION"

  fi

  echo "Update the version file value for this branch..."
  echo "$VERSION" > "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$version_filename"

  echo "Push the updated \"$version_filename\" version file to S3..."
  aws s3 cp "/$OUTPUT_FILE_FOLDER/$COMPARE_FOLDER/$version_filename" "s3://$S3_BUCKET/$S3_FOLDER/compare/$version_filename" --region "$AWS_REGION"
  check_status $? "AWS CLI"

}

update_api_rest_deployment_resource () {

  # If there is an application base folder, switch to it...
  if [ -n "$APP_BASE_FOLDER" ]; then
    cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
  fi

  if [ -e "$API_REST_TEMPLATE" ]; then
    echo "API REST Gateway templete exists, updating deployment resource..."
    sed -i'' "s/<<VersionHash>>/$CODEBUILD_START_TIME/" "$API_REST_TEMPLATE"
  else
    echo "API REST Gateway templete doesn't exist..."
  fi

  # If there is an application base folder, switch back to the original base folder...
  if [ -n "$APP_BASE_FOLDER" ]; then
    cd "$CODEBUILD_SRC_DIR" || exit 1;
  fi

}

update_lambda_version_resource () {

  # If there is an application base folder, switch to it...
  if [ -n "$APP_BASE_FOLDER" ]; then
    cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
  fi

  if [ -e "$LAMBDA_FUNCTION_TEMPLATE" ]; then
    echo "Lambda templete exists, updating version resource..."
    sed -i'' "s/<<VersionHash>>/$CODEBUILD_START_TIME/" "$LAMBDA_FUNCTION_TEMPLATE"
  else
    echo "Lambda templete doesn't exist..."
  fi

  # If there is an application base folder, switch back to the original base folder...
  if [ -n "$APP_BASE_FOLDER" ]; then
    cd "$CODEBUILD_SRC_DIR" || exit 1;
  fi

}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set Git Variables
#------------------------------------------------------------------------

echo "Extract some METADATA from the package.json file..."
NAME=$(cat "$PACKAGE_FILE" | jq -r '.name')
VERSION=$(cat "$PACKAGE_FILE" | jq -r '.version')

#Set some git variables...
echo "Retrieve the remote origin URL..."
GIT_REMOTE_URL=$(git config --local remote.origin.url)

echo "Retrieve the full git revision..."
GIT_FULL_REVISION=$(git rev-parse HEAD)
check_status $? "git"

echo "Retrieve the short git revision..."
GIT_SHORT_REVISION=$(git rev-parse --short HEAD)
check_status $? "git"

echo "Retrieve the git branch..."
echo "CODEBUILD_WEBHOOK_TRIGGER: $CODEBUILD_WEBHOOK_TRIGGER"
echo "CODEBUILD_SOURCE_VERSION: $CODEBUILD_SOURCE_VERSION"
GIT_BRANCH=$(retrieve_github_branch)

echo "Retrieve the GitHub commit message..."
GIT_COMMIT_MESSAGE=$(git log -1 --pretty=%B)
check_status $? "git"

echo "Retrieve the GitHub commit date..."
GIT_COMMIT_DATE=$(git log -1 --pretty=%cd --date=local)
check_status $? "git"

echo "Retrieve the GitHub commit author name..."
GIT_COMMIT_AUTHOR_NAME=$(git log -1 --pretty=%an)
check_status $? "git"

echo "Retrieve the GitHub commit auther e-mail..."
GIT_COMMIT_AUTHOR_EMAIL=$(git log -1 --pretty=%ae)
check_status $? "git"

echo "Retrieve the GitHub organization..."
GITHUB_ORGANIZATION=$(retrieve_github_organization "$GIT_REMOTE_URL")
check_status $? "git"

echo "Retrieve the GitHub repository..."
GITHUB_REPOSITORY=$(retrieve_github_repository "$GIT_REMOTE_URL")
check_status $? "git"

#------------------------------------------------------------------------
# END: Set Git Variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Main Build Logic
#------------------------------------------------------------------------

check_cmd_exists "aws" "--version"

check_cmd_exists "jq" "-V"

check_cmd_exists "npm" "-v"

check_cmd_exists "yarn" "-v"

check_cmd_exists "zip" "--version"

check_cmd_exists "zipcmp" "-V"

#Output some variables
echo "Git full revision is: $GIT_FULL_REVISION"
echo "Git short revision is: $GIT_SHORT_REVISION"
echo "Git branch name is: $GIT_BRANCH"
echo "GitHub organization: $GITHUB_ORGANIZATION"
echo "GitHub repository: $GITHUB_REPOSITORY"

echo "Do a directory listing of the base directory..."
ls -altr

#Loop through the arguments.
while [ $# -gt 0 ]; do
  case "$1" in
    # Required Arguments
    -b|--bucket)  check_option "$1" "$2"; S3_BUCKET="$2"; shift $SHIFT_COUNT;;       # S3 bucket ID.
    -f|--folder)  check_option "$1" "$2"; S3_FOLDER="$2"; shift $SHIFT_COUNT;;       # S3 top folder if not deploying to top level of bucket.
    -r|--region)  check_option "$1" "$2"; REGION="$2"; shift $SHIFT_COUNT;;          # AWS region.
    -v|--version) check_option "$1" "$2"; APP_BASE_FOLDER="$2"; shift $SHIFT_COUNT;; # Application Version folder.
    *) echo "Error: Invalid argument \"$1\"" ; exit 64 ;;
  esac
done


#Check if the orchestrator should install the Node.js modules.
check_execute_install_command

#Update the API Gateway Deployment resource name.
update_api_rest_deployment_resource

#Update the Lambda version resource name.
update_lambda_version_resource

#Update the package version.
update_version

#Check to see if we need to push to the dev/unstable environment.
if [ "$UNSTABLE_BRANCH" = "$GIT_BRANCH" ]; then

  push_unstable_environment

else

  push_regular_environment

fi

#------------------------------------------------------------------------
# END: Main Build Logic
#------------------------------------------------------------------------