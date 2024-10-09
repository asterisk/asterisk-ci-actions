#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))
PROGNAME=$(basename $(readlink -fn $0))
. ${SCRIPT_DIR}/ci.functions

[ -z "${GH_TOKEN}" ] && { echo "${PROGNAME}: GH_TOKEN must be passed as an environment variable" >&2 ; exit 1 ; }
[ -z "${REPO}" ] && { echo "${PROGNAME}: --repo=<owner/repo> required" >&2 ; exit 1 ; }
[ -z "${PR_NUMBER}" ] && { echo "${PROGNAME}: --pr-number=<asterisk pr number> required"  >&2 ; exit 1 ; }
[ -z "${TESTSUITE_PR_REGEX}" ] && { echo "${PROGNAME}: --testsuite-pr-regex=<testsuite pr regex> required" >&2 ; exit 1 ; }

jq_exp=".[].body | match(\"${TESTSUITE_PR_REGEX}\"; \"g\") | .captures[0].string"
testsuite_pr=$(gh api /repos/${REPO}/issues/${PR_NUMBER}/comments \
  --jq "$jq_exp") || \
  { echo "${PROGNAME}: Unable to retrieve comments for /repos/${REPO}/issues/${PR_NUMBER}" >&2 ; exit 1 ; }

if [ -n "${testsuite_pr}" ] ; then
  echo "${PROGNAME}: Testsuite PR: ${testsuite_pr}" >&2
  echo ${testsuite_pr}
else
  echo "${PROGNAME}: No Testsuite PR found (OK)" >&2
fi

exit 0
