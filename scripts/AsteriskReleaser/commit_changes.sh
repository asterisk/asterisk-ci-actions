#!/bin/bash
set -e

declare needs=( start_tag end_tag )
declare wants=( src_repo dst_dir security norc hotfix )
declare tests=( start_tag src_repo dst_dir )

# Since creating the changelog doesn't make any
# changes, we're not bothering with dry-run.

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

declare -A end_tag_array
tag_parser ${END_TAG} end_tag_array

cd "${SRC_REPO}"
	
debug "Committing ChangeLog and Alembic scripts"

git add contrib/realtime

cp ${DST_DIR}/.version .version
git add .version

if [ ! -d ChangeLogs ] ; then
	mkdir -p ChangeLogs/historical
	[ -f CHANGES ] && git mv CHANGES ChangeLogs/historical/
	[ -f ChangeLog ] && git mv ChangeLog ChangeLogs/historical/
fi

if [ -f asterisk-*-summary.html ] ; then
	git rm -f asterisk-*-summary.html asterisk-*-summary.txt >/dev/null 2>&1 || :
fi

cp ${DST_DIR}/ChangeLog-${END_TAG}.md ChangeLogs/
ln -sf ChangeLogs/ChangeLog-${END_TAG}.md CHANGES.md
git add ChangeLogs/ChangeLog-${END_TAG}.md CHANGES.md

if [ "${end_tag_array[release_type]}" == "ga" ] ; then
	if ! { $SECURITY || $NORC || $HOTFIX ; }; then
		# Security releases have no RCs.
		git rm -f ChangeLogs/ChangeLog-${end_tag_array[base_version]}-rc*
	fi
fi

if [ -f UPGRADE.txt ] ; then
	header=$(head -1 UPGRADE.txt)
	if [[ ! "$header" =~ OBSOLETE ]] ; then
		cp UPGRADE.txt /tmp/asterisk/last_upgrade
		cat <<-EOF >UPGRADE.txt
		===== WARNING, THIS FILE IS OBSOLETE AND WILL BE REMOVED IN A FUTURE VERSION =====
		See 'Upgrade Notes' in the CHANGES file
		
		EOF
		cat /tmp/asterisk/last_upgrade >>UPGRADE.txt
	fi
fi

status=$(git status --porcelain)
if [ "x${status}" == "x" ] ; then
	echo "Nothing new to commit!"
	exit 0
fi

git commit -a -m "Update for ${END_TAG}"

debug "Done"
