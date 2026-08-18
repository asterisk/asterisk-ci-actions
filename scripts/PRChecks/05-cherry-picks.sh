#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
set -e

printvars REPO PR_NUMBER DRY_RUN CHERRY_PICK_VALID_BRANCHES USER_IS_ADMIN
assert_env_variables --print PR_PATH PR_COMMENTS_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

if [ -z "${CHERRY_PICK_VALID_BRANCHES}" ] ; then
	cpvar=$(gh variable --repo=${REPO} get CHERRY_PICK_VALID_BRANCHES || : )
	sfvar=$(gh variable --repo=${REPO} get SECURITY_FIX_BRANCHES || :)
	if [[ "${REPO}" =~ GHSA ]] && [ -n "${sfvar}" ] ; then
		CHERRY_PICK_VALID_BRANCHES="${sfvar}"
	elif [ -n "${cpvar}" ] ; then
		CHERRY_PICK_VALID_BRANCHES="${cpvar}"
	else
		CHERRY_PICK_VALID_BRANCHES='["23","22","20","certified/20.7"]'
	fi
fi

base_branch=$(jq -c '[.base.ref]' "${PR_PATH}")
# If the base branch isn't mmaster, swap things around in CHERRY_PICK_VALID_BRANCHES
if [ "${base_branch}" != "master" ] ; then
	CHERRY_PICK_VALID_BRANCHES=$(jq -c '. - '${base_branch}' + ["master"]' <<<${CHERRY_PICK_VALID_BRANCHES})
	debug_out "   Base branch is ${base_branch} so swapping with master in CHERRY_PICK_VALID_BRANCHES"
	debug_out "   CHERRY_PICK_VALID_BRANCHES=${CHERRY_PICK_VALID_BRANCHES}"
fi

debug_out "    Parsing comments for cherry-pick-to: headers."
mapfile -t CPBRANCHES < <(jq -r '[ .[].body
            | match("(^|\r?\n)cherry-pick-to:[[:blank:]]*(([0-9.]+)|(certified/[0-9.]+)|(master|none))"; "g")
            | .captures[1].string ] | sort | unique[]' ${PR_COMMENTS_PATH})

cpbranches=$(array_join CPBRANCHES)
checklist_added=false

if [ ${#CPBRANCHES[@]} -eq 0 ] ; then
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

debug_out "    Found cherry-pick branches ${cpbranches}."

if [ ${#CPBRANCHES[@]} -eq 1 ] && [ "${CPBRANCHES[0]}" == "none" ]  ; then
	debug_out "Cherry-pick to none found. No checklist item needed."
	exit $EXIT_OK
fi

# if ${USER_IS_ADMIN} ; then
# 	debug_out "User is an admin.  Not checking cherry-pick-to."
# 	exit $EXIT_OK
# fi

debug_out "    Looking for 'cherry-pick-to' headers matching ${CHERRY_PICK_VALID_BRANCHES}."
# Remove any valid branches from the list.  What remains are invalid branches.
invalid=$(array_to_json_array CPBRANCHES | jq -c -r --argjson cpvbranches "${CHERRY_PICK_VALID_BRANCHES}" '. - $cpvbranches')
debug_out "    Invalid branches: ${invalid}."
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
	checklist_added=true
fi

json_array_to_array CHERRY_PICK_MISSING_BRANCHES
json_array_to_array CHERRY_PICK_MISSING_TEST_BRANCHES
debug_out "    Checking for missing branches ${CHERRY_PICK_MISSING_BRANCHES[*]}."

if [ ${#CHERRY_PICK_MISSING_BRANCHES[@]} -gt 0 ] && [ ${#CHERRY_PICK_MISSING_TEST_BRANCHES[@]} -gt 0 ] ; then
	test_missing=false
	for tb in "${CHERRY_PICK_MISSING_TEST_BRANCHES[@]}" ; do
		if is_in_array "${tb}" CPBRANCHES ; then
			test_missing=true
			debug_out "      Found test branch ${tb}."
			break
		fi
	done
	if ${test_missing} ; then
		for mb in "${CHERRY_PICK_MISSING_BRANCHES[@]}" ; do
			if ! is_in_array "${mb}" CPBRANCHES ; then
				debug_out "Cherry-pick-to missing branch ${mb}"
				cat <<-EOF | print_checklist_item --append-newline
				- [ ] Branch \`${mb}\` is  new and should be included in the \`cherry-pick-to\` branches. 
				EOF
				checklist_added=true
			fi
		done
	fi
fi

$checklist_added && exit $EXIT_SKIP_FURTHER_CHECKS

debug_out "cherry-pick-to: ${cpbranches} found.  No checklist item needed."
exit $EXIT_OK

