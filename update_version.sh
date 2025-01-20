#!/bin/bash

# path to pom.xml
POM_FILE="pom.xml"

# load environment variables from .prepare-commit-msg-config file
if [ -f .prepare-commit-msg-config ]; then
    source .prepare-commit-msg-config
else
    echo "Configuration file '.prepare-commit-msg-config' not found. Please create it with REMOTE_MAIN_BRANCH_NAME variable."
    exit 1
fi

# skip the hook if required
if [[ "$SKIP_HOOK" == "true" ]]; then
    # echo "Skipping prepare-commit-msg hook."
    exit 0
fi

# define the remote branch to fetch the version from
# REMOTE_BRANCH="origin/master"

# fetch the latest changes from the remote repository
echo "Fetching latest changes from the remote repository..."
git fetch origin > /dev/null 2>&1

# retrieve the version from the pom.xml in the master branch of the remote repository
REMOTE_VERSION=$(git show $REMOTE_MAIN_BRANCH_NAME:$POM_FILE 2>/dev/null | grep -oPm1 "(?<=<version>)(.*)(?=</version>)")

if [ -z "$REMOTE_VERSION" ]; then
    echo "Could not retrieve version from $REMOTE_MAIN_BRANCH_NAME. Ensure the branch exists and has a valid pom.xml."
    exit 1
fi

echo "Remote ($REMOTE_MAIN_BRANCH_NAME) Version: $REMOTE_VERSION"

# retrieve the version from the local pom.xml
LOCAL_VERSION=$(grep -oPm1 "(?<=<version>)(.*)(?=</version>)" "$POM_FILE")

if [ -z "$LOCAL_VERSION" ]; then
    echo "Could not retrieve version from local pom.xml."
    exit 1
fi

echo "Local Version: $LOCAL_VERSION"

# determine the highest version between remote (master branch) and local
IFS='.' read -r -a remote_parts <<< "$REMOTE_VERSION"
IFS='.' read -r -a local_parts <<< "$LOCAL_VERSION"

for i in 0 1 2; do
    if (( ${remote_parts[i]} > ${local_parts[i]} )); then
        HIGHEST_VERSION=$REMOTE_VERSION
        break
    elif (( ${remote_parts[i]} < ${local_parts[i]} )); then
        HIGHEST_VERSION=$LOCAL_VERSION
        break
    fi
done

HIGHEST_VERSION=${HIGHEST_VERSION:-$REMOTE_VERSION}
# echo "Highest Version: $HIGHEST_VERSION"

# split the highest version into components
IFS='.' read -r -a version_parts <<< "$HIGHEST_VERSION"
MAJOR=${version_parts[0]}
MINOR=${version_parts[1]}
PATCH=${version_parts[2]}

# get the commit message from the prepared message file
COMMIT_MSG_FILE=$1 # first argument passed to the hook
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

## check for keywords in the commit message and increment the version accordingly
## echo "Commit Message: $COMMIT_MSG"
#if [[ "$COMMIT_MSG" =~ \(major\) ]]; then
#    # echo "Detected 'major' keyword in commit message."
#    MAJOR=$((MAJOR + 1))
#    MINOR=0
#    PATCH=0
#elif [[ "$COMMIT_MSG" =~ \(minor\) ]]; then
#    # echo "Detected 'minor' keyword in commit message."
#    MINOR=$((MINOR + 1))
#    PATCH=0
#elif [[ "$COMMIT_MSG" =~ \(patch\) ]]; then
#    # echo "Detected 'patch' keyword in commit message."
#    PATCH=$((PATCH + 1))
#else
#    # echo "No version-related keyword found. Defaulting to patch increment."
#    PATCH=$((PATCH + 1))
#fi

# increment the version based on the DEFAULT_INCREMENT variable in config file
case "$DEFAULT_INCREMENT" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo "Invalid DEFAULT_INCREMENT value in .prepare-commit-msg-config. Use 'major', 'minor', or 'patch'."
        exit 1
        ;;
esac

# build the new version number
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

echo "New Version: $NEW_VERSION"

# update the version in local pom.xml
sed -i "s|<version>$LOCAL_VERSION</version>|<version>$NEW_VERSION</version>|" "$POM_FILE"

git add "$POM_FILE"

SKIP_HOOK=true git commit -m "$COMMIT_MSG" # prepare-commit-msg hook infinitely calls itself if SKIP_HOOK=true option is not used

# append the new version to the original commit message
echo "Version $NEW_VERSION" >> "$COMMIT_MSG_FILE"

# output the new version for downstream tasks
echo "##vso[task.setvariable variable=NEW_VERSION]$NEW_VERSION"

# allow the commit to continue
exit 0
