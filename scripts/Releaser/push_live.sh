#!/bin/bash

declare needs=( end_tag )
declare wants=( product src_repo dst_dir start_tag push_branches push_tarballs )
declare tests=( src_repo dst_dir )

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

declare -A end_tag
tag_parser ${END_TAG} end_tag || bail "Unable to parse end tag '${END_TAG}'"
${DEBUG} && declare -p end_tag

debug "Pushing ${PRODUCT} release ${END_TAG} live"
cd "${SRC_REPO}"

echo "
************************************************
    FUTURE FAILURES NOW REQUIRE RECOVERY
************************************************
"

if ${PUSH_BRANCHES} ; then
	debug "Pushing commits upstream"
	$ECHO_CMD git -C "${SRC_REPO}" checkout ${end_tag[branch]}
	$ECHO_CMD git -C "${SRC_REPO}" push
	debug "Pushing tag upstream"
	$ECHO_CMD git -C "${SRC_REPO}" push origin ${END_TAG}:${END_TAG}
fi

# Creating the release with all the assets seems to
# fail much of the time so we'll create first, then
# upload the assets one at a time.

declare -i RC=0
set -x
gh release create ${END_TAG} \
	--verify-tag \
	$( [ "${end_tag[release_type]}" != "ga" ] && echo "--prerelease" ) \
	--notes-file ${DST_DIR}/email_announcement.md \
	--target ${end_tag[branch]} -t "Asterisk Release ${END_TAG}" || RC=1

if [ $RC -ne 0 ] ; then
	# Try again
	echo "First attempt failed.  Trying again"
	RC=0
	gh release create ${END_TAG} \
		--verify-tag \
		$( [ "${end_tag[release_type]}" != "ga" ] && echo "--prerelease" ) \
		--notes-file ${DST_DIR}/email_announcement.md \
		--target ${end_tag[branch]} -t "Asterisk Release ${END_TAG}" || RC=1
fi

if [ $RC -ne 0 ] ; then
	bail "Unable to create release!"
fi

RC=0
for f in ${DST_DIR}/${PRODUCT}-${END_TAG}* \
	${DST_DIR}/ChangeLog-${END_TAG}.md ${DST_DIR}/ChangeLog-${END_TAG}.html \
	${DST_DIR}/README-${END_TAG}.md ${DST_DIR}/README-${END_TAG}.html ; do
	gh release upload ${END_TAG} --clobber $f || \
		{ echo "Retrying..." ; gh release upload ${END_TAG} --clobber $f ; } || { RC=1 ; break ; }
done

if [ $RC -ne 0 ] ; then
	gh release delete --yes ${END_TAG}
	bail "Unable to attach artifacts.  Release deleted!!  You need to clean up the release branch."
fi

$PUSH_TARBALLS || exit 0

debug "Pushing Asterisk Release ${END_TAG} live"

cat >/tmp/ssh_config <<EOF
UserKnownHostsFile /tmp/known_hosts
CheckHostIP no
StrictHostKeyChecking no
UpdateHostKeys no
EOF

scp -F /tmp/ssh_config -p "${progdir}/common.sh" "${progdir}/downloads_host_publish.sh" \
	${DEPLOY_SSH_USERNAME}@${DEPLOY_HOST}:/home/${DEPLOY_SSH_USERNAME}/

ssh -F /tmp/ssh_config ${DEPLOY_SSH_USERNAME}@${DEPLOY_HOST} \
	/home/${DEPLOY_SSH_USERNAME}/downloads_host_publish.sh \
	--product=${PRODUCT} --end-tag=${END_TAG} --dst-dir=${DEPLOY_DIR}
