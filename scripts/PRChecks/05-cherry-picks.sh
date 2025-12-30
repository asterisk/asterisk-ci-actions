#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
set -e

assert_env_variables --print PR_COMMENTS_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}
: ${CHERRY_PICK_VALID_BRANCHES:='["23","22","20","certified/20.7"]'}

debug_out "    Looking for 'cherry-pick-to' headers."
value=$(jq -c -r "[ .[].body | match(\"(^|\r?\n)cherry-pick-to:[[:blank:]]*(([0-9.]+)|(certified/[0-9.]+)|(master|none))\"; \"g\") | .captures[1].string ]" ${PR_COMMENTS_PATH})

if [ "$value" == "[]" ] ; then
	debug_out "No 'cherry-pick-to' headers found.  Adding checklist item."
	
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The are no \`cherry-pick-to\` headers in any comment in this PR. 
	If the PR applies to more than just the branch it was submitted against, 
	please add a comment with one or more \`cherry-pick-to: <branch>\` headers or a 
	comment with \`cherry-pick-to: none\` to indicate that this PR shouldn't 
	be cherry-picked to any other branch. See the 
	[Code Contribution](https://docs.asterisk.org/Development/Policies-and-Procedures/Code-Contribution/) 
	documentation for more information.
	EOF
	exit $EXIT_CHECKLIST_ADDED
fi

if [ "$value" == '["none"]' ] ; then
	debug_out "Cherry-pick to none found. No checklist item needed."
	exit $EXIT_OK
fi

# Remove any valid branches from the list.  What remains are invalid branches.
invalid=$(echo "${value}" | jq -c -r ". - ${CHERRY_PICK_VALID_BRANCHES}")
# If there are invalid branches, add a checklist item.
if [ "$invalid" != "[]" ] ; then
	# Remove the 'certified' branches from the valid branches
	# because we don't want any user adding them.
	val=$(echo "${CHERRY_PICK_VALID_BRANCHES}" | jq -c -r 'del(.[] | select(test("certified.*"; "g")))')
	debug_out "Invalid cherry-pick-to values found: ${invalid}"
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The following \`cherry-pick-to\` values are invalid: ${invalid//[[:space:]]/,}. 
	Valid values are ${val}.
	EOF
	exit $EXIT_CHECKLIST_ADDED
fi

debug_out "cherry-pick-to: ${value//[[:space:]]/,} found.  No checklist item needed."
exit $EXIT_OK

