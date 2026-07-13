#!/usr/bin/bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))

source ${SCRIPT_DIR}/ci.functions
set -e

for v in REPO PR_NUMBER CHERRY_PICK_REGEX ; do
	assert_env_variable $v || exit 1
done

print_output() {
	output="{ \"forced_none\": $1, \"branch_count\": $2, \"branches\": $3 }"
	debug_out "Output: $output"
	echo "$output"
	if [ -n "$GITHUB_ENV" ] ; then
		echo "FORCED_NONE=$1" >> ${GITHUB_ENV}
		echo "BRANCH_COUNT=$2" >> ${GITHUB_ENV}
		echo "BRANCHES=$3" >> ${GITHUB_ENV}
	fi
	if [ -n "$GITHUB_OUTPUT" ] ; then
		echo "FORCED_NONE=$1" >> ${GITHUB_OUTPUT}
		echo "BRANCH_COUNT=$2" >> ${GITHUB_OUTPUT}
		echo "BRANCHES=$3" >> ${GITHUB_OUTPUT}
	fi
}

gh api --paginate "/repos/${REPO}/issues/${PR_NUMBER}/comments" > "/tmp/pr-${PR_NUMBER}-comments.json"

branches=$( jq -c -r --arg CPR "${CHERRY_PICK_REGEX}" '[ .[].body | match($CPR; "g") | .captures[0].string  ] | unique' "/tmp/pr-${PR_NUMBER}-comments.json" )
branch_count=$(jq '. | length' <<<"${branches}")
debug_out "Branch list: ${branches}"

if [[ "${branches}" =~ none ]] ; then
	print_output true 0 '[]'
	exit 0
fi

print_output false "${branch_count}" "${branches}"

exit 0
