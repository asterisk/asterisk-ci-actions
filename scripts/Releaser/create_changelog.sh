#!/bin/bash
set -e

declare needs=( start_tag end_tag )
declare wants=( src_repo gh_repo dst_dir hotfix security advisories adv_url_base )
declare tests=( start_tag src_repo dst_dir )

# Since creating the changelog doesn't make any
# changes, we're not bothering with dry-run.

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

TMPDIR=/tmp/${PRODUCT}
mkdir -p ${TMPDIR}
TMPFILE1=${TMPDIR}/ChangeLog-${END_TAG}.tmp1.md
TMPFILE2=${TMPDIR}/ChangeLog-${END_TAG}.tmp2.txt

declare -A start_tag_array
tag_parser ${START_TAG} start_tag_array
debug "$(declare -p start_tag_array)"

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

echo -n "" >"${TMPFILE2}"

# If this is a new non-certified major release, we need to
# get the commits that are in the new release that aren't
# in the last GA branch first.
if ! ${start_tag_array[certified]} && [ "${start_tag_array[release_type]}" == "pre" ] ; then
	debug "New major release: ${END_TAG}"
	lastmajor=$(( ${end_tag_array[major]} - 1 ))
	lastlastmajor=$(( ${lastmajor} - 1 ))
	git -C "${SRC_REPO}" fetch origin ${lastlastmajor}:${lastlastmajor}
	git -C "${SRC_REPO}" fetch origin ${lastmajor}:${lastmajor}
	git -C "${SRC_REPO}" cherry -v $lastmajor ${end_tag_array[major]} | grep "^+ " >"${TMPDIR}/majorchanges1.txt"
#	The "cherry" operation will include some cherry-picks that
#   had minor changes between branches so we'll need to weed those out.
#   Get a list of commits from the last branch:
	echo -n "" >"${TMPDIR}/majorchanges2.txt"
	git -C "${SRC_REPO}" --no-pager log --oneline ${lastlastmajor}..$lastmajor > "${TMPDIR}/lastchanges.txt"
#	Now only print the ones that aren't in that list.
	while read PLUS SHA MSG ; do
		[[ "$MSG" =~ ^((Add ChangeLog)|(Update for)) ]] && continue || :
		grep -q "$MSG" "${TMPDIR}/lastchanges.txt" && continue || :
		git -C "${SRC_REPO}" --no-pager log -1 \
			--format='format:@#@#@#@%nSubject: %<(80,trunc)%s%nAuthor: %an  %nDate:   %as  %n%n%b%n#@#@#@#%n' \
			-E --grep "^((Add ChangeLog)|(Update for))" --invert-grep $SHA >>"${TMPFILE2}"
	done < "${TMPDIR}/majorchanges1.txt"
fi

# If this is a new certified major release/branch, we need to find
# the last GA certified tag to produce the change log from.

if ${start_tag_array[certified]} && [ "${start_tag_array[release_type]}" == "pre" ] ; then
	new_start=$(git -C "${SRC_REPO}" --no-pager tag --sort="v:refname" --list "certified-*cert[0-9]" | tail -1)
	START_TAG=$new_start
	unset start_tag_array
	declare -A start_tag_array
	tag_parser ${START_TAG} start_tag_array
	debug "$(declare -p start_tag_array)"
fi

debug "Getting commit list for ${START_TAG}..HEAD"
git -C "${SRC_REPO}" --no-pager log \
	--format='format:@#@#@#@%nSubject: %<(80,trunc)%s%nAuthor: %an  %nDate:   %as  %n%n%b%n#@#@#@#' \
	-E --grep "^(([.]github)|(Add\s+ChangeLog)|(Update[s]?\s+for)|(Update\s+CHANGES))" --invert-grep ${START_TAG}..HEAD >>"${TMPFILE2}"

if [ ! -s "${TMPFILE2}" ] ; then
	bail "There are no commits in the range ${START_TAG}..HEAD.
	Do you need to cherry pick?"
fi

