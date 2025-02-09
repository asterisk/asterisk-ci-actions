#!/usr/bin/bash
SCRIPT_DIR=$(dirname $(realpath $0))

PUSH=false
NO_CLONE=false

source ${SCRIPT_DIR}/ci.functions

for v in REPO REPO_DIR PR_NUMBER ; do
	assert_env_variable $v || exit 1
done

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

cd $(dirname ${REPO_DIR})

: ${BRANCHES:=[\'$BRANCH\']}
: ${GITHUB_SERVER_URL:="https://github.com"}

if ! $NO_CLONE ; then
	debug_out "Cloning ${REPO} to ${REPO_DIR}"
	mkdir -p ${REPO_DIR}
	git clone -q --depth 10 --no-tags \
		${GITHUB_SERVER_URL}/${REPO} ${REPO_DIR}
	git config --global --add safe.directory $(realpath ${REPO_DIR})
else
	debug_out "Skipping clone"
fi

if [ ! -d ${REPO_DIR}/.git ] ; then
	error_out "Failed to clone ${REPO} to ${REPO_DIR}"
	exit 1
fi

cd ${REPO_DIR}
debug_out "Fetching PR ${PR_NUMBER}"
git fetch --depth 10 --no-tags origin refs/pull/${PR_NUMBER}/head

# Get commits
debug_out "Getting commits for PR ${PR_NUMBER}"
mapfile COMMITS < <(gh api repos/${REPO}/pulls/${PR_NUMBER}/commits --jq '.[] | .sha + "|" + (.commit.message | split("\n")[0]) + "|" + .commit.author.name + "|" + .commit.author.email + "|"' || echo "@_ERROR_@")
[[ "${COMMITS[0]}" =~ @_ERROR_@ ]] && {
	error_out "No commits for PR ${PR_NUMBER}"
	exit 1
}

echo "COMMITS array: "
declare -p COMMITS

debug_out "***** There are ${#COMMITS[@]} commits for PR ${PR_NUMBER}"
for commit in "${COMMITS[@]}" ; do
	[[ "$commit" =~ ([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\| ]] || {
		error_out "Unable to parse commit '$commit'"
		exit 1
	}
	SHA=${BASH_REMATCH[1]}
	MESSAGE=${BASH_REMATCH[2]}
	NAME=${BASH_REMATCH[3]}
	EMAIL=${BASH_REMATCH[4]}
	debug_out "Found commit: SHA: $SHA MESSAGE: $MESSAGE NAME: $NAME EMAIL: $EMAIL"
done

branches=${BRANCHES//[\"\|\'|\]|\[]/}
debug_out "***** Cherry-picking to branches: $branches"

declare -a error_msgs
RC=0
IFS=$','
for BRANCH in $branches ; do
	[ -n "${GITHUB_OUTPUT}" ] && echo "::group::Branch $BRANCH"

	debug_out "***** Cherry-picking commits to branch $BRANCH"
	$NO_CLONE || git fetch --no-tags --depth 10 origin refs/heads/$BRANCH:$BRANCH
	git checkout $BRANCH
	
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
			error_out "$msg"
			error_msgs+=( "${msg}" )
			RC=1
			break
		fi
	done
	[ -n "${GITHUB_OUTPUT}" ] && echo "::endgroup::"
done

if $PUSH ; then
	gh auth setup-git -h github.com
	if [ $RC -eq 0 ] ; then
		for BRANCH in $branches ; do
			debug_out "Pushing to branch $BRANCH"
			git checkout ${BRANCH}
			git push --set-upstream origin $BRANCH
		done
	else
		debug_out "Not pushing to any branches due to errors"
	fi
fi

echo "RC: $RC  OUTPUT_DIR: ${OUTPUT_DIR}"
declare -p error_msgs

if [ -n "${OUTPUT_DIR}" ] && [ ${#error_msgs[@]} -gt 0 ] ; then
	debug_out "Writing cherry-pick errors to ${OUTPUT_DIR}/job_summary.txt"
	mkdir -p "${OUTPUT_DIR}"
	for msg in "${error_msgs[@]}" ; do
		echo "$msg" >> "${OUTPUT_DIR}/job_summary.txt"
	done
fi

exit $RC
