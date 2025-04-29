#!/usr/bin/bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))

PUSH=false
NO_CLONE=false

source ${SCRIPT_DIR}/ci.functions

assert_env_variables REPO REPO_DIR PR_NUMBER || exit 1

printvars REPO REPO_DIR PR_NUMBER BRANCH BRANCHES NO_CLONE PUSH

if [ -z "${BRANCH}" ] && [ -z "${BRANCHES}" ] ; then
	error_out "Either --branch or --branches must be specified"
	exit 1
fi

if [ -n "${BRANCH}" ] && [ -n "${BRANCHES}" ] ; then
	error_out "Can't specify both --branch and --branches at the same time"
	exit 1
fi

if ! [[ "${PUSH}" =~ (true|false) ]] ; then
	error_out "--push can only be true or false"
	exit 1
fi

if ! [[ "${NO_CLONE}" =~ (true|false) ]] ; then
	error_out "--no-clone can only be true or false"
	exit 1
fi

REPO_DIR=$(realpath ${REPO_DIR})

cd $(dirname ${REPO_DIR})

: ${BRANCHES:=[\"$BRANCH\"]}
: ${GITHUB_SERVER_URL:="https://github.com"}

if $NO_CLONE ; then
	debug_out "Skipping clone"
else
	debug_out "Cloning ${REPO} to ${REPO_DIR}"
	mkdir -p ${REPO_DIR}
	git clone -q --no-tags \
		${GITHUB_SERVER_URL}/${REPO} ${REPO_DIR}
fi

if [ ! -d ${REPO_DIR}/.git ] ; then
	log_error_msgs "Failed to clone ${REPO} to ${REPO_DIR}"
	exit 1
fi

cd ${REPO_DIR}

git config --global --get safe.directory ${REPO_DIR} &>/dev/null || {
	debug_out "Setting safe.directory to ${REPO_DIR}"
	git config --global --add safe.directory ${REPO_DIR}
}

debug_out "Fetching PR ${PR_NUMBER}"
git fetch --no-tags origin refs/pull/${PR_NUMBER}/head

# Get commits
debug_out "Getting commits for PR ${PR_NUMBER}"
mapfile -t COMMITS < <(gh api /repos/${REPO}/pulls/${PR_NUMBER}/commits \
		--jq '.[] | .sha + "|" + (.commit.message | split("\n")[0]) + "|" + .commit.author.name + "|" + .commit.author.email + "|"' || echo "@_ERROR_@")
[[ "${COMMITS[0]}" =~ @_ERROR_@ ]] && {
	log_error_msgs "No commits for PR ${PR_NUMBER}"
	exit 1
}

echo "COMMITS array: "
declare -p COMMITS

debug_out "***** There are ${#COMMITS[@]} commits for PR ${PR_NUMBER}"
for commit in "${COMMITS[@]}" ; do
	[[ "$commit" =~ ([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\| ]] || {
		log_error_msgs "Unable to parse commit '$commit'"
		exit 1
	}
	SHA=${BASH_REMATCH[1]}
	MESSAGE=${BASH_REMATCH[2]}
	NAME=${BASH_REMATCH[3]}
	EMAIL=${BASH_REMATCH[4]}
	debug_out "Found commit: SHA: $SHA MESSAGE: $MESSAGE NAME: $NAME EMAIL: $EMAIL"
done

branches=$(echo ${BRANCHES} | jq -c -r '.[]' | tr '\n' ' ')
debug_out "Cherry-picking to branches: $branches"

declare -a error_msgs
RC=0

for BRANCH in $branches ; do

	debug_out "***** Cherry-picking commits to branch $BRANCH"
	current_branch=$(git branch --show-current)
	if [ "${current_branch}" != "${BRANCH}" ] ; then
		remote_branch=$(git branch -r --list origin/${BRANCH})
		if [ -z "${remote_branch}" ] ; then
			debug_out "Branch ${BRANCH} does not exist in the repository.  Fetching"
			git fetch --no-tags origin refs/heads/$BRANCH:$BRANCH
		fi
		debug_out "Checking out branch $BRANCH"
		git checkout ${BRANCH}
	else
		debug_out "Already on branch ${BRANCH}"
	fi
	debug_out "Pulling branch $BRANCH"
	git pull

	for commit in "${COMMITS[@]}" ; do
		[[ "$commit" =~ ([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\| ]] || {
			error_msg+="Unable to parse commit '$commit'\n"
			RC=1
			continue
		}
		SHA=${BASH_REMATCH[1]}
		MESSAGE=${BASH_REMATCH[2]}
		NAME=${BASH_REMATCH[3]}
		EMAIL=${BASH_REMATCH[4]}
		
		git config --local user.email "$EMAIL"
		git config --local user.name "$NAME"
		# The SHA should already be downloaded in FETCH_HEAD
		# so we should be able to just cherry-pick it.
		debug_out "Cherry-picking: SHA: $SHA MESSAGE: $MESSAGE to branch $BRANCH"
		git cherry-pick ${SHA}
		if [ $? -eq 0 ] ; then
			debug_out "Successfully cherry-picked: SHA: $SHA MESSAGE: $MESSAGE to branch $BRANCH"
		else
			git cherry-pick --abort &>/dev/null || :
			msg="Unable to cherry-pick commit '${MESSAGE}' to branch ${BRANCH}"
			error_msgs+=( "${msg}" )
			RC=1
			break
		fi
	done
	debug_out "***** Cherry-picked commits to branch $BRANCH"
done

if [ $RC -ne 0 ] ; then
	debug_out "***** Cherry-picking failed"
	log_error_msgs "${error_msgs[@]}"
	exit $RC
fi
debug_out "***** Cherry-picking done"

RC=0
if $PUSH ; then
	gh auth setup-git -h github.com
	for BRANCH in $branches ; do
		debug_out "Pushing to branch $BRANCH"
		git checkout ${BRANCH}
		git push --set-upstream origin $BRANCH || {
			msg="Unable to push to branch ${BRANCH}"
			error_msgs+=( "${msg}" )
			RC=1
			break
		}
	done
fi

log_error_msgs "${error_msgs[@]}"

exit $RC
