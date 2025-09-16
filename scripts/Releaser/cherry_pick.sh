#!/bin/bash
set -e

declare needs=( start_tag end_tag )
declare wants=( gh_repo src_repo hotfix force_cherry_pick security advisories adv_url_base )
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

# [ -n "${SRC_REPO}" ] && { cd "${SRC_REPO}" || bail "src-repo '${SRC_REPO}' doesn't exist" ; }
# [ ! -d ./.git ] && bail "src-repo '${PWD}' isn't a git repo"

git checkout ${end_tag[branch]} &>/dev/null
PREVIOUS=$(git --no-pager log --oneline -1 --format="%h %s")
PREVIOUS_SUBJECT="${PREVIOUS#* }"
PREVIOUS_HEAD="${PREVIOUS%% *}"

echo "Current ${end_tag[branch]} HEAD: ${PREVIOUS}"


# We need to get all the commits in teh dev branch not in the release
# branch even for follow-on RC, security or hotfix releases.
commitlist=$(mktemp -p /tmp commitlist.XXXXX)
# Get all the commits in the development branch that aren't in the
# release branch.  They'll have a '+' in the git-cherry output.
git cherry -v ${end_tag[branch]} ${end_tag[source_branch]} |\
	sed -n -r -e "s/^[+]\s?(.*)/\1/gp" > ${commitlist}

declare -a commit_hashes=( $(sed -n -r -e "s/([^ ]+)\s+.*/\1/gp" ${commitlist}) )
commit_count=${#commit_hashes[@]}

echo "There are ${commit_count} commits in ${end_tag[source_branch]} not in ${end_tag[branch]}"

cherry_picker() {
	hash=$1
	type=$2
	# Get the details for the source commit.
	cd=$(git --no-pager show -s --format="format:%h %ae %ai %s" ${hash})
	echo "${type:+${type} }Cherry-picking ${cd}"

	# Attempt the cherry-pick.  If successful, continue with the next one.
	${ECHO_CMD} git cherry-pick ${hash} &>/dev/null && return 0
	# It failed!
	git cherry-pick --abort
	echo "    FAILED!"
	return 1
}

# If we're doing a follow-on RC, security or hotfix release, we need to make
# sure that the commits remaining in the dev branch will cherry-pick cleanly
# onto the commits that were manually cherry-picked into the release branch
# for this release.  If they don't, the next regular release will fail.
if ( [ "${end_tag[release_type]}" == "rc" ] && [ "${end_tag[release_num]}" != "1" ] ) || \
	${SECURITY} || ${HOTFIX} ; then

	echo "Testing cherry-picking ${commit_count} commits remaining in dev branch"
	failed=false
	for hash in ${commit_hashes[@]} ; do
		cherry_picker $hash TEST || { failed=true ; break ; }
	done
	git reset --hard ${PREVIOUS_HEAD} &>/dev/null
	if ${failed} ; then
		bail "A commit from the dev branch failed to test-cherry-pick to the release branch." \
		"This will cause the next regular release to fail!."
	else
		echo "Test cherry-picks succeeded"
	fi
fi

if [ "${end_tag[release]}" != "-rc1" ] && ! ${FORCE_CHERRY_PICK} ; then
	echo "Not an RC1 and FORCE_CHERRY_PICK=false.  Skipping automated cherry-picking."
	exit 0
fi

${FORCE_CHERRY_PICK} && debug "Forcing cherry-pick" || :

[ $commit_count -eq 0 ] && bail "There were no commits to cherry-pick"
echo "Found ${commit_count}commits to cherry-pick"

# Cherry-pick for real.
for hash in ${commit_hashes[@]} ; do
	cherry_picker $hash || {
		git cherry-pick --abort
		git reset --hard ${PREVIOUS_HEAD}
		bail "    FAILED!"
	}
done

[ $commit_count -eq 0 ] && bail "There were no commits cherry-picked"

echo "Cherry-picked $commit_count commits"

exit 0

