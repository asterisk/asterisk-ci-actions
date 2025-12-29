#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

DRY_RUN=false
DOWNLOAD_ONLY=false
DOWNLOAD=true
QUIET_CHECKS=false
FORCE_CLOSE=false

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions

assert_env_variables REPO PR_NUMBER || exit 1
printvars REPO PR_NUMBER DRY_RUN DOWNLOAD_ONLY DONT_DOWNLOAD QUIET_CHECKS FORCE_CLOSE

pr_path=/tmp/pr-${PR_NUMBER}.json
pr_files_path=/tmp/pr-files-${PR_NUMBER}.json
pr_commits_path=/tmp/pr-commits-${PR_NUMBER}.json
pr_comments_path=/tmp/pr-comments-${PR_NUMBER}.json
pr_reviews_path=/tmp/pr-reviews-${PR_NUMBER}.json
pr_status_path=/tmp/pr-status-${PR_NUMBER}.json
pr_timeline_path=/tmp/pr-timeline-${PR_NUMBER}.json
pr_checklist_comment_path=/tmp/pr-checklist-comment-${PR_NUMBER}.md
pr_checklist_path=/tmp/pr-checklist-${PR_NUMBER}.md

if $DOWNLOAD ; then
	debug_out "Downloading PR,  diff, commits, comments"

	gh api /repos/${REPO}/pulls/${PR_NUMBER} | jq . > ${pr_path}

	gh api /repos/${REPO}/pulls/${PR_NUMBER}/files | jq . > ${pr_files_path}

	gh api /repos/${REPO}/pulls/${PR_NUMBER}/commits | jq . > ${pr_commits_path}

	gh api /repos/${REPO}/issues/${PR_NUMBER}/comments | jq . > ${pr_comments_path}

	gh api /repos/${REPO}/pulls/${PR_NUMBER}/reviews | jq . > ${pr_reviews_path}

	status_url=$(jq -r '.statuses_url' ${pr_path})
	gh api /repos/${status_url##*/repos/} | jq . > ${pr_status_path}
	
	gh api /repos/${REPO}/issues/${PR_NUMBER}/timeline | jq . > ${pr_timeline_path}

	checklist_review_id=$(jq -r '.[] | select(.state != "DISMISSED" and (.body | startswith("<!--PRCL-->")) ) | .id' ${pr_reviews_path})
	if [ -n "$checklist_review_id" ] ; then
		debug_out "Found existing checklist review ${checklist_review_id}"
	fi
	dismissed_checklist_review_id=$(jq -r '.[] | select(.state == "DISMISSED" and (.body | startswith("<!--PRCL-->")) ) | .id' ${pr_reviews_path})
	dismissed_checklist_review_body=$(jq -r '.[] | select(.state == "DISMISSED" and (.body | startswith("<!--PRCL-->")) ) | .body' ${pr_reviews_path})
	dismissed_checklist_review_reason=$(sed -n -r -e "s/.+PRCR:([^ -]+)\s+.*/\1/gp" <<<"${dismissed_checklist_review_body}")
	if [ -n "$dismissed_checklist_review_id" ] ; then
		debug_out "Found existing dismissed checklist review ${dismissed_checklist_review_id}"
		debug_out "Found existing dismissed checklist review reason: ${dismissed_checklist_review_reason}"
	fi
fi

if $DOWNLOAD_ONLY ; then
	debug_out "Retrieval only.  Exiting."
	exit 0
fi

clear_existing_checklist() {
	if [ -n "$checklist_review_id" ] ; then
		force=false
		[ "$1" == "force" ] && force=true || :
		msg="$1"
		debug_out "Removing existing obsolete PR checklist review ${msg}"
		if $DRY_RUN ; then
			debug_out "DRY-RUN: gh api /repos/${REPO}/pulls/${PR_NUMBER}/reviews/${checklist_review_id}/dismissals -f 'event=DISMISS' -X PUT -f'message=Checklist Complete'"
			debug_out "DRY-RUN: gh pr edit --repo ${REPO} --remove-label \"has-pr-checklist\" ${PR_NUMBER}"
		else
			echo "<!--PRCL-->" > ${pr_checklist_comment_path}
			${force} && echo "<!--PRCR:exception -->" >> ${pr_checklist_comment_path} || :
			echo "Pull Request Checklist Complete ${msg}" >> ${pr_checklist_comment_path}
			gh api /repos/${REPO}/pulls/${PR_NUMBER}/reviews/${checklist_review_id} \
				-X PUT  -F "body=@${pr_checklist_comment_path}" > /dev/null
			gh api /repos/${REPO}/pulls/${PR_NUMBER}/reviews/${checklist_review_id}/dismissals -f 'event=DISMISS' -X PUT -f'message=Pull Request Checklist Complete' >/dev/null
			gh pr edit --repo ${REPO} --remove-label "has-pr-checklist" ${PR_NUMBER}
		fi
	fi
}

if $FORCE_CLOSE ; then
	clear_existing_checklist force
	exit 0
fi

[ -f ${pr_checklist_path} ] && rm ${pr_checklist_path}

SCRIPT_ARGS="--repo=${REPO} --pr-number=${PR_NUMBER} \
--pr-path=${pr_path} \
--pr-files-path=${pr_files_path} \
--pr-commits-path=${pr_commits_path} \
--pr-comments-path=${pr_comments_path} \
--pr-reviews-path=${pr_reviews_path} \
--pr-status-path=${pr_status_path} \
--pr-timeline-path=${pr_timeline_path} \
--pr-checklist-path=${pr_checklist_path}"

debug_out "Running PR checks with arguments: ${SCRIPT_ARGS}"

checklist_added=false
skip_checklists=false

for s in $(find ${CHECKS_DIR} -name '[0-9]*.sh' | sort) ; do
	check_name=$(basename $s)
	if $skip_checklists && [ "${check_name:0:2}" != "99" ]; then
		debug_out "Skipping check: ${check_name}"
		continue
	fi
	debug_out "Running check: ${check_name}"
	if $QUIET_CHECKS ; then
		bash $s ${SCRIPT_ARGS} &> /dev/null
	else
		bash $s ${SCRIPT_ARGS}
	fi
	RC=$?
	case $RC in
		$EXIT_OK)
			debug_out "    Check ${check_name} added no checklist items."
			;;
		$EXIT_ERROR)
			debug_out "    Check ${check_name} fatal error.  Exiting."
			exit 1
			;;
		$EXIT_CHECKLIST_ADDED)
			debug_out "    Check ${check_name} added checklist items."
			checklist_added=true
			;;
		$EXIT_SKIP_FURTHER_CHECKS)
			debug_out "    Check ${check_name} requested no more checks."
			checklist_added=true
			skip_checklists=true
			;;
		*)
			debug_out "    Check ${check_name} returned unknown exit code: $RC"
			exit 1
			;;
	esac
