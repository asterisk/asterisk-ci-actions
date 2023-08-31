#!/bin/bash
set -e

declare needs=( start_tag end_tag )
declare wants=( src_repo dst_dir security advisories adv_url_base )
declare tests=( start_tag src_repo dst_dir )

# Since creating the changelog doesn't make any
# changes, we're not bothering with dry-run.

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

mkdir -p /tmp/${PRODUCT}
TMPFILE1=/tmp/${PRODUCT}/ChangeLog-${END_TAG}.tmp1.md
TMPFILE2=/tmp/${PRODUCT}/ChangeLog-${END_TAG}.tmp2.txt

declare -A end_tag_array
tag_parser ${END_TAG} end_tag_array

debug "$(declare -p end_tag_array)"
# We need to actually check out the branch we're generating
# the changelog for so we can get to the files easily
debug "Checking out ${end_tag_array[branch]}"
git -C "${SRC_REPO}" checkout ${end_tag_array[branch]}  >/dev/null 2>&1 

# This gets a somewhat machine readable list of commits
# that don't include any commit with a subject that starts
# ChangeLog.  This way we don't include the changelog from
# the previous release.
#
# Each commit will start with @#@#@#@ on a separate line
# and end with #@#@#@# on a separate line.  This makes them
# easier to parse later on.  
debug "Getting commit list for ${START_TAG}..HEAD"
git -C "${SRC_REPO}" --no-pager log \
	--format='format:@#@#@#@%nSubject: %s%nAuthor: %an  %nDate:   %as  %n%n%b%n#@#@#@#' \
	-E --grep "^((Add ChangeLog)|(Update for))" --invert-grep ${START_TAG}..HEAD >"${TMPFILE2}"

if [ ! -s "${TMPFILE2}" ] ; then
	bail "There are no commits in the range ${START_TAG}..HEAD.
	Do you need to cherry pick?"
fi

# Get rid of any automated "cherry-picked" or "Change-Id" lines.
sed -i -r -e '/^(\(cherry.+|Change-Id.+)/d' "${TMPFILE2}"


# NOTE:  There are two spaces at the end of each
# link line.  They force newlines when rendered
# are are intentional.

cat <<-EOF >"${TMPFILE1}"

Change Log for Release ${PRODUCT}-${END_TAG}
========================================

