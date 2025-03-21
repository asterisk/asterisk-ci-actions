#!/usr/bin/env bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))
source $SCRIPT_DIR/ci.functions

mkdir -p ${TESTSUITE_DIR}
debug_out "Checking out testsuite"
git clone --depth 1 --no-tags -q -b ${BASE_BRANCH} \
	${GITHUB_SERVER_URL}/${TESTSUITE_REPO} ${TESTSUITE_DIR} || {
	log_error_msgs "Failed to clone ${TESTSUITE_REPO} to ${TESTSUITE_DIR}"
	exit 1
}

if [ ! -d ${TESTSUITE_DIR}/.git ] ; then
	log_error_msgs "Failed to clone ${TESTSUITE_REPO} to ${TESTSUITE_DIR}"
	exit 1
fi

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
	git fetch origin refs/pull/${TESTSUITE_TEST_PR}/head || exit 1
	git checkout FETCH_HEAD	-b "pr-${TESTSUITE_TEST_PR}"
	git --no-pager log -1 --oneline
fi

export_to_github TEST_NAME TEST_OPTIONS TEST_TIMEOUT TEST_CMD TEST_DIR
echo "Testsuite setup complete"
exit 0
