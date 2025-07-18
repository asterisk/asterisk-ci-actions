#!/usr/bin/bash
set -e
SCRIPT_DIR=$(dirname $(readlink -fn $0))
STAGING_DIR=${GITHUB_WORKSPACE}/${PRODUCT}-${NEW_VERSION}

declare needs=( repo repo_dir product new_version security hotfix 
				force_cherry_pick skip_cherry_pick skip_test_builds
				push_branches create_github_release
				push_tarballs send_email mail_list_ga mail_list_rc
				mail_list_cert_ga mail_list_cert_rc mail_list_sec
				adv_url_base deploy_host deploy_dir 
				gpg_private_key deploy_ssh_username deploy_ssh_priv_key
				gh_token )
declare wants=( user_ok )

source ${SCRIPT_DIR}/common.sh

if [ "$USER" != "runner" ] && [ "$USER" != "$USER_OK" ]; then
	cat <<-EOF
	CAUTION: This script may make system-wide changes and is intended
	to be run only by the GitHub Actions runner.  If you are sure you
	want to run this script, re-run it with --user-ok=${USER}
	EOF
	exit 1
fi

END_TAG="${NEW_VERSION}"

declare -A end_tag_array
tag_parser ${END_TAG} end_tag_array || bail "Unable to parse end tag '${END_TAG}'"

if ${end_tag_array[certified]} && [ "${end_tag_array[release_type]}" == "ga" ] && ! ${SECURITY} ; then
	NORC=true
	FORCE_CHERRY_PICK=true
fi

debug "Validating tags"
${SCRIPT_DIR}/version_validator.sh \
	--product=${PRODUCT} \
	$(booloption security) $(booloption hotfix)  $(booloption norc) \
	$(stringoption start-tag) --end-tag=${END_TAG} --debug

debug "Tags valid: ${START_TAG} -> ${END_TAG} Release Type: ${end_tag_array[release_type]}"

if [ -n "${ADVISORIES}" ] ; then
	IFS=$','
	debug "Checking security advisories"
	declare -i failed=0
	for a in ${ADVISORIES} ; do
		summary=$(gh api /repos/${REPO}/security-advisories/$a --jq '.summary' 2>/dev/null || echo "FAILED")
		if [[ "$summary" =~ FAILED$ ]] ; then
			debug "Security advisory $a not found. Bad ID or maybe not published yet."
			failed=1
		else
			debug "Security advisory $a found."
		fi
	done
	[ $failed -gt 0 ] && bail "One or more security advisories were not found" || :
	unset IFS
fi

cd ${GITHUB_WORKSPACE}
mkdir -p ${REPO_DIR}
mkdir -p ${STAGING_DIR}

git clone ${GITHUB_SERVER_URL}/${REPO} ${REPO_DIR} || bail "Unable to clone ${REPO}"

cd ${REPO_DIR}

debug "Checking safe.directory"
git config --global --get safe.directory ${REPO_DIR} &>/dev/null || {
	debug "Setting safe.directory to ${REPO_DIR}"
	git config --global --add safe.directory ${REPO_DIR}
}

debug "Checking out ${end_tag_array[source_branch]}"
git -C ${REPO_DIR} checkout ${end_tag_array[source_branch]} >/dev/null 2>&1
git -C ${REPO_DIR} pull >/dev/null 2>&1 
debug "Checking out ${end_tag_array[branch]}"
git -C ${REPO_DIR} checkout ${end_tag_array[branch]} >/dev/null 2>&1
git -C ${REPO_DIR} pull >/dev/null 2>&1

git -C ${REPO_DIR} config --local user.email "asteriskteam@digium.com"
git -C ${REPO_DIR} config --local user.name "Asterisk Development Team"

START_TAG=$(${SCRIPT_DIR}/get_start_tag.sh --src-repo=${REPO_DIR} \
	--product=${PRODUCT} --debug \
	$(booloption security) $(booloption hotfix) $(booloption norc) \
	$(stringoption start-tag) --end-tag=${END_TAG})

