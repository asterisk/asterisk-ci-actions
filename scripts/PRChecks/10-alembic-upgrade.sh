#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
set -e

assert_env_variables --print PR_FILES_PATH PR_COMMITS_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

declare -a files=( $(jq '.[].filename' ${PR_FILES_PATH}) )

debug_out "Checking for Alembic changes"
found_alembic_changes=false
for fn in "${files[@]}" ; do
	if [[ $fn =~ ast-db-manage ]] ; then
		debug_out "Found ast-db-manage file: ${fn}."
		found_alembic_changes=true
		break
	fi
done

if ! $found_alembic_changes ; then
	debug_out "No ast-db-manage files found.  No checklist item needed."
	exit $EXIT_OK
fi

debug_out "Checking for UpgradeNote mentioning Alembic in commit message."
checklist_added=false
upgrade_note=$(jq -r '.[].commit.message' ${PR_COMMITS_PATH} | \
	tr -d '\r' | sed -n -r -e '/^UpgradeNote:/,/^$/p' | \
	 tr '[:upper:]' '[:lower:]' | sed -n -r -e 's/.*(alembic|database|schema).*/\1/p')
if [ -z "$upgrade_note" ] ; then
	debug_out "No UpgradeNote mentioning 'alembic', 'database' or 'schema' found.  Adding checklist item."

	cat <<-EOF | print_checklist_item --append-newline
	- [ ] An Alembic change was detected but a commit message UpgradeNote 
	with at least one of the 'alembic', 'database' or 'schema' keywords wasn't found. 
	Please add an UpgradeNote to the commit message that mentions one of those keywords 
	notifying users that there's a database schema change.
	EOF
	checklist_added=true
fi

debug_out "Checking for sample config changes."

found_config_changes=false
for fn in "${files[@]}" ; do
	if [[ $fn =~ configs/samples ]] ; then
		debug_out "Found sample config file: ${fn}."
		found_config_changes=true
		break
	fi
done

if ! $found_config_changes ; then
	debug_out "An alembic change was detected without a sample config change."

	cat <<-EOF | print_checklist_item --append-newline
	- [ ] An Alembic change was detected but no changes were detected to any 
	sample config file. If this PR changes the database schema, it probably 
	should also include changes to the matching sample config files in configs/samples.
	EOF
	checklist_added=true
fi

$checklist_added && exit $EXIT_CHECKLIST_ADDED
debug_out "No issues found."
exit $EXIT_OK
