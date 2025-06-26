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
commitlist=$(mktemp)
git -C "${SRC_REPO}" cherry -v ${end_tag[branch]} ${end_tag[source_branch]} |\
	sed -n -r -e "s/^[+]\s?(.*)/\1/gp" > ${commitlist}

if [ ! -f "${SRC_REPO}/.lastclean" ] ; then
	sed -i -r -e "/Remove .lastclean and .version from source control/d" ${commitlist}
fi

if [ ! -f "${SRC_REPO}/CHANGES" ] && [ ! -f "${SRC_REPO}/UPGRADE.txt" ] ; then
	sed -i -r -e "/Remove files that are no longer updated/d" ${commitlist}
fi

commitcount=$(wc -l ${commitlist} | sed -n -r -e "s/([0-9]+).*/\1/gp")
[ $commitcount -eq 0 ] && bail "There were no commits to cherry-pick"
echo "Cherry picking $commitcount commit(s) from ${end_tag[source_branch]} to ${end_tag[branch]}"
${DEBUG} && cat ${commitlist}
sed -i -r -e "s/([^ ]+)\s+.*/\1/g" ${commitlist}
echo git -C "${SRC_REPO}" cherry-pick --keep-redundant-commits -x $(< ${commitlist})
${ECHO_CMD} git -C "${SRC_REPO}" cherry-pick --keep-redundant-commits -x $(< ${commitlist}) || { 
	echo "Aborting cherry-pick"
	git -C "${SRC_REPO}" cherry-pick --abort
	echo "Rolling back to previous head ${PREVIOUS_HEAD}: ${PREVIOUS_SUBJECT}"
	git -C "${SRC_REPO}" reset --hard ${PREVIOUS_HEAD}
	RC=1
}
${ECHO_CMD} rm ${commitlist} &>/dev/null || :
debug "Done"

exit $RC

