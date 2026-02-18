#!/usr/bin/bash
CHECKS_DIR=$(dirname $(realpath $0))
SCRIPT_DIR=$(dirname ${CHECKS_DIR})

DRY_RUN=false
DOWNLOAD_ONLY=false
DOWNLOAD=true
QUIET_CHECKS=false

source ${SCRIPT_DIR}/ci.functions
source ${CHECKS_DIR}/checks.functions

assert_env_variables REPO PR_NUMBER || exit 1
printvars REPO PR_NUMBER DRY_RUN DOWNLOAD_ONLY DONT_DOWNLOAD QUIET_CHECKS FORCE_CLOSE CHERRY_PICK_VALID_BRANCHES

pr_path=/tmp/pr-${PR_NUMBER}.json
pr_files_path=/tmp/pr-files-${PR_NUMBER}.json
pr_commits_path=/tmp/pr-commits-${PR_NUMBER}.json
pr_comments_path=/tmp/pr-comments-${PR_NUMBER}.json
pr_reviews_path=/tmp/pr-reviews-${PR_NUMBER}.json
pr_status_path=/tmp/pr-status-${PR_NUMBER}.json
pr_timeline_path=/tmp/pr-timeline-${PR_NUMBER}.json
pr_checklist_comment_path=/tmp/pr-checklist-comment-${PR_NUMBER}.md
pr_checklist_path=/tmp/pr-checklist-${PR_NUMBER}.md
org_members_path=/tmp/orgmembers.json

if $DOWNLOAD ; then
	debug_out "Downloading PR,  diff, commits, comments"

	gh api /repos/${REPO}/pulls/${PR_NUMBER} | jq . > ${pr_path}

	gh api --paginate /repos/${REPO}/pulls/${PR_NUMBER}/files | jq . > ${pr_files_path}

	gh api --paginate /repos/${REPO}/pulls/${PR_NUMBER}/commits | jq . > ${pr_commits_path}

	gh api --paginate /repos/${REPO}/issues/${PR_NUMBER}/comments | jq . > ${pr_comments_path}

	gh api --paginate /repos/${REPO}/pulls/${PR_NUMBER}/reviews | jq . > ${pr_reviews_path}

	status_url=$(jq -r '.statuses_url' ${pr_path})
	gh api --paginate /repos/${status_url##*/repos/} | jq . > ${pr_status_path}
	
	gh api --paginate /repos/${REPO}/issues/${PR_NUMBER}/timeline | jq . > ${pr_timeline_path}

	export PR_ORG=$(jq -r '.base.user.login' ${pr_path})
	gh api --paginate /orgs/${PR_ORG}/members | jq . > ${org_members_path}
fi

if $DOWNLOAD_ONLY ; then
	debug_out "Retrieval only.  Exiting."
	exit 0
fi

checklist_review_id=$(jq -r '.[] | select(.state != "DISMISSED" and (.body | startswith("<!--PRCL-->")) ) | .id' ${pr_reviews_path})
checklist_review_label=$(jq -r '.labels[] | select(.name == "has-pr-checklist") | .id' ${pr_path})
if [ -z "$checklist_review_id" ] ; then
	debug_out "No checklist. No reminder needed."
	exit 0
fi
debug_out "Found existing checklist review ${checklist_review_id}"

checklist_reminder_id=$(jq -r '.[] | select(.body | startswith("<!--PRCLREMINDER-->")) | .id' ${pr_comments_path})
checklist_reminder_label=$(jq -r '.labels[] | select(.name == "has-pr-checklist-reminder") | .id' ${pr_path})

if [ -n "$checklist_reminder_id" ] ; then
	debug_out "Found existing checklist reminder ${checklist_reminder_id}.  New one not needed."
	exit 0
fi

approved_id=$(jq -r '.[] | select(.state == "APPROVED" and (.user.login == "jcolp")) | .id' ${pr_reviews_path})
if [ -z "${approved_id}" ] ; then
	debug_out "Not approved.  Reminder not needed."
	exit 0
fi

debug_out "Found approval ${approved_id}.  Reminder needed."

# <!--PRCLREMINDER--> needs to be the first line of the comment.
# This is how we'll find it later.
cat <<-EOF > ${pr_checklist_comment_path}
<!--PRCLREMINDER-->
REMINDER:  Your pull request has been functionally approved by the Asterisk
team lead but you have one or more [outstanding PR Checklist items](https://github.com/${REPO}/pull/${PR_NUMBER}#pullrequestreview-${checklist_review_id})
that must be resolved before your pull request can be merged.
If you need assistance or believe the checklist is in error, mention a team member
in a comment and ask.
EOF

if $DRY_RUN ; then
	cat ${pr_checklist_comment_path} >&2
	exit 0
fi

gh pr edit --repo ${REPO} --add-label "has-pr-checklist-reminder" ${PR_NUMBER}
gh pr comment --repo ${REPO} ${PR_NUMBER} -F "${pr_checklist_comment_path}"

exit 0