echo "" >>"${TMPFILE2}"

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

 - [Full ChangeLog](https://downloads.asterisk.org/pub/telephony/${end_tag_array[download_dir]}/releases/ChangeLog-${END_TAG}.md)  
 - [GitHub Diff](https://github.com/asterisk/${PRODUCT}/compare/${START_TAG}...${END_TAG})  
 - [Tarball](https://downloads.asterisk.org/pub/telephony/${end_tag_array[download_dir]}/${PRODUCT}-${END_TAG}.tar.gz)  
 - [Downloads](https://downloads.asterisk.org/pub/telephony/${end_tag_array[download_dir]})  

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

debug "Creating upgrade notes"
cat <<-EOF >>"${TMPFILE1}"

Upgrade Notes:
----------------------------------------

EOF

awk 'BEGIN{RS="@#@#@#@"; ORS="#@#@#@#"} /UpgradeNote/' "${TMPFILE2}" |\
	sed -n -r -e 's/Subject: (.*)/- ### \1/p' -e '/UpgradeNote:/,/(UserNote|UpgradeNote|#@#@#@#)/!d  ; s/UpgradeNote:\s+//g ; s/#@#@#@#|UpgradeNote.*|UserNote.*//p; s/^(.)/  \1/p' \
		>>"${TMPFILE1}"

cat <<-EOF >>"${TMPFILE1}"

Closed Issues:
----------------------------------------

EOF

# Anything that matches the regex is a GitHub issue
# number.  We're going to list the issues here but also
# save them to 'issues_to_close.txt' so we can label them
# later without having to pull them all again.

rm "${DST_DIR}/issues_to_close.txt" &>/dev/null || :

debug "Getting GitHub security advisory list"
ghsalist=( $(sed -n -r -e "s/^\s*(Fixes|Resolves):\s*#(GHSA-[0-9a-z-]+)/\2/gp" "${TMPFILE2}" | sort -n | tr '[:space:]' ' ') )
if [ ${#ghsalist[*]} -gt 0 ] ; then
	debug "Getting ${#ghsalist[*]} issue titles from GitHub"
	for issue in ${ghsalist[*]} ; do
		gh api /repos/${GH_REPO}/security-advisories/$issue \
			--json ghsa_id,summary \
			--jq '. | "  - !" + .ghsa_id + ": " + .summary' \
			>> "${DST_DIR}/issues_to_close.txt"
	done
fi

debug "Getting GitHub issue list"
issuelist=( $(sed -n -r -e "s/^\s*(Fixes|Resolves):\s*#([0-9]+)/\2/gp" "${TMPFILE2}" | sort -n | tr '[:space:]' ' ') )
if [ ${#issuelist[*]} -gt 0 ] ; then
	debug "Getting ${#issuelist[*]} issue titles from GitHub"
	# If the issue list is large, we can get rate limit issues
	# so we're going to get the titles with a single graphql
	# call.

	query="query={ repository(name: \"${GH_REPO%%/*}\", owner: \"${GH_REPO##*/}\") { "

	for n in ${issuelist[@]} ; do
		query+="issue${n}: issue(number: ${n}) { number title } "
	done
	query+="}}"

	gh api graphql --paginate -F "$query" \
		--jq '[ .data.repository[] ] | sort_by(.number) | .[] | "  - #" + ( .number | tostring) + ": " + .title' >> "${DST_DIR}/issues_to_close.txt"
fi

# For historical reasons, let's also look for "ASTERISK-" issues
debug "Getting ASTERISK issues list"
astlist=( $(sed -n -r -e 's/^(ASTERISK-[0-9]+)\s*(#.*)?$/\1/gp' "${TMPFILE2}" | sort -n | tr '[:space:]' ' ') )

if [ ${#astlist[*]} -gt 0 ] ; then
	echo "" >>"${DST_DIR}/issues_to_close.txt"
	echo " An additional ${#astlist[*]} ASTERISK-* issues were closed." >>"${DST_DIR}/issues_to_close.txt"

#	debug "Getting ${#astlist[*]} issue titles from issues-archive"
#	for issue in ${astlist[*]} ; do
#		[[ $issue =~ ASTERISK-([0-9][0-9])[0-9]+ ]] && dir=${BASH_REMATCH[1]}
#		[ -z "$dir" ] && continue
#		ix=${TMPDIR}/index-${dir}.html
#		[ ! -f ${ix} ] && curl -s https://issues-archive.asterisk.org/${dir}/index.html > ${ix}
#		sed -n -r -e "s/.*${issue}<.a>:\s*([^<]+)<.td>.*/  - ${issue}: \1/gp" ${ix} \
#		| python3 -c 'import html, sys; [print(html.unescape(l), end="") for l in sys.stdin]' \
#		>> "${DST_DIR}/asterisk_issues.txt"
#	done
#	sort -u "${DST_DIR}/asterisk_issues.txt" >>"${DST_DIR}/issues_to_close.txt"

fi

if [ -f "${DST_DIR}/issues_to_close.txt" ] && [ $(cat "${DST_DIR}/issues_to_close.txt" | wc -l ) -gt 0 ] ; then
	${DEBUG} && cat "${DST_DIR}/issues_to_close.txt"
	cat "${DST_DIR}/issues_to_close.txt" >> ${TMPFILE1}
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
git -C "${SRC_REPO}" shortlog \
	-E --grep "^(([.]github)|(Add\s+ChangeLog)|(Update[s]?\s+for)|(Update\s+CHANGES))" --invert-grep \
	--group="author" --format="- %<(80,trunc)%s" ${START_TAG}..HEAD |\
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
https://github.com/${GH_REPO}/releases/tag/${END_TAG}
and
https://downloads.asterisk.org/pub/telephony/${end_tag_array[download_dir]}

Repository: https://github.com/${GH_REPO}
Tag: ${END_TAG}

EOF
	if [ -n "${ADVISORIES}" ] ; then
		IFS=$','
		echo "The following security advisories were resolved in this release:" >> "${DST_DIR}/email_announcement.md"

		for a in ${ADVISORIES} ; do
			summary=$(gh api /repos/${GH_REPO}/security-advisories/$a --jq '.summary' 2>/dev/null || echo "FAILED")
			[[ "$summary" =~ FAILED$ ]] && summary=""
			if [ -n "$ADV_URL_BASE" ] ; then
				echo "- [${summary}](${ADV_URL_BASE}/${a})" >> "${DST_DIR}/email_announcement.md"
			else
				echo "- [${summary}](${a})" >> "${DST_DIR}/email_announcement.md"
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
https://github.com/${GH_REPO}/releases/tag/${END_TAG}
and
https://downloads.asterisk.org/pub/telephony/${end_tag_array[download_dir]}

Repository: https://github.com/${GH_REPO}
Tag: ${END_TAG}

This release resolves issues reported by the community  
and would have not been possible without your participation.

Thank You!

EOF
fi
cat "${DST_DIR}/release_notes.md" >>"${DST_DIR}/email_announcement.md"

debug "Create the README"
cp "${SRC_REPO}/README.md" "${DST_DIR}/README-${END_TAG}.md"


debug "Done"
