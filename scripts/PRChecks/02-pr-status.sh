#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
set -e

assert_env_variables --print PR_STATUS_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

status_count=$(jq -r '. | length' ${PR_STATUS_PATH})
if [ $status_count -eq 0 ] ; then
	debug_out "No status checks.  No checklist item needed."
	exit $EXIT_OK
fi

readarray -d "" -t states < <( jq --raw-output0 '.[].state ' ${PR_STATUS_PATH})
readarray -d "" -t descriptions < <( jq --raw-output0 '.[].description ' ${PR_STATUS_PATH})
readarray -d "" -t contexts < <( jq --raw-output0 '.[].context ' ${PR_STATUS_PATH})

checklist_added=true
for (( status=0 ; status < status_count ; status+=1 )) ; do
	if [ "${states[$status]}" == "success" ] && [ "${contexts[$status]}" == "license/cla" ] ; then
		checklist_added=false
	fi
done

if $checklist_added ; then
	debug_out "Status check failed: Contributor License Agreement is not signed yet."
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] Contributor License Agreement is not signed yet.
	EOF
fi

$checklist_added && exit $EXIT_CHECKLIST_ADDED
debug_out "No issues found."
exit $EXIT_OK
