#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
set -e

assert_env_variables --print PR_COMMITS_PATH PR_COMMENTS_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

commit_count=$(jq -r '. | length' ${PR_COMMITS_PATH})
if [ $commit_count -eq 1 ] ; then
	debug_out "Only one commit.  No checklist item needed."
	exit $EXIT_OK
fi

debug_out "${commit_count} commits found."

debug_out "Looking for merge commits"
merge=$(jq '.[].commit.message | select(startswith("Merge branch"))' ${PR_COMMITS_PATH})
if [ -n "$merge" ] ; then
	cat <<EOF | print_checklist_item --append-newline
- [ ] There is a Merge commit in this PR.  The Asterisk project doesn't 
use Merge commits so this commit must be removed.
EOF
	# If there was only the good commit and a merge commit
	# we can stop here.
	if [ $commit_count -eq 2 ] ; then
		exit $EXIT_CHECKLIST_ADDED
	fi
fi

debug_out "Looking for 'multiple-commits' headers"
value=$(jq -r "[ .[].body | match(\"(^|\r?\n)multiple-commits:[[:blank:]]*(standalone|interim)(\r?\n|$)\"; \"g\") | .captures[1].string ][0]" ${PR_COMMENTS_PATH})
if [[ "$value" =~ (standalone|interim) ]] ; then
	debug_out "multiple-commits: ${value} found.  No checklist item needed."
	exit $EXIT_OK
fi

debug_out "No 'multiple-commits' header found."
debug_out "Adding squash commits checklist item."

cat <<EOF | print_checklist_item --append-newline
- [ ] There is more than 1 commit in this PR and 
no PR comment with a \`multiple-commits:\` special header. 
Please squash the commits down into 1 or see the 
[Code Contribution](https://docs.asterisk.org/Development/Policies-and-Procedures/Code-Contribution/) 
documentation for how to add the \`multiple-commits:\` header.
EOF

exit $EXIT_CHECKLIST_ADDED
