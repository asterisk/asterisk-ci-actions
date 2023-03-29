#!/usr/bin/bash
set -x
ip addr
printenv
ls -al /github/workspace/
ls -al /home/runner/work/asterisk-gh-test/asterisk-gh-test/
mkdir /tmp/output
pwd
#cd asterisk
#${GITHUB_ACTION_PATH}/../scripts/installAsterisk.sh --github --uninstall-all \
#	--branch-name=${BRANCH} --user-group=asteriskci:users \
#	--output-dir=/tmp/output
