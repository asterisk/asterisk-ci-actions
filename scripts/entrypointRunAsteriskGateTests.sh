#!/usr/bin/bash
set -x
set -e

export GITHUB_TOKEN=${INPUT_GITHUB_TOKEN}
export GH_TOKEN=${INPUT_GITHUB_TOKEN}

SCRIPT_DIR=${GITHUB_WORKSPACE}/$(basename ${GITHUB_ACTION_REPOSITORY})/scripts
ASTERISK_DIR=${GITHUB_WORKSPACE}/$(basename ${INPUT_ASTERISK_REPO})
OUTPUT_DIR=${GITHUB_WORKSPACE}/${INPUT_CACHE_DIR}/output

[ ! -d ${SCRIPT_DIR} ] && { echo "::error::SCRIPT_DIR ${SCRIPT_DIR} not found" ; exit 1 ; } 
[ ! -d ${ASTERISK_DIR} ] && { echo "::error::ASTERISK_DIR ${ASTERISK_DIR} not found" ; exit 1 ; } 
[ ! -d ${OUTPUT_DIR} ] && { echo "::error::OUTPUT_DIR ${OUTPUT_DIR} not found" ; exit 1 ; } 

cd ${ASTERISK_DIR}

${SCRIPT_DIR}/installAsterisk.sh --github --uninstall-all \
  --branch-name=${INPUT_BASE_BRANCH} --user-group=asteriskci:users \
  --output-dir=${OUTPUT_DIR}

cd ${GITHUB_WORKSPACE}

TESTSUITE_DIR=${GITHUB_WORKSPACE}/$(basename ${INPUT_TESTSUITE_REPO})
mkdir -p ${TESTSUITE_DIR}
git clone --depth 1 --no-tags -q -b ${INPUT_BASE_BRANCH} \
	${GITHUB_SERVER_URL}/${INPUT_TESTSUITE_REPO} ${TESTSUITE_DIR}
git config --global --add safe.directory ${TESTSUITE_DIR}

echo ${INPUT_GATETEST_COMMAND} > /tmp/test_commands.json
TEST_NAME=$(jq -j '.name' /tmp/test_commands.json)
TEST_OPTIONS=$(jq -j '.options' /tmp/test_commands.json)
TEST_TIMEOUT=$(jq -j '.timeout' /tmp/test_commands.json)
TEST_CMD=$(jq -j '.testcmd' /tmp/test_commands.json)
TEST_DIR=$(jq -j '.dir' /tmp/test_commands.json)

cd ${TESTSUITE_DIR}

if [[ "${INPUT_TESTSUITE_TEST_PR}" =~ [0-9]+ ]] ; then
	echo "Checking out testsuite PR ${INPUT_TESTSUITE_TEST_PR}"
	gh pr checkout "${INPUT_TESTSUITE_TEST_PR}" -b "pr-${INPUT_TESTSUITE_TEST_PR}" || \
		{ echo "::error::Testsuite PR ${INPUT_TESTSUITE_TEST_PR} not found" ; exit 1 ; }
fi

TESTRC=0
${SCRIPT_DIR}/runAsteriskGateTests.sh \
  --test-timeout=${TEST_TIMEOUT} \
  --testsuite-command="${TEST_OPTIONS} ${TEST_CMD}" || TESTRC=1
exit $TESTRC
