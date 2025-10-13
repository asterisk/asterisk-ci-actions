#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))
. ${SCRIPT_DIR}/ci.functions

for v in REPO PR_NUMBER ; do
	assert_env_variable $v || exit 1
done

# Get files from PR
declare -a files=( $(gh api /repos/${REPO}/pulls/${PR_NUMBER}/files --jq '.[].filename') )
declare -a tests
for f in "${files[@]}" ; do
	[[ "$f" =~ ^tests/ ]] || continue
	d=$(dirname "$f")
	if [[ "$f" =~ .+([.]py|test-config.yaml|run-test)$ ]] ; then
		tests+=( "$d" )
	elif [[ "$d" =~ .+/sipp$ ]] ; then
		d=$(dirname "$d")
		tests+=( "$d" )
	elif [[ "$d" =~ .+/ast[0-9]$ ]] ; then
		d=$(dirname $(dirname "$d"))
		tests+=( "$d" )
	fi
done
echo "gatetest_count=${#tests[@]}" >> ${GITHUB_OUTPUT}

if [ ${#tests[@]} -eq 0 ] ; then
	echo "No tests changed"
	exit 0
fi

declare -a sorted=( $( for t in "${tests[@]}" ; do echo "$t" ; done | sort -u) )
testcmd=$( for t in "${sorted[@]}" ; do echo -n "-t $t " ; done )
gatetest_group=gates
echo "gatetest_group=${gatetest_group}" >> ${GITHUB_OUTPUT}
{
  echo 'gatetest_commands<<EOF'
  cat <<-INNEREOF
  {
  "${gatetest_group}": {
      "name": "${gatetest_group}",
      "dir": "tests/CI/output/${gatetest_group}",
      "timeout": 240,
      "step_timeout_minutes": 45,
      "options": "",
      "testcmd": "${testcmd}"
  }
  }
INNEREOF
  echo "EOF"
} >> ${GITHUB_OUTPUT}
echo "Testcmd: $testcmd"

exit 0
