#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions

assert_env_variables --print PR_CHECKLIST_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

# The introduction is wrapped here for convenience but the
# newlines are stripped out so the PR webpage can handle wrapping.
print_checklist_item --append-newline=2 --no-check-name <<-EOF
**Attention!** This pull request may contain issues that could 
prevent it from being accepted.  Please review the checklist below 
and take the recommended action.  If you believe any of these are 
not applicable, just add a comment and let us know.
EOF

exit $EXIT_OK
