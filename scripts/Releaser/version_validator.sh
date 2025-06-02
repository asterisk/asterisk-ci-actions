#!/bin/bash
set -e

declare -A options=(
	[save_github_env]="--save-github-env                 # Saves start tag to 'start_tag' in the github environment"
)
SAVE_GITHUB_ENV=false

declare needs=( end_tag )
declare wants=( start_tag src_repo security hotfix norc )
declare tests=( src_repo )

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

declare -A end_tag
tag_parser ${END_TAG} end_tag || bail "Unable to parse end tag '${END_TAG}'"
${DEBUG} && declare -p end_tag

declare -A start_tag
if [ -n "${START_TAG}" ] ; then
	tag_parser ${START_TAG} start_tag || bail "Unable to parse start tag '${START_TAG}'"
	${DEBUG} && declare -p start_tag
fi

if [ -z "${SRC_REPO}" ] ; then
	echo "${progname}: Tags are formatted correctly."
	exit 0
fi

$progdir/get_start_tag.sh $(stringoption start-tag) \
	--end-tag=${END_TAG} --src-repo="${SRC_REPO}" --debug \
	$(booloption SECURITY) $(booloption HOTFIX) $(booloption NORC) \
	$(booloption SAVE_GITHUB_ENV)

exit 0