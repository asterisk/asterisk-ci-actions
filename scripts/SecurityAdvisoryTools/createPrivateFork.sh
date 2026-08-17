#!/usr/bin/bash

SAT_DIR=$(dirname $(readlink -fn $0))
: ${SCRIPT_DIR:=$(dirname ${SAT_DIR})}

if [ -z "${GITHUB_TOKEN}" ] ; then
	echo "GITHUB_TOKEN must be provided in the environment"
	exit 1
fi

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

if [ -z "${SKIP_MASTER_BRANCH_RENAME}" ] ; then
	SKIP_MASTER_BRANCH_RENAME=false
fi

if [ -z "${GITHUB_WORKSPACE}" ] ; then
	export GITHUB_WORKSPACE=${WORK_DIR}
fi

export GH_TOKEN=${GITHUB_TOKEN}
export GIT_TOKEN=${GITHUB_TOKEN}

gh auth setup-git -h github.com

json_array_to_array SECURITY_FORK_ACTIONS
json_array_to_array SECURITY_FIX_BRANCHES

has_actions=false
if [ ${#SECURITY_FORK_ACTIONS[@]} -gt 0 ] ; then
	has_actions=true
fi

REPO_DIR=${GITHUB_WORKSPACE}/$(basename ${DST_REPO})
echo "Source repository:      asterisk/${SRC_REPO}"
echo "Local repo directory:   ${REPO_DIR}"
echo "Destination repository: asterisk/${DST_REPO}"
echo "Enable actions:         ${SECURITY_FORK_ACTIONS[*]:-none}"
echo "Security fix branches:  ${SECURITY_FIX_BRANCHES[*]:-none}"

echo "Changing directory to ${GITHUB_WORKSPACE}"
cd "${GITHUB_WORKSPACE}"

# Clone the source repo with only the master branch.
# This way when we create the remote repo, master
# will become the default branch instead of the lowest
# numbered one.
echo "Cloning asterisk/${SRC_REPO} to ./${DST_REPO}"
gh repo clone "asterisk/${SRC_REPO}" "./${DST_REPO}" -- --branch master

git config --global --get safe.directory ${REPO_DIR} &>/dev/null || {
	debug_out "Setting safe.directory to ${REPO_DIR}"
	git config --global --add safe.directory ${REPO_DIR}
}

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

echo "Sleeping for 10 seconds to allow GitHub to process the new repository"
sleep 10

echo "Setting repo asterisk/${DST_REPO} parameters"
gh repo edit "asterisk/${DST_REPO}" --allow-forking=true --enable-auto-merge=false \
	--enable-discussions=false --enable-issues=false --enable-merge-commit=false \
	--enable-wiki=false --enable-projects=false --default-branch=master

# Clone all the labels from the soure repo.
echo "Copying labels from asterisk/${SRC_REPO} to asterisk/${DST_REPO}"
gh -R "asterisk/${DST_REPO}" label clone "asterisk/${SRC_REPO}" -f

echo "Pushing branches..."
cd "./${DST_REPO}"
IFS=,
for b in "${SECURITY_FIX_BRANCHES[@]}" ; do
	if [ "$b" == "master" ] ; then
		continue
	fi
	echo "    Pulling $b from asterisk/${SRC_REPO}"
	git checkout -b "$b" "upstream/$b"
	echo "    Pushing $b to asterisk/${DST_REPO}"
	git push -u origin "$b"
done
unset IFS

if ! ${has_actions} ; then
	echo "Actions not used in this repo so no further work needed"
	exit 0
fi

echo "Enabling actions on repo asterisk/${DST_REPO}"
gh api --method PUT \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"/repos/asterisk/${DST_REPO}/actions/permissions" \
	-F "enabled=true" -f "allowed_actions=all"

if ! ${SKIP_MASTER_BRANCH_RENAME} ; then
	# A "GitHub Hack" to enable workflows on the repo.
	echo "Renaming master branch to main and back again to trigger workflow"
	gh api --method POST -H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"/repos/asterisk/${DST_REPO}/branches/master/rename" -f "new_name=main" || :
	sleep 2
	echo "Renaming main branch back to master again to trigger workflow"
	gh api --method POST -H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"/repos/asterisk/${DST_REPO}/branches/main/rename" -f "new_name=master" || :
fi

# Now that workflows have been enabled, we need yet
# another "GitHub Hack" to get the workflow files
# recognized.
high_branch=$(gh api --paginate \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"/repos/asterisk/${DST_REPO}/branches?per_page=100" \
	--jq '.[] | .name' | grep -E "^[0-9.]+$" | sort -r -V | head -1)

gh repo edit "asterisk/${DST_REPO}" --default-branch="${high_branch}"
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

mapfile -t WORKFLOWS < <(gh api "/repos/asterisk/${DST_REPO}/actions/workflows" --jq '.workflows[].name')
echo "Disabling all workflows first"
for wf in "${WORKFLOWS[@]}" ; do
	gh -R "asterisk/${DST_REPO} workflow" disable "$wf" || :
done	

# Disable the workflows we never want to run in the private repo.
echo "Disabling workflows in asterisk/${DST_REPO}"
for wf in "${SECURITY_FORK_ACTIONS[@]}" ; do
	gh -R "asterisk/${DST_REPO}" workflow enable "$wf" || :
done