done


if ! $checklist_added ; then
	debug_out "No PR checklist items found.  No reminder needed"
	clear_existing_checklist
	exit 0
fi


# <!--PRCL--> needs to be the first line of the comment.
# This is how we'll find it later.
echo "<!--PRCL-->" > ${pr_checklist_comment_path}

# Append the checklist items
cat ${pr_checklist_path} >> ${pr_checklist_comment_path}

if [ -n "$checklist_review_id" ] ; then
	existing_checklist=/tmp/pr-existing-checklist-comment-${PR_NUMBER}.md
	jq -jr '.[] | select( .id == '${checklist_review_id}' ) | .body' ${pr_reviews_path} > ${existing_checklist}
	diff -qEZBwb ${existing_checklist} ${pr_checklist_comment_path} &>/dev/null && {
		debug_out "New checklist same as existing.  Nothing to do"
		exit 0
	}
fi

if $DRY_RUN ; then
	cat ${pr_checklist_comment_path} >&2
fi

if [ -n "$checklist_review_id" ] ; then
	debug_out "Updating existing PR checklist comment"
	if $DRY_RUN ; then
		debug_out "DRY-RUN: gh api /repos/${REPO}/pulls/${PR_NUMBER}/reviews/${checklist_review_id} \
			-X PUT  -F \"body=@${pr_checklist_comment_path}\""
	else
		gh api /repos/${REPO}/pulls/${PR_NUMBER}/reviews/${checklist_review_id} \
			-X PUT  -F "body=@${pr_checklist_comment_path}" > /dev/null
	fi
else
	debug_out "Creating new PR checklist comment"
	if $DRY_RUN ; then
		debug_out "DRY-RUN: gh pr review --repo ${REPO} ${PR_NUMBER} -r -F \"${pr_checklist_comment_path}\""
		debug_out "DRY-RUN: gh pr edit --repo ${REPO} --add-label \"has-pr-checklist\" ${PR_NUMBER}"
	else
		gh pr review --repo ${REPO} ${PR_NUMBER} -r -F "${pr_checklist_comment_path}"
		gh pr edit --repo ${REPO} --add-label "has-pr-checklist" ${PR_NUMBER}
	fi
fi

exit 0
