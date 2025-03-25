#!/usr/bin/env bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))

source $SCRIPT_DIR/ci.functions

: ${GITHUB_SERVER_URL:="https://github.com"}
: ${PR_NUMBER:=-1}

assert_env_variables REPO REPO_DIR BRANCH GATETEST_COMMAND || exit 1

printvars REPO_DIR BRANCH REPO PR_NUMBER GATETEST_COMMAND

PR_OPTIONS=""
if [ ${PR_NUMBER} -gt 0 ] ; then
	PR_OPTIONS="--pr-number=${PR_NUMBER} --is-cherry-pick"
fi

debug_out "Checking out testsuite"
${SCRIPT_DIR}/checkoutRepo.sh --repo="${REPO}" \
	--repo-dir="${REPO_DIR}" --branch="${BRANCH}" \
	${PR_OPTIONS} || exit 1

echo ${GATETEST_COMMAND} > /tmp/test_commands.json
TEST_NAME=$(jq -j '.name' /tmp/test_commands.json)
TEST_OPTIONS=$(jq -j '.options' /tmp/test_commands.json)
TEST_TIMEOUT=$(jq -j '.timeout' /tmp/test_commands.json)
TEST_CMD=$(jq -j '.testcmd' /tmp/test_commands.json)
TEST_DIR=$(jq -j '.dir' /tmp/test_commands.json)

export_to_github TEST_NAME TEST_OPTIONS TEST_TIMEOUT TEST_CMD TEST_DIR
echo "Testsuite setup complete"
exit 0
