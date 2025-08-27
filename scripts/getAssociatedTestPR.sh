#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))
. ${SCRIPT_DIR}/ci.functions

for v in REPO PR_NUMBER ASSOCIATED_TEST_PR_REGEX ; do
	assert_env_variable $v || exit 1
done

jq_exp=".[].body | match(\"${ASSOCIATED_TEST_PR_REGEX}\"; \"g\") | .captures[0].string"
associated_pr=$(gh api /repos/${REPO}/issues/${PR_NUMBER}/comments \
	--jq "$jq_exp") || \
	{
		log_error_msgs "::error::Unable to retrieve comments for /repos/${REPO}/issues/${PR_NUMBER}"
		exit 1
	}

if [ -z "${associated_pr}" ] ; then
	debug_out "No associated PR found (OK)"
	exit 0
fi

debug_out "Associated PR: ${associated_pr}"

if [ -n "$GITHUB_ENV" ] ; then
	echo "ASSOCIATED_TEST_PR=${associated_pr}" >> ${GITHUB_ENV}
fi
if [ -n "$GITHUB_OUTPUT" ] ; then
	echo "ASSOCIATED_TEST_PR=${associated_pr}" >> ${GITHUB_OUTPUT}
fi

echo ${associated_pr}

exit 0
