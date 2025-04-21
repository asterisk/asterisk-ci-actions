#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions
#set -e
shopt -s extglob

assert_env_variables --print PR_PATH PR_COMMITS_PATH PR_COMMENTS_PATH || exit 1

: ${PR_CHECKLIST_PATH:=/dev/stderr}

pr_title=$(jq -j -r '.title' ${PR_PATH})
# We need to strip out any carriage returns('\r') so we can do
# more accurate comparisons.
pr_body=$(jq -j -r '.body | sub("\r";"";"g")' ${PR_PATH})

commit_count=$(jq -r '. | length' ${PR_COMMITS_PATH})
multiple_commits=$(jq -r "[ .[].body | match(\"(^|\r?\n)multiple-commits:[[:blank:]]*(standalone|interim)(\r?\n|$)\"; \"g\") | .captures[1].string ][0]" ${PR_COMMENTS_PATH})

readarray -d "" -t commit_msgs < <( jq --raw-output0 '.[].commit.message | sub("\r";"";"g")' ${PR_COMMITS_PATH})
# The commit title isn't split out for us like the PR title
# so we need to get the first line ourselves.
readarray -d "" -t commit_titles < <( jq --raw-output0 '.[].commit.message  | sub("\r";"";"g") | split("\n")[0]' ${PR_COMMITS_PATH})
# The second line of the commit message should be a blank line.
readarray -d "" -t commit_blanks < <( jq --raw-output0 '.[].commit.message | sub("\r";"";"g") | split("\n")[1] // ""' ${PR_COMMITS_PATH})
# The rest of the commit message is the body.
readarray -d "" -t commit_bodies < <( jq --raw-output0 '.[].commit.message | sub("\r";"";"g") | split("\n")[2:] | join("\n")' ${PR_COMMITS_PATH})

debug_out "Checking for PR description/Commit msg mismatches"
checklist_added=false

if [ $commit_count -eq 1 ] && [ "$pr_title" != "${commit_titles[0]}" ] ; then
	debug_out "PR title and commit title mismatch"
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The PR title does not match the commit title. This can cause 
	confusion for reviewers and future maintainers. 
	GitHub doesn't automatically update the PR title when you update 
	the commit message so if you've updated the commit with a force-push, 
	please update the PR title to match the new commit message body. 
	EOF
	checklist_added=true
fi

pb="${pr_body//+([[:cntrl:]]|[[:blank:]])/ }"
cb="${commit_bodies[0]//+([[:cntrl:]]|[[:blank:]])/ }"

if [ $commit_count -eq 1 ] && [ "${pb}" != "${cb}" ] ; then
	debug_out "PR description and commit message body mismatch."
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The PR description does not match the commit message body. 
	This can cause confusion for reviewers and future maintainers. 
	GitHub doesn't automatically update the PR description when you update 
	the commit message so if you've updated the commit with a force-push, 
	please update the PR description to match the new commit message body. 
	EOF
	checklist_added=true
fi

no_blank_line=false
for (( commit=0 ; commit < commit_count ; commit+=1 )) ; do
	if [ -n "${commit_blanks[$commit]}" ] ; then
		no_blank_line=true
	fi
done

if $no_blank_line ; then
	debug_out "Commit message doesn't contain a blank line after the title."
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] A commit message doesn't contain a blank line after the title.
	EOF
	checklist_added=true
fi

debug_out "Checking commit message for Resolves/Fixes, UpgradeNote and UserNote trailers."

declare -A has_fixes=( ["commit"]=false ["pr"]=false )

has_extra_trailers=false

check_for_extra_trailers() {
	bad_trailers=$(echo "$2" | grep -A999 -E '^(Resolves|Fixes|UserNote|UpgradeNote)' | sed -n -r -e '/^[^ :]+:/!d;/(Resolves|Fixes|UpgradeNote|UserNote)/!p')
	if [ -n "$bad_trailers" ] ; then
		debug_out "${1} has extra trailers: ${bad_trailers}"
		has_extra_trailers=true
	fi
}

# Check PR and commits for extra trailers.
check_for_extra_trailers "pr" "${pr_body}"
for (( commit=0 ; commit < commit_count ; commit+=1 )) ; do
	check_for_extra_trailers "commit" "${commit_bodies[$commit]}"
done

