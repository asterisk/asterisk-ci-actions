#!/usr/bin/bash
set -x
set -e

SCRIPT_DIR=${GITHUB_WORKSPACE}/$(basename ${GITHUB_ACTION_REPOSITORY})/scripts
ASTERISK_DIR=${GITHUB_WORKSPACE}/asterisk

mkdir -p ${ASTERISK_DIR}
${SCRIPT_DIR}/checkoutAsterisk.sh --asterisk-repo=${INPUT_ASTERISK_REPO} \
	--base-branch=${INPUT_BASE_BRANCH} --is-cherry-pick=${INPUT_IS_CHERRY_PICK} \
	--pr-number=${INPUT_PR_NUMBER} --destination=${ASTERISK_DIR}

OUTPUT_DIR=${GITHUB_WORKSPACE}/cache/output
mkdir -p ${OUTPUT_DIR}

cd ${ASTERISK_DIR}
${SCRIPT_DIR}/buildAsterisk.sh --github --branch-name=${INPUT_BASE_BRANCH} \
  --modules-blacklist="${INPUT_MODULES_BLACKLIST// /}" \
  --output-dir=${OUTPUT_DIR}
