#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

#------------------------------------------------------------------------
# BEGIN: Functions
#------------------------------------------------------------------------

exists () {
  command -v "$1" >/dev/null 2>&1
}

check_cmd_exists () {
  local cmd="$1"

  if exists $cmd; then
    echo "The command \"$cmd\" is installed."
  else
    echo "The command \"$cmd\" is not installed."
    exit 1
  fi
}

#------------------------------------------------------------------------
# END: Functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set up the git hooks directory
#------------------------------------------------------------------------

GIT_HOOKS="v1/git-hook"

if [ -n "$GIT_HOOKS" ]; then
  echo "Setting the active git hooks folder: $GIT_HOOKS"
  git config --local core.hooksPath "$GIT_HOOKS"
fi

#------------------------------------------------------------------------
# END: Set up the git hooks directory
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Check for prerequisite commands
#------------------------------------------------------------------------

echo "Check that the \"git-secrets\" command is installed..."
echo "This is the repository for the \"git-secrets\" command: https://github.com/awslabs/git-secrets"

check_cmd_exists "git-secrets"

#------------------------------------------------------------------------
# END: Check for prerequisite commands
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Add git secrets rules
#------------------------------------------------------------------------

echo "Adding git secrets rules..."

git config --unset-all --global secrets.patterns
git secrets --add --global "(A3T[A-Z0-9]|AKIA|ASIA|ACCA)[A-Z0-9]{16}"
git secrets --add --global "[-]{5}BEGIN\\s(RSA|DSA|EC|PGP|OPENSSH)\\sPRIVATE\\s(KEY|KEY\\sBLOCK)[-]{5}"
git secrets --add --global "mongodb://.+?:.+?@[a-zA-Z0-9\.-]+(:[0-9]+){0,1}"
git secrets --add --global "mongodb\+srv://.+?:.+?@[a-zA-Z0-9\.-]+(:[0-9]+){0,1}"
git secrets --add --global "postgres://.+?:.+?@[a-zA-Z0-9\.-]+(:[0-9]+){0,1}"
git secrets --add --global "(http|https)://[^/\s:@]{3,64}:[^/\s:@]{3,64}@[a-zA-Z0-9\.-]+(:[0-9]+){0,1}"
git secrets --add --global "AIza[0-9A-Za-z_-]{35}"
git secrets --add --global "https://hooks.slack.com/services/T[a-zA-Z0-9_]{8}/B[a-zA-Z0-9_]{8}/[a-zA-Z0-9_]{24}"

#------------------------------------------------------------------------
# END: Add git secrets rules
#------------------------------------------------------------------------