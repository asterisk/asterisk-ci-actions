#!/bin/bash
set -e

declare needs=( end_tag dst_dir )
declare wants=( product src_repo gh_repo dst_dir security hotfix norc advisories
				adv_url_base skip_cherry_pick force_cherry_pick
				skip_test_builds alembic
				changelog commit tag push_branches tarball patchfile
				sign full_monty dry_run )
declare tests=( src_repo dst_dir )

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

declare -A end_tag
tag_parser ${END_TAG} end_tag || bail "Unable to parse end tag '${END_TAG}'"
${DEBUG} && declare -p end_tag

if ${end_tag[certified]} && [ "${end_tag[release_type]}" == "ga" ] && ! ${SECURITY} ; then
	NORC=true
	FORCE_CHERRY_PICK=true
fi

if [ -z "${START_TAG}" ] ; then
	START_TAG=$($progdir/get_start_tag.sh \
		--end-tag=${END_TAG} --src-repo="${SRC_REPO}" \
		$(booloption security) $(booloption hotfix) $(booloption norc) $(booloption debug) )
fi
if [ -z "${START_TAG}" ] ; then
	bail "can't determine a start tag"
fi

debug "Start tag: ${START_TAG}"
declare -A start_tag
tag_parser ${START_TAG} start_tag || bail "Unable to parse start tag '${START_TAG}'"
debug "$(declare -p start_tag)"

${ECHO_CMD} git -C "${SRC_REPO}" checkout ${end_tag[branch]}
cd "${SRC_REPO}"

CHERRY_PICK=true
if ${SKIP_CHERRY_PICK} ; then
	debug "Skipping cherry-pick"
	CHERRY_PICK=false
fi

if ${CHERRY_PICK} ; then
	debug "Cherry-picking ${START_TAG} -> ${END_TAG}"
	$ECHO_CMD $progdir/cherry_pick.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption security) $(booloption hotfix) \
		$(booloption debug) $(booloption force_cherry_pick)
fi

if ! ${SKIP_TEST_BUILDS} ; then
	CI_SCRIPT_DIR=$(dirname ${progdir})
	debug "Running production buildAsterisk.sh for ${END_TAG}"
	$ECHO_CMD ${CI_SCRIPT_DIR}/buildAsterisk.sh \
		--distclean --no-dev-mode --build-native --optimize
	debug "Running dev-mode buildAsterisk.sh for ${END_TAG}"
	$ECHO_CMD ${CI_SCRIPT_DIR}/buildAsterisk.sh \
		--distclean --dev-mode --build-native --no-optimize --compile-double
fi

if ${CHANGELOG} ; then
	debug "Creating ChangeLog for ${START_TAG} -> ${END_TAG}"
	$ECHO_CMD $progdir/create_changelog.sh --start-tag=${START_TAG} \
		--end-tag=${END_TAG} --src-repo="${SRC_REPO}" --gh-repo="${GH_REPO}" \
		--dst-dir="${DST_DIR}" \
		$(booloption security) $(booloption hotfix) $(booloption norc) \
		$([ -n "$ADVISORIES" ] && echo "--advisories=$ADVISORIES") \
		$([ -n "$ADV_URL_BASE" ] && echo "--adv-url-base=$ADV_URL_BASE") \
		$(booloption debug) --product=${PRODUCT}
fi

if ${ALEMBIC} && [ "${PRODUCT}" == "asterisk" ] ; then
	debug "Creating Alembic scripts for ${END_TAG}"
	$ECHO_CMD $progdir/create_alembic_scripts.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption debug)
fi

echo "${END_TAG}" > ${DST_DIR}/.version
if ${COMMIT} ; then
	${ALEMBIC} || ${CHANGELOG} || bail "There were no changes so so there's nothing to commit"
	debug "Committing changes for ${END_TAG}"
	$ECHO_CMD $progdir/commit_changes.sh --start-tag=${START_TAG} \
		--end-tag=${END_TAG} --src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption security) $(booloption hotfix) $(booloption norc) \
		--product=${PRODUCT} $(booloption alembic) $(booloption debug)
fi

if ${TAG} ; then
	${COMMIT} || bail "There was no commit so there's nothing to tag"
	debug "Creating tag for ${END_TAG}"
	$ECHO_CMD git -C "${SRC_REPO}" checkout ${end_tag[branch]}
	$ECHO_CMD git -C "${SRC_REPO}" tag -a ${END_TAG} -m ${END_TAG}
fi

if ${TARBALL} ; then
	debug "Creating tarball for ${END_TAG}"
	$ECHO_CMD $progdir/create_tarball.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		--product=${PRODUCT} $(booloption sign) \
		$(booloption debug)
fi

if ${PATCHFILE} && [ "${start_tag[release_type]}" != "pre" ] ; then
	debug "Creating patchfile for ${END_TAG}"
	$ECHO_CMD $progdir/create_patchfile.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		--product=${PRODUCT} \
		$(booloption sign) $(booloption debug)
fi
