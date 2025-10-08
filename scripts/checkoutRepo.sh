#!/usr/bin/bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))

IS_CHERRY_PICK=false
NO_TAGS=false
PR_NUMBER=-1

source ${SCRIPT_DIR}/ci.functions

: ${GITHUB_SERVER_URL:="https://github.com"}
: ${BRANCH:="master"}

assert_env_variables REPO REPO_DIR BRANCH || exit 1

printvars REPO REPO_DIR PR_NUMBER BRANCH IS_CHERRY_PICK NO_TAGS

[ -z ${PR_NUMBER} ] && PR_NUMBER=-1

set -e

REPO_DIR=$(realpath ${REPO_DIR})

cd $(dirname ${REPO_DIR})

no_tags=""
${NO_TAGS} && no_tags="--no-tags"

debug_out "PWD: $(pwd)"
debug_out "Cloning ${REPO} to ${REPO_DIR}..."
git clone -q --no-tags \
	${GITHUB_SERVER_URL}/${REPO} ${REPO_DIR}

if [ ! -d ${REPO_DIR}/.git ] ; then
	log_error_msgs "Failed to clone ${REPO} to ${REPO_DIR}"
	exit 1
fi
debug_out "Clone complete"

cd ${REPO_DIR}

git config --global --get safe.directory ${REPO_DIR} &>/dev/null || {
	debug_out "Setting safe.directory to ${REPO_DIR}"
	git config --global --add safe.directory ${REPO_DIR}
}

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

if [ ${PR_NUMBER} -le 0 ] ; then
	# This is a nightly or dispatch job
	if ${IS_CHERRY_PICK} ; then
		log_error_msgs "Cherry-pick requested without a PR to cherry-pick"
		exit 1
	fi
	debug_out "No PR number specified.  Done."
	exit 0
fi

if ! ${IS_CHERRY_PICK} ; then
	debug_out "    Fetching PR ${PR_NUMBER}"
	git fetch origin refs/pull/${PR_NUMBER}/head
	# We're just checking out the PR
	git checkout FETCH_HEAD
	exit 0
else
	${SCRIPT_DIR}/cherryPick.sh --no-clone --repo=${REPO} \
		--pr-number=${PR_NUMBER} --branch=${BRANCH} \
		--repo-dir=${REPO_DIR} || exit 1
fi