declare -A start_tag_array
tag_parser ${START_TAG} start_tag_array || bail "Unable to parse start tag '${START_TAG}'"

debug "Tags valid: ${START_TAG} Release Type: ${start_tag_array[release_type]} -> ${END_TAG} Release Type: ${end_tag_array[release_type]}"

gh auth setup-git -h github.com

echo $"${GPG_PRIVATE_KEY}" > gpg.key
gpg --import gpg.key
rm gpg.key

eval $(ssh-agent -s)
echo $"${DEPLOY_SSH_PRIV_KEY}" | ssh-add -

debug "Running create_release_artifacts.sh"
${SCRIPT_DIR}/create_release_artifacts.sh \
	--src-repo=${REPO_DIR} --dst-dir=${STAGING_DIR} \
	--gh-repo=${REPO} --debug \
	$(booloption security) $(booloption hotfix) $(booloption norc) \
	$(stringoption advisories) $(stringoption adv-url-base) \
	$(booloption skip-cherry-pick) $(booloption force-cherry-pick) \
	$(booloption skip-test-builds) --product=${PRODUCT} \
	--start-tag=${START_TAG} --end-tag=${END_TAG} \
	$([ "${PRODUCT}" == "asterisk" ] && echo "--alembic" || echo "") \
	--changelog --commit --tag \
	--sign --tarball --patchfile

if ${CREATE_GITHUB_RELEASE} ; then
	${SCRIPT_DIR}/push_live.sh \
		--product=${PRODUCT} \
		--src-repo=${REPO_DIR} --dst-dir=${STAGING_DIR} --debug \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		$(booloption push-branches) $(booloption push-tarballs)
fi

eval $(ssh-agent -k)

echo "email_announcement=${PRODUCT}-${END_TAG}/email_announcement.md" >> ${GITHUB_OUTPUT}

# Determine the correct email list to send the announcement
# to (if any).
if ! ${SEND_EMAIL} ; then
	echo "subject=none" >> ${GITHUB_OUTPUT}
	echo "mail_list=none" >> ${GITHUB_OUTPUT}
	exit 0
fi

echo "release_type=${end_tag_array[release_type]}" >> ${GITHUB_OUTPUT}

if ${SECURITY} ; then
	if ${end_tag_array[certified]} ; then
		echo "subject=Certified ${PRODUCT^} Security Release ${END_TAG}" >> ${GITHUB_OUTPUT}
	else
		echo "subject=${PRODUCT^} Security Release ${END_TAG}" >> ${GITHUB_OUTPUT}
	fi
	echo "mail_list=${MAIL_LIST_SEC}" >> ${GITHUB_OUTPUT}
elif [ "${end_tag_array[release_type]}" == "rc" ] ; then
	if ${end_tag_array[certified]} ; then
		echo "subject=Certified ${PRODUCT^} Release Candidate ${END_TAG}" >> ${GITHUB_OUTPUT}
		echo "mail_list=${MAIL_LIST_CERT_RC}" >> ${GITHUB_OUTPUT}
	else
		echo "subject=${PRODUCT^} Release Candidate ${END_TAG}" >> ${GITHUB_OUTPUT}
		echo "mail_list=${MAIL_LIST_RC}" >> ${GITHUB_OUTPUT}
	fi
elif [ "${end_tag_array[release_type]}" == "ga" ] ; then
	if ${end_tag_array[certified]} ; then
		echo "subject=Certified ${PRODUCT^} Release ${END_TAG}" >> ${GITHUB_OUTPUT}
		echo "mail_list=${MAIL_LIST_CERT_GA}" >> ${GITHUB_OUTPUT}
	else
		echo "subject=${PRODUCT^} Release ${END_TAG}" >> ${GITHUB_OUTPUT}
		echo "mail_list=${MAIL_LIST_GA}" >> ${GITHUB_OUTPUT}
	fi
else
	echo "subject=none" >> ${GITHUB_OUTPUT}
	echo "mail_list=none" >> ${GITHUB_OUTPUT}
fi

debug "Github output:"
cat ${GITHUB_OUTPUT}
exit 0
