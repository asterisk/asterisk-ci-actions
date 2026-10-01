#!/bin/bash

SAT_DIR=$(dirname $(readlink -fn $0))
SCRIPT_DIR=$(dirname ${SAT_DIR})

set -e
QUIETER=true
HELP=false

bail() {
	# Join lines that start with whitespace.
	sed -E ':a ; $!N ; s/\n\s+/ / ; ta ; P ; D' <<<"$@" >&2
	exit 1
}

print_help() {
	cat <<-EOF >&2
	
	Usage: $0 --last-release=<last_release_tag> | --tag-prefix=<prefix> --src-repo=<src-repo>
				[ --next-release-types=<type>[,<type>]... | --previous=<n> ] 
	
	This script can take a tag or prefix representing the last GA release (no RCs, etc)
	and print a list of the GA release tags for them.
	
	If --next-release-types contains a list of release types (minor or patch), the script
	will predict a future release tag for each type.
	
	If a number is specified with --previous, the script will list the last <n> number
	of release tags.
		
	These can be used to create a sequence of release versions suitable
	for setting the vulnerable_version_range and patched_versions in
	Security Advisories BUT NOT FOR THE ACTUAL RELEASSE PROCESS.
	
	For instance:
	
	$0 --last-release=23.3.2 --next-release-types=patch,minor,patch
	23.3.2 23.3.3 23.4.0 23.4.1
	
	The first tag will be the current release.

	If you don't know the last release tag, you can specify tag-prefix and src-repo
	and the script will find the last GA release tag matching the prefix.
	If there are RCs for a branch but the GA hasn't been released yet, the
	last-release will be set to the upcoming GA release tag.

	$0 --tag-prefix=certified-20 --src-repo=../asterisk --next-release-types=patch,minor,patch
	certified-20.7-cert9 certified-20.7-cert10 certified-20.7-cert10 certified-20.7-cert11
	
	For certified releases, the minor release-type is ignored and the last-release
	tag will be printed again.  This is because we don't normally do regular minor
	releases of certified branches so a minor release of a non-certified branch
	won't be accompanied by a minor or patch version bunp for a certified release. 
	
	EOF

}

source "${SCRIPT_DIR}/ci.functions"
source "${SCRIPT_DIR}/tag.functions"
source "${SAT_DIR}/sa.functions"

if ${HELP} ; then
	print_help
	exit 1
fi

if [ -n "${NEXT_RELEASE_TYPES}" ] ; then
	irt=$( print_invalid_release_types "${NEXT_RELEASE_TYPES}" )
	if [ -n "${irt}" ] ; then
		echo -e "\nUnrecognized release types '${irt}'.  Only 'minor' and 'patch' are allowed." >&2
		print_help
		exit 1
	fi
fi

if [ -n "${PREVIOUS}" ] && ! [[ "${PREVIOUS}" =~ [0-9]+ ]] ; then
	echo -e "\n--previous must be a number." >&2
	print_help
	exit 1
fi

doit() {
	declare -lA last
	tag_parser ${1} last|| bail "Unable to parse end tag '${1}'"
	
	declare -lA next
	for k in ${!last[@]} ; do
		next[$k]="${last[$k]}"
	done
	
	case "${2}" in
		major)
			if ! ${next[certified]} ; then
				next[patch]=0
				next[minor]=0
			fi
			;;
		minor)
			if ! ${next[certified]} ; then
				next[patch]=0
				next[minor]=$(( next[minor] + 1 ))
			fi
			;;
		patch)
			next[patch]=$(( next[patch] + 1 ))
			;;
		*)
			bail "Unknown next release type '${2}'"
	esac
	
	tag_from_array next
}

if [ -z "${LAST_RELEASE}" ] ; then
	[ -z "${TAG_PREFIX}" ] && bail "If last-release isn't specified, tag-prefix and src-repo must be"
	[ -z "${SRC_REPO}" ] && bail "If last-release isn't specified, tag-prefix and src-repo must be"
	if [[ "${TAG_PREFIX}" =~ ^certified[-/]([0-9]+)$ ]] ; then
		search="certified-${BASH_REMATCH[1]}"
	else
		search="${TAG_PREFIX}"
	fi

	LAST_RELEASE=$(git -C "${SRC_REPO}" --no-pager tag --no-column -l --sort "version:refname" "${search}*" | grep -vE "(pre)" | sed '/-rc/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -1)

	[ -z "${LAST_RELEASE}" ] && bail "Couldn't determine last release from tag-prefix ${TAG_PREFIX}"
	LAST_RELEASE=${LAST_RELEASE%%-rc*}
fi

if [ -n "${PREVIOUS}" ] && [ "${PREVIOUS}" -gt 0 ] ; then
	PREVIOUS=$(( PREVIOUS + 1 ))
	git -C "${SRC_REPO}" --no-pager tag --no-column -l --sort "version:refname" "${search}*" | grep -vE "(pre|rc)" | sed '/-rc/!{s/$/_/}' | sort -V | sed 's/_$//' | tail -${PREVIOUS} | tr '\n' ' '
	echo
	exit 0	
fi


IFS=$','
lrt=$LAST_RELEASE
printf "%s " $lrt
for nrt in ${NEXT_RELEASE_TYPES} ; do
	lrt=$(doit $lrt $nrt)
	printf "%s " $lrt
done
echo


