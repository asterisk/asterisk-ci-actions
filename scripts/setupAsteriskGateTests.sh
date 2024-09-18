#!/usr/bin/env bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))
source $SCRIPT_DIR/ci.functions

echo "Running setup for testsuite tests"

sysctl -w kernel.core_pattern=/tmp/core-%e-%t
chmod 1777 /tmp
GC_TESTSUITE_DIR=$(basename ${TESTSUITE_REPO})
GC_TEST_NAME=${GATETEST_GROUP}-${BASE_BRANCH//\//-}

TESTSUITE_DIR=${GITHUB_WORKSPACE}/${GC_TESTSUITE_DIR}
ASTERISK_DIR=${GITHUB_WORKSPACE}/${REPO_DIR}

mkdir -p ${TESTSUITE_DIR}
echo "Checking out testsuite"
git clone --depth 1 --no-tags -q -b ${BASE_BRANCH} \
	${GITHUB_SERVER_URL}/${TESTSUITE_REPO} ${TESTSUITE_DIR}
git config --global --add safe.directory ${TESTSUITE_DIR}

echo ${GATETEST_COMMAND} > /tmp/test_commands.json
TEST_NAME=$(jq -j '.name' /tmp/test_commands.json)
TEST_OPTIONS=$(jq -j '.options' /tmp/test_commands.json)
TEST_TIMEOUT=$(jq -j '.timeout' /tmp/test_commands.json)
TEST_CMD=$(jq -j '.testcmd' /tmp/test_commands.json)
TEST_DIR=$(jq -j '.dir' /tmp/test_commands.json)

cd ${TESTSUITE_DIR}

if [[ "${TESTSUITE_TEST_PR}" =~ [0-9]+ ]] ; then
	echo "Checking out testsuite PR ${TESTSUITE_TEST_PR}"
	gh pr checkout "${TESTSUITE_TEST_PR}" -b "pr-${TESTSUITE_TEST_PR}" || \
		{ echo "::error::Testsuite PR ${TESTSUITE_TEST_PR} not found" ; exit 1 ; }
	git --no-pager log -1 --oneline
fi

export_to_github GC_TESTSUITE_DIR GC_TEST_NAME ASTERISK_DIR TESTSUITE_DIR \
	TEST_NAME TEST_OPTIONS TEST_TIMEOUT TEST_CMD TEST_DIR
echo "Testsuite setup complete"
exit 0