Links:
----------------------------------------

 - [Full ChangeLog](https://downloads.asterisk.org/pub/telephony/${PRODUCT}/releases/ChangeLog-${END_TAG}.md)  
 - [GitHub Diff](https://github.com/asterisk/${PRODUCT}/compare/${START_TAG}...${END_TAG})  
 - [Tarball](https://downloads.asterisk.org/pub/telephony/${PRODUCT}/${PRODUCT}-${END_TAG}.tar.gz)  
 - [Downloads](https://downloads.asterisk.org/pub/telephony/${PRODUCT})  

Summary:
----------------------------------------

EOF

# For the summary, we want only the commit subject
debug "Creating summary"

sed -n -r -e "s/^Subject:\s+(.+)/- \1/p" "${TMPFILE2}" \
	>>"${TMPFILE1}"


debug "Creating user notes"
cat <<-EOF >>"${TMPFILE1}"

User Notes:
----------------------------------------

EOF

# We only want commit messages that have UserNote
# headers in them. awk is better at filtering
# paragraphs than sed so we'll use it to find
# the commits then sed to format them.

awk 'BEGIN{RS="@#@#@#@"; ORS="#@#@#@#"} /UserNote/' "${TMPFILE2}" |\
	sed -n -r -e 's/Subject: (.*)/- ### \1/p' -e '/UserNote:/,/(UserNote|UpgradeNote|#@#@#@#)/!d ; s/UserNote:\s+//g ; s/#@#@#@#|UpgradeNote.*|UserNote.*//p ; s/^(.)/  \1/p' \
		>>"${TMPFILE1}"

# We need to check for any left over files in 
# doc/CHANGES-staging.  They will be deleted
# after the first GA release after the GitHub
# migration
if [ -d "${SRC_REPO}/doc/CHANGES-staging" ] ; then
	changefiles=$(find "${SRC_REPO}/doc/CHANGES-staging" -name '*.txt')
	if [ "x${changefiles}" != "x" ] ; then
		for changefile in ${changefiles} ; do
			git -C "${SRC_REPO}" log -1 --format="- ### %s" -- "${changefile}" >>"${TMPFILE1}"
			sed -n -r -e '/^Subject:/d ; /^$/d ; s/^/  /p' "${changefile}" >>"${TMPFILE1}"
			echo ""  >>"${TMPFILE1}"
		done
	fi
fi

debug "Creating upgrade notes"
cat <<-EOF >>"${TMPFILE1}"

Upgrade Notes:
----------------------------------------

EOF

awk 'BEGIN{RS="@#@#@#@"; ORS="#@#@#@#"} /UpgradeNote/' "${TMPFILE2}" |\
	sed -n -r -e 's/Subject: (.*)/- ### \1/p' -e '/UpgradeNote:/,/(UserNote|UpgradeNote|#@#@#@#)/!d  ; s/UpgradeNote:\s+//g ; s/#@#@#@#|UpgradeNote.*|UserNote.*//p; s/^(.)/  \1/p' \
		>>"${TMPFILE1}"

# We need to check for any left over files in 
# doc/UPGRADE-staging.  They will be deleted
# after the first GA release after the GitHub
# migration
if [ -d "${SRC_REPO}/doc/UPGRADE-staging" ] ; then
	changefiles=$(find "${SRC_REPO}/doc/UPGRADE-staging" -name '*.txt')
	if [ "x${changefiles}" != "x" ] ; then
		for changefile in ${changefiles} ; do
			git -C "${SRC_REPO}" log -1 --format="- ### %s" -- "${changefile}" >>"${TMPFILE1}"
			sed -n -r -e '/^Subject:/d ; /^$/d ; s/^/  /p' "${changefile}" >>"${TMPFILE1}"
			echo ""  >>"${TMPFILE1}"
		done
	fi
fi

cat <<-EOF >>"${TMPFILE1}"

Closed Issues:
----------------------------------------

EOF

# Anything that matches the regex is a GitHub issue
# number.  We're going to list the issues here but also
# save them to 'issues_to_close.txt' so we can label them
# later without having to pull them all again.
debug "Getting issues list"
issuelist=( $(sed -n -r -e "s/^\s*(Fixes|Resolves):\s*#([0-9]+)/\2/gp" "${TMPFILE2}" | sort -n | tr '\n' ' ') )
rm "${DST_DIR}/issues_to_close.txt" &>/dev/null || :

if [ ${#issuelist[*]} -gt 0 ] ; then
	debug "Getting ${#issuelist[*]} issue titles from GitHub"
	# We want the issue number and the title formatted like:
	#   - #2: Issue Title
	# which GitHub can do for us using a jq format string.
	for issue in ${issuelist[*]} ; do
		gh --repo=asterisk/$(basename ${SRC_REPO}) issue view $issue \
			--json number,title \
			--jq ". | \"  - #\" + ( .number | tostring) + \": \" + .title" \
			>> "${DST_DIR}/issues_to_close.txt"
	done
	cat "${DST_DIR}/issues_to_close.txt" >>"${TMPFILE1}"
	${DEBUG} && cat "${DST_DIR}/issues_to_close.txt"
else
	touch "${DST_DIR}/issues_to_close.txt"
	debug "No issues"
	echo "None" >> "${TMPFILE1}"
fi

debug "Save as release_notes.md"
cp "${TMPFILE1}" "${DST_DIR}/release_notes.md"


debug "Getting shortlog for authors"
cat <<-EOF >>"${TMPFILE1}"

Commits By Author:
----------------------------------------

EOF

# git shortlog can give us a list of commit authors
# and the number of commits in the tag range.
git -C "${SRC_REPO}" shortlog --grep "^Add ChangeLog" --invert-grep \
	--group="author" --format="- %s" ${START_TAG}..HEAD |\
#	Undent the commits and make headings for the authors
	sed -r -e "s/\s+-(.+)/  -\1/g" --e "s/^([^ ].+)/- ### \1/g" >>"${TMPFILE1}" 

debug "Adding the details"
cat <<-EOF >>"${TMPFILE1}"

Detail:
----------------------------------------

EOF
# Clean up the tags we added to make parsing easier.
sed -r -e "s/^(.)/  \1/g" \
	-e '/@#@#@#@/,/Subject:/p ; s/^  Subject:\s+([^ ].+)/- ### \1/g' \
	"${TMPFILE2}" |\
	 sed -r -e '/\(cherry picked|Change-Id|#@#@#@#|@#@#@#@|Subject:/d' >> "${TMPFILE1}"

cp "${TMPFILE1}" "${DST_DIR}/ChangeLog-${END_TAG}.md"

# Create the email

if [ "${end_tag_array[release_type]}" == "rc" ] ; then
	rt="release candidate ${end_tag_array[release_num]} of "
else
    rt="the release of "
fi

# The 2 spaces after the first line in each paragraph force line breaks.
# They're there on purpose.
if $SECURITY ; then
cat <<-EOF >"${DST_DIR}/email_announcement.md"
The Asterisk Development Team would like to announce security release  
${end_tag_array[certprefix]:+Certified }Asterisk ${end_tag_array[major]}.${end_tag_array[minor]}${end_tag_array[patchsep]}${end_tag_array[patch]}.

The release artifacts are available for immediate download at  
https://github.com/asterisk/$(basename ${SRC_REPO})/releases/tag/${END_TAG}
and
https://downloads.asterisk.org/pub/telephony/${end_tag_array[certprefix]:+certified-}asterisk

EOF
	if [ -n "$ADVISORIES" ] ; then
		IFS=$','
		echo "The following security advisories were resolved in this release:" >> "${DST_DIR}/email_announcement.md"

		for a in $ADVISORIES ; do
			if [ -n "$ADV_URL_BASE" ] ; then
				echo "${ADV_URL_BASE}/$a" >> "${DST_DIR}/email_announcement.md"
			else
				echo "$a" >> "${DST_DIR}/email_announcement.md"
			fi
		done
		echo "" >> "${DST_DIR}/email_announcement.md"
		unset IFS
	fi
else

cat <<-EOF >"${DST_DIR}/email_announcement.md"
The Asterisk Development Team would like to announce  
${rt}${end_tag_array[certprefix]:+Certified }${PRODUCT}-${end_tag_array[major]}.${end_tag_array[minor]}${end_tag_array[patchsep]}${end_tag_array[patch]}.

The release artifacts are available for immediate download at  
https://github.com/asterisk/$(basename ${SRC_REPO})/releases/tag/${END_TAG}
and
https://downloads.asterisk.org/pub/telephony/${end_tag_array[certprefix]:+certified-}${PRODUCT}

This release resolves issues reported by the community  
and would have not been possible without your participation.

Thank You!

EOF
fi
cat "${DST_DIR}/release_notes.md" >>"${DST_DIR}/email_announcement.md"

debug "Create the README"
cp "${SRC_REPO}/README.md" "${DST_DIR}/README-${END_TAG}.md"


debug "Done"