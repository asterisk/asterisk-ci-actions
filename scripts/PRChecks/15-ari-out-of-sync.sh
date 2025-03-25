#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
set -e

assert_env_variables --print PR_FILES_PATH PR_COMMITS_PATH || exit $EXIT_ERROR

: ${PR_CHECKLIST_PATH:=/dev/stderr}

debug_out "Checking for ARI changes"

declare -a files=( $(jq '.[].filename' ${PR_FILES_PATH}) )

declare -i json_files_changed=0
declare -i resource_files_changed=0
for f in "${files[@]}" ; do
	[[ ! "$f" =~ (rest-api/api-docs|res/ari/resource_.*[.]h|res/res_ari_.*[.]c) ]] && continue
	if [[ $f =~ (res_ari_|resource_) ]] ; then
		resource_files_changed+=1
	else 
		json_files_changed+=1
	fi
done

if [ $json_files_changed -eq 0 ] && [ $resource_files_changed -eq 0 ] ; then
	debug_out "No ARI related files found in commit. No checklist item needed."
	exit $EXIT_OK
fi

checklist_added=false
if [ $json_files_changed -eq 0 ] && [ $resource_files_changed -ne 0 ] ; then
	debug_out "    ${files[@]} changed manually! Adding checklist item."
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] There appear to be changes to res/res_ari_*.c and/or res/ari/*.h 
	files but no corresponding changes to the the json files in rest-api/api-docs. 
	The *.c and *.h files are auto-generated from the json files by \`make ari-stubs\` 
	and must not be modified directly.
	EOF
	checklist_added=true
fi

if [ $json_files_changed -ne 0 ] && [ $resource_files_changed -eq 0 ] ; then
	debug_out "    ${files[@]} changed manually! Adding checklist item."
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] There appear to be changes to the json files in rest-api/api-docs 
	but no corresponding changes to the res/res_ari_*.c and/or res/ari/*.h 
	files that are generated from them. You must run \`make ari-stubs\` after 
	modifying any file in rest-api/api-docs and include the changes in your commit.
	EOF
	checklist_added=true
fi

debug_out "    Checking for UpgradeNote mentioning ARI in commit message."
upgrade_note=$(jq -r '.[].commit.message' ${PR_COMMITS_PATH} | \
	tr -d '\r' | sed -n -r -e '/^UpgradeNote:/,/^$/p' | \
	 tr '[:upper:]' '[:lower:]' | sed -n -r -e 's/.*(ari).*/\1/p')

if [ -z "$upgrade_note" ] ; then
debug_out "    No UpgradeNote mentioning 'ARI' found.  Adding checklist item."
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] An ARI change was detected but a commit message UpgradeNote mentioning ARI wasn't found. 
	Please add an UpgradeNote to the commit message that mentions ARI 
	notifying users that there's been a change to the REST resources.
	EOF
	checklist_added=true
fi

$checklist_added && exit $EXIT_CHECKLIST_ADDED
debug_out "No issues found."

exit $EXIT_OK
