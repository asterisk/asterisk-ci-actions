#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions

assert_env_variables --print PR_CHECKLIST_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

print_checklist_item --prepend-newline=1 --append-newline=1 --preserve-newlines --no-check-name <<-EOF
Documentation:<br>
* [Asterisk Developer Documentation](https://docs.asterisk.org/Development/)<br>
  * [Code Contribution](https://docs.asterisk.org/Development/Policies-and-Procedures/Code-Contribution/)<br>
  * [Commit Messages](https://docs.asterisk.org/Development/Policies-and-Procedures/Commit-Messages)<br>
  * [Alembic Scripts](https://docs.asterisk.org/Development/Reference-Information/Other-Reference-Information/Alembic-Scripts/)<br>
EOF

exit $EXIT_OK
