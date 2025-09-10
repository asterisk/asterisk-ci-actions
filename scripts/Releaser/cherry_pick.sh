#!/bin/bash
set -e

declare needs=( start_tag end_tag src_repo )
declare wants=( gh_repo hotfix force_cherry_pick security advisories adv_url_base )
declare tests=( start_tag src_repo )

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

debug "End tag: ${END_TAG}"
declare -A end_tag
tag_parser ${END_TAG} end_tag || bail "Unable to parse end tag '${END_TAG}'"
debug "$(declare -p end_tag)"

debug "Start tag: ${START_TAG}"
declare -A start_tag
tag_parser ${START_TAG} start_tag || bail "Unable to parse start tag '${START_TAG}'"
debug "$(declare -p start_tag)"

git -C "${SRC_REPO}" checkout ${end_tag[branch]}
PREVIOUS=$(git -C "${SRC_REPO}" --no-pager log --oneline -1 --format="%H %s")
PREVIOUS_SUBJECT="${PREVIOUS#* }"
PREVIOUS_HEAD="${PREVIOUS%% *}"


cd "${SRC_REPO}"

if [ "${end_tag[release]}" != "-rc1" ] && ! ${FORCE_CHERRY_PICK} ; then
	debug "Automatic cherry-picking only needed when
	creating an rc1. Skipping."
	exit 0
fi

RC=0

${FORCE_CHERRY_PICK} && debug "Forcing cherry-pick" || :
commitlist=$(mktemp -p /tmp commitlist.XXXXX)

# Get all the commits in the development branch that aren't in the
# release branch.  They'll have a '+' in the git-cherry output.
git -C "${SRC_REPO}" cherry -v ${end_tag[branch]} ${end_tag[source_branch]} |\
	sed -n -r -e "s/^[+]\s?(.*)/\1/gp" > ${commitlist}

declare -a commit_hashes=( $(sed -n -r -e "s/([^ ]+)\s+.*/\1/gp" ${commitlist}) )

commit_count=${#commit_hashes[@]}
[ $commit_count -eq 0 ] && bail "There were no commits to cherry-pick"

# Hack Alert!
# It's possible that a commit in the development branch is already in the
# release branch but with a small content different that makes git think
# they're not the same commit.  In this case, git will try to cherry pick
# it again and fail.  To get around this, for each commit in the development
# branch, we'll do a search in the release branch for the same commit author,
# author date, and commit summary to see if it exists.  If it does, we'll
# skip cherry-picking that commit.
debug "Retrieving details for ${commit_count} commits"
mapfile -t commit_details < <(git -C "${SRC_REPO}" --no-pager show -s --format="format:%H|%ae|%at|%s" "${commit_hashes[@]}")

declare -a skipped_commits

debug "Checking for commits that already exist in the dest branch"
for n in $(seq 0 $(( ${#commit_details[@]} - 1 )) ) ; do
	cd="${commit_details[$n]}"
	[[ "$cd" =~ ([a-f0-9]+)[|]([^|]+)[|]([^|]+)[|]([^|]+) ]] || bail "Unable to apply regex to '$cd'"
	# You can't search by author date with git-log directly so we have to get close
	# with the author email and summary, then grep for the date.
	found_in_dest=$(git -C "${SRC_REPO}" --no-pager log --format="tformat:%H|%ae|%at|%s" \
		--author="${BASH_REMATCH[2]}" --grep="${BASH_REMATCH[4]}" ${end_tag[branch]} \
			| grep -m1 ${BASH_REMATCH[3]} ) || :
	[ -n "${found_in_dest}" ] && {
		debug "    SOURCE: ${cd}"
		debug "    DEST:   ${found_in_dest}"
		debug "    Skipping ${BASH_REMATCH[1]}"
		skipped_commits+=( $n )
	}
done

for n in ${skipped_commits[@]} ; do
	unset commit_hashes[$n]
done

commit_count=${#commit_hashes[@]}
debug "Final commit count: $commit_count"

[ $commit_count -eq 0 ] && bail "There were no commits to cherry-pick after filtering dups"

echo "Cherry picking $commit_count commit(s) from ${end_tag[source_branch]} to ${end_tag[branch]}"

${ECHO_CMD} git -C "${SRC_REPO}" cherry-pick --keep-redundant-commits -x ${commit_hashes[@]} || {
	echo "Aborting cherry-pick"
	git -C "${SRC_REPO}" cherry-pick --abort
	echo "Rolling back to previous head ${PREVIOUS_HEAD}: ${PREVIOUS_SUBJECT}"
	git -C "${SRC_REPO}" reset --hard ${PREVIOUS_HEAD}
	RC=1
}

debug "Done"

exit $RC

