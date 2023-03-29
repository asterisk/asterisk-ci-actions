#!/usr/bin/bash
set -x
set -e

SCRIPT_DIR=${GITHUB_WORKSPACE}/$(basename ${GITHUB_ACTION_REPOSITORY})/scripts
ASTERISK_DIR=${GITHUB_WORKSPACE}/asterisk

mkdir -p ${ASTERISK_DIR}
${SCRIPT_DIR}/checkoutAsterisk.sh --asterisk-repo=asterisk/asterisk-gh-test \
	--base-branch=master --is-cherry-pick=false \
	--pr-number=0 --destination=${ASTERISK_DIR}

OUTPUT_DIR=${GITHUB_WORKSPACE}/cache/output
mkdir -p ${OUTPUT_DIR}

cd ${ASTERISK_DIR}
${SCRIPT_DIR}/buildAsterisk.sh --github --branch-name=master \
  --modules-blacklist="test_crypto" \
  --output-dir=${OUTPUT_DIR}

${SCRIPT_DIR}/installAsterisk.sh --github --uninstall-all \
  --branch-name=master --user-group=asteriskci:users \
  --output-dir=${OUTPUT_DIR}

cd ${GITHUB_WORKSPACE}
TESTSUITE_DIR=${GITHUB_WORKSPACE}/testsuite

mkdir -p ${TESTSUITE_DIR}
git clone --depth 1 --no-tags -q -b master \
	${GITHUB_SERVER_URL}/asterisk/testsuite-gh-test ${TESTSUITE_DIR}
git config --global --add safe.directory ${TESTSUITE_DIR}

cd ${TESTSUITE_DIR}

${SCRIPT_DIR}/runTestsuite.sh \
  --timeout=180 \
  --testsuite-command="--test-regex=tests/channels/pjsip/[ab]"


exit

netstat -anup
ip addr
ping -c 5 ::1
nc -l -6 -u -i 5 ::1 5000 &
sleep 1
netstat -anup
nc -6 -u -p 5005 ::1 5000 <<EOF
sdlkjfhsdlkjfg
sdlkfjghdslkjfg
EOF

kill -KILL `pidof nc`

python3 <<EOF
from socket import *

s = socket(AF_INET6, SOCK_DGRAM)
try:

    s.bind(('::1', 0))
    res = s.getsockname()[1]
    print(res)
except error as e:
    # errno = 98 is 'Port already in use'. However, if any error occurs
    # just fail since we probably don't want to bind to it anyway.
    print(e)
    print("{0}/{1} port '{2}' is in use".format(
        socket_type(SOCK_DGRAM), socket_family(AF_INET6), 5000))

s.close()
EOF



exit