if $has_extra_trailers ; then
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The PR description and/or commit message has unsupported trailers after 
	the \`Resolves\`, \`Fixes\`, \`UserNote\`, and/or \`UpgradeNote\` trailers. 
	Please refrain from adding unsupported trailers as they will confuse the 
	release change log generation.  If you really need them, please move them 
	before any of the supportred trailers and ensure there's a blank line after them.
	EOF
	checklist_added=true
fi

has_bad_fixes=false
check_for_bad_fixes() {
	while read LINE ; do
		# Skip the check if someone typed "Resolves an issue..."
		[[ "$LINE" =~ ^(Resolves|Fixes)[[:blank:]][a-zA-Z] ]] && continue
		[[ "$LINE" =~ (^|[[:cntrl:]])(Fixes|Resolves)([^[:cntrl:]]+) ]] || continue
		keyword=${BASH_REMATCH[2]}
		value=${BASH_REMATCH[3]}
		has_fixes[$1]=true
		debug_out "${1} has a '${keyword}' trailer.  Checking value '${value}'."
		if [[ ! "${value}" =~ ^[:][[:blank:]]([#]([0-9]+|GHSA))|(https://github.com/[^/]+/[^/]+/issues/[0-9]+) ]] || [[ ! "${2}" =~ (^|[[:cntrl:]][[:cntrl:]])${keyword} ]] ; then
			debug_out "${1} '${keyword}' trailer is malformed."
			has_bad_fixes=true
		fi
	done <<< $2 
}

# Check PR and commits for bad fixes.
check_for_bad_fixes "pr" "${pr_body}"
for (( commit=0 ; commit < commit_count ; commit+=1 )) ; do
	check_for_bad_fixes "commit" "${commit_bodies[$commit]}"
done

if $has_bad_fixes ; then
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The PR description and/or commit message has a malformed 
	\`Fixes\` or \`Resolves\` trailer. 
	The \`Fixes\` and \`Resolves\` keywords MUST be preceeded by a blank line 
	and followed immediately by a colon, a space, a hash sign(\`#\`), and the issue number. 
	If you have multiple issues to reference, you can add additional 
	\`Fixes\` and \`Resolves\` trailers on consecutive lines as long as the first 
	one has the preceeding blank line. 
	A malformed trailer will prevent the issue from being automatically closed when 
	the PR merges and from being listed in the release change logs.<br> 
	  Regular expression: \`^(Fixes|Resolves): #[0-9]+$\`.<br> 
	  Example: \`Fixes: #9999\`. 
	EOF
	checklist_added=true
fi

has_stray_refs=false

declare -a stray_issues
check_for_stray_refs() {
	[[ "$2" =~ [[:blank:]](#[0-9]+)[[:blank:]] ]] || return 0
	debug_out "${1} has a stray reference to issue ${BASH_REMATCH[1]}."
	stray_issues+=("${BASH_REMATCH[1]}")
	has_stray_refs=true
}

# Check PR and commits for stray issue references.
if ! ${has_fixes[pr]} ; then
	check_for_stray_refs "pr" "${pr_body}"
fi

if ! ${has_fixes[commit]} ; then
	for (( commit=0 ; commit < commit_count ; commit+=1 )) ; do
		check_for_stray_refs "commit" "${commit_bodies[$commit]}"
	done
fi

if $has_stray_refs ; then
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The PR description and/or commit message references one or more 
	issues ( ${stray_issues[@]} ) without a \`Fixes:\` or \`Resolves:\` 
	keyword. Without those keywords, the issues won't be automatically 
	closed when the PR merges and won't be listed in the release change logs.<br>
	  Regular expression: \`^(Fixes|Resolves): #[0-9]+$\`.<br> 
	  Example: \`Fixes: #9999\`. 
	EOF
	checklist_added=true
fi


has_bad_note=false
check_for_bad_notes() {
	for keyword in UserNote UpgradeNote ; do
		[[ "${2}" =~ (^|[[:cntrl:]])(${keyword})([^[:cntrl:]]+) ]] || continue
		debug_out "${1} has a '${keyword}' trailer.  Checking for ':' and predeeding blank line."
		if [[ ! "${2}" =~ (^|[[:cntrl:]][[:cntrl:]])${keyword}[:][[:blank:]] ]] ; then
			debug_out "${1} '${keyword}' trailer either doesn't have a ':' after the keyword or doesn't have a preceeding blank line."
			has_bad_note=true
		fi
	done
}

# Check PR and commits for notes.
check_for_bad_notes "pr" "${pr_body}"
for (( commit=0 ; commit < commit_count ; commit+=1 )) ; do
	check_for_bad_notes "commit" "${commit_bodies[$commit]}"
done

if $has_bad_note ; then
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] The PR description and/or commit message has malformed 
	\`UserNote\` and/or \`UpgradeNote\` trailers.  The \`UserNote\` and 
	\`UpgradeNote\` keywords MUST be predeeded by a blank line and 
	followed immediately by a colon and a space before 
	the actual note text.  This is to ensure that the note is properly 
	formatted and displayed in the release change logs.
	EOF
	checklist_added=true
fi

if [ "${has_fixes[commit]}" != "${has_fixes[pr]}" ] ; then
	debug_out "Commit has fixes but PR doesn't."
	cat <<-EOF | print_checklist_item --append-newline
	- [ ] Either the PR description has a \`Fixes\` or \`Resolves\` special trailer 
	but the commit mesage doesn't or the other way around. 
	A properly formatted \`Fixes\` or \`Resolves\` 
	trailer is required in the PR description to allow the issue and the PR 
	to be cross-linked and for the issue to be automatically closed when the 
	PR merges. It's also required in the commit message to allow the issue 
	to be listed in the release change logs.
	EOF
	checklist_added=true
fi

$checklist_added && exit $EXIT_CHECKLIST_ADDED
debug_out "No issues found."
exit $EXIT_OK

