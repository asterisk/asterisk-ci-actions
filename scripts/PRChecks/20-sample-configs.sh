#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
set -e

assert_env_variables --print PR_FILES_PATH PR_COMMITS_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

declare -a files=( $(jq '.[].filename' ${PR_FILES_PATH}) )

debug_out "Checking for sample config files or alembic changes."
found_sample_changes=false
found_alembic_changes=false
found_pjsip_changes=false
for fn in "${files[@]}" ; do
	if [[ $fn =~ configs/samples/.*[.]sample ]] ; then
		debug_out "    Found sample config file: ${fn}."
		found_sample_changes=true
	fi
	if [[ $fn =~ configs/samples/pjsip.*[.]sample ]] ; then
		debug_out "    Found pjsip sample config file: ${fn}."
		found_pjsip_changes=true
	fi
	if [[ $fn =~ ast-db-manage ]] ; then
		debug_out "    Found ast-db-manage file: ${fn}."
		found_alembic_changes=true
	fi
done

if ! $found_sample_changes ; then
	debug_out "No sample config changes detected.  No checklist item needed."
	exit $EXIT_OK
fi

debug_out "Checking for Upgrade/UserNote."
checklist_added=false

upgrade_note=$(jq -r '.[].commit.message' ${PR_COMMITS_PATH} | \
	tr -d '\r' | sed -n -r -e '/^(User|Upgrade|Developer)Note:/,/^$/p')
if [ -z "$upgrade_note" ] ; then
	debug_out "    No Upgrade/UserNote."

	cat <<-EOF | print_checklist_item --append-newline
	- [ ] A change was detected to the sample configuration files in ./config/samples 
	but no UserNote or UpgradeNote was found in the commit message. If this PR 
	includes changes that contain new configuration parameters or a change 
	to existing parameters, please include a UserNote in the 
	commit message.  If the changes require some action from the user to 
	preserve existing behavior, please include an UpgradeNote.
	EOF
	checklist_added=true
fi

debug_out "    Checking for pjsip change but no alembic change."
if $found_pjsip_changes && ! $found_alembic_changes ; then
	debug_out "    pjsip config change detected with no alembic change."

	cat <<-EOF | print_checklist_item --append-newline
	- [ ] A change was detected to the pjsip sample configuration files in 
	./config/samples but no Alembic change was detected. If this PR includes 
	changes that contain new configuration parameters or a change to existing 
	configuration parameters for pjsip, chances are that a change to the realtime 
	database schema is also required.
	EOF
	checklist_added=true
fi

$checklist_added && exit $EXIT_CHECKLIST_ADDED
debug_out "No issues found."

# NOTE: changes to alembic without changes to sample configs are handled in
# 10-alembic-upgrade.sh

exit $EXIT_OK
