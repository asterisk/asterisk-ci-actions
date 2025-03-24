#!/usr/bin/bash

if [ -z "${GITHUB_TOKEN}" ] ; then
	echo "GITHUB_TOKEN must be provided in the environment"
	exit 1
fi

: ${SCRIPT_DIR:=$(dirname $(readlink -fn $0))}

if [ ! -f "${SCRIPT_DIR}/ci.functions" ] ; then
	echo "Functions script '${SCRIPT_DIR}/ci.functions' doesn't exist."
	exit 1
fi
. "$SCRIPT_DIR/ci.functions"

set -e

if [ -z "${SRC_REPO}" ] ; then
	echo "--src-repo=<repo> must be provided"
	exit 1
fi

if [ -z "${DST_REPO}" ] ; then
	echo "--dst-repo=<repo> must be provided"
	exit 1
fi

if [ -z "${SECURITY_FIX_BRANCHES}" ] ; then
	echo "--security-fix-branches=<branch>[,<branch>]... must be provided"
	exit 1
fi

if [ -z "${WORK_DIR}" ] && [ -z "${GITHUB_WORKSPACE}" ] ; then
	echo "--work-dir=<dir> must be provided on the command line or GITHUB_WORKSPACE must be provided in the environment"
	exit 1
fi

if [ -z "${GITHUB_WORKSPACE}" ] ; then
	export GITHUB_WORKSPACE=${WORK_DIR}
fi

export GH_TOKEN=${GITHUB_TOKEN}
export GIT_TOKEN=${GITHUB_TOKEN}

gh auth setup-git -h github.com

REPO_DIR=${GITHUB_WORKSPACE}/$(basename ${DST_REPO})
echo "Source repository:      asterisk/${SRC_REPO}"
echo "Local repo directory:   ${REPO_DIR}"
echo "Destination repository: asterisk/${DST_REPO}"
IFS=,
echo -n "Populating branches:    "
for b in ${SECURITY_FIX_BRANCHES} ; do
	echo -n "$b "
done
echo
unset IFS

echo "Changing directory to ${GITHUB_WORKSPACE}"
cd "${GITHUB_WORKSPACE}"

# Clone the source repo with only the master branch.
# This way when we create the remote repo, master
# will become the default branch instead of the lowest
# numbered one.
echo "Cloning asterisk/${SRC_REPO} to ./${DST_REPO}"
gh repo clone "asterisk/${SRC_REPO}" "./${DST_REPO}" -- --branch master
git config --global --add safe.directory "${REPO_DIR}"

# gh repo create tries to set origin in the source
# directory so we need to rename the current origin
# to upstream first.
git -C "${DST_REPO}" remote rename origin upstream
# Prevent accidental pushes to the public repo
git -C "${DST_REPO}" remote set-url --push upstream none

# Create the private repo from the source directory
# and push the branch up.
echo "Creating remote repository asterisk/${DST_REPO} from local directory ./${DST_REPO} and pushing master branch"
gh repo create "asterisk/${DST_REPO}" --source "./${DST_REPO}" --private --disable-issues --disable-wiki --push

echo "Setting repo asterisk/${DST_REPO} parameters"
gh repo edit "asterisk/${DST_REPO}" --allow-forking=false --enable-auto-merge=false \
	--enable-discussions=false --enable-issues=false --enable-merge-commit=false \
	--enable-wiki=false --default-branch=master

echo "Enabling actions on repo asterisk/${DST_REPO}"
gh api --method PUT \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"/repos/asterisk/${DST_REPO}/actions/permissions" \
	-F "enabled=true" -f "allowed_actions=all"

# A "GitHub Hack" to enable workflows on the repo.
echo "Renaming master branch to main and back again to trigger workflow"
gh api --method POST -H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	/repos/asterisk/${DST_REPO}/branches/master/rename -f "new_name=main" >/dev/null
sleep 2
gh api --method POST -H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	/repos/asterisk/${DST_REPO}/branches/main/rename -f "new_name=master" >/dev/null

# Clone all the labels from the soure repo.
echo "Copyinglabels from asterisk/${SRC_REPO} to asterisk/${DST_REPO}"
gh -R "asterisk/${DST_REPO}" label clone "asterisk/${SRC_REPO}" -f

echo "Pushing branches..."
cd "./${DST_REPO}"
IFS=,
for b in ${SECURITY_FIX_BRANCHES} ; do
	if [ "$b" == "master" ] ; then
		continue
	fi
	echo "    Pulling $b from asterisk/${SRC_REPO}"
	git checkout -b "$b" "upstream/$b"
	echo "    Pushing $b to asterisk/${DST_REPO}"
	git push -u origin "$b"
done
unset IFS

# Now that workflows have been enabled, we need yet
# another "GitHub Hack" to get the workflow files
# recognized.
high_branch=$(gh api --paginate \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"/repos/asterisk/${DST_REPO}/branches?per_page=100" \
	--jq '.[] | .name' | grep -E "^[0-9.]+$" | sort -r -V | head -1)

gh repo edit "asterisk/${DST_REPO}" --default-branch=${high_branch}
sleep 1
gh repo edit "asterisk/${DST_REPO}" --default-branch=master
sleep 2

declare -i wfcount=0
wfcount=$(gh api "/repos/asterisk/${DST_REPO}/actions/workflows" --jq '.total_count')
if [ $wfcount -eq 0 ] ; then
	echo "Waiting for workflows to become available"
	declare -i start_sec=0
	declare -i elapsed=0
	start_sec=$SECONDS
	while true ; do
		sleep 1m
		wfcount=$(gh api "/repos/asterisk/${DST_REPO}/actions/workflows" --jq '.total_count')
		[ $wfcount -gt 0 ] && break
		elapsed=$(( (SECONDS - start_sec) / 60 ))
		echo "No workflows after ${elapsed} minutes.  Sleeping for 1 minute"
	done
	echo "$wfcount workflows available after ${elapsed} minutes"
fi

# Disable the workflows we never want to run in the private repo.
echo "Disabling workflows in asterisk/${DST_REPO}"
declare -a DISABLE_WORKFLOWS=( CreateDocs "Issue Opened" PRMerge NightlyAdmin NightlyTests Releaser WeeklyTests )
for w in "${DISABLE_WORKFLOWS[@]}" ; do
	gh -R asterisk/${DST_REPO} workflow disable "$w" || :
done
