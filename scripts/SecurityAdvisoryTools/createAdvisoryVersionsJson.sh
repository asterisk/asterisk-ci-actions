#!/usr/bin/bash

SAT_DIR=$(dirname "$(readlink -fn $0)")
SCRIPT_DIR=$(dirname "${SAT_DIR}")

set -e
QUIETER=true
COMBINE_VERSIONS=false
HELP=false
PREVIOUS=false

print_help() {
	cat <<-EOF >&2

	This script generates a JSON document that can be used to update
	one or more security advisory product versions sections.

	Usage: $0 \\
	    --tag-prefixes=<prefix>[,<prefix>]... 
	    [ --next-release-types=<type>[,<type>]... | --previous ]
	    --src-repo=<path to source respository>
	    [ --modules=<module>[,<module>]... ]

	    <prefix>: A tag prefix to match when looking for the last GA release tag.
	    <type>: For future releases, one or more of "minor" or "patch" separated by commas.
	    <path to source repository>: A local path to the source repository.  This is
	    used to find the last GA release tag for each tag prefix and to calculate
	    the future release tags based on the next release types.
	    <module>: An asterisk module affected. Optional.

	For each tag prefix, the script will find the last GA release tag and then,
	if next-release-types is specified, calculate the future release tags based
	on the next release types.  The last release tag will be used as the
	"patched_version" and the one before that will be used as the "vulnerable
	version range".  The resulting JSON document will have an entry for each tag
	prefix.  The "vulnerable_functions" field will be left empty and should be
	updated manually if needed.

	The resulting JSON document can be fed to a "gh api" command as follows:

	$0 \\
	    --next-release-types=patch,minor,patch \\
	    --src-repo=../asterisk-upstream \\
	    --tag-prefixes=20,21,22,23,certified-20,certified-22 > /tmp/versions.json

	gh api -X PATCH -H "Accept: application/vnd.github+json" \\
	    -H "X-GitHub-Api-Version: 2026-03-10" \\
	    /repos/asterisk/asterisk/security-advisories/GHSA-xxxx-yyyy-zzzz \\
	    --input /tmp/versions.json

	In this example, we expect that there will be a patch release and
	a minor release of each asterisk version matching the list of
	tag-prefixes before the patch release that will fix the affected
	vulnerability.  The script will find the last GA release, then
	calculate the future tags for each release type.  For the 20 branch,
	the list would look like: 20.18.2 20.18.3 20.19.0 20.19.1 with
	20.18.2 being the last GA release and  20.18.3 20.19.0 20.19.1 
	being the next patch, minor and patch releases.  The last entry
	(20.19.1) will become the "patched_version" and the one before that
	(20.19.0) will become the "vulnerable version range". 

	The resulting JSON fragment would be:
   {
      "package": {
        "ecosystem": "Asterisk",
        "name": "asterisk"
      },
      "vulnerable_version_range": "<= 20.19.0",
      "patched_versions": "20.19.1",
      "vulnerable_functions": []
    },

	The final JSON document would have an entry for each branch.

EOF

}

source "${SCRIPT_DIR}/ci.functions"
source "${SCRIPT_DIR}/tag.functions"
source "${SAT_DIR}/sa.functions"

if ${HELP} ; then
	print_help
	exit 1
fi

if [ -z "${TAG_PREFIXES}" ] || [ -z "${SRC_REPO}" ] ; then
	echo -e "\nError: --tag-prefixes and --src-repo are required." >&2
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
elif ! ${PREVIOUS} ; then
		echo -e "\nEither --next-release-types or --previous must be specified." >&2
		print_help
		exit 1
fi

string_split "${TAG_PREFIXES}" TPS

printf "%-20s %-18s %-20s %-12s\n" "Package Name" "Earliest GA Vers" "Vulnerable Vers" "Patched Vers" >&2
declare -A versions
for tp in "${TPS[@]}" ; do
	if [ -n "${NEXT_RELEASE_TYPES}" ] ; then
		read -r -a vs < <(${SAT_DIR}/getReleaseTags.sh --src-repo="${SRC_REPO}" --tag-prefix="${tp}" \
			--next-release-types="${NEXT_RELEASE_TYPES}")
	else
		read -r -a vs < <(${SAT_DIR}/getReleaseTags.sh --src-repo="${SRC_REPO}" --tag-prefix="${tp}" \
			--previous=1)
	fi

	name="asterisk"
	[[ "$tp" =~ certified ]] && name="certified-asterisk"
	if [ ${#vs[@]} -gt 1 ] ; then 
		cv="${vs[0]/certified-/}"
		vvr="<= ${vs[-2]/certified-/}"
		pv="${vs[-1]/certified-/}"
	else
		cv="${vs[0]/certified-/}"
		vvr="< ${vs[0]/certified-/}"
		pv="${vs[0]/certified-/}"
	fi
	printf "%-20s %-18s %-20s %-12s\n" "$name" "$cv" "$vvr" "$pv" >&2
	versions["$tp"]="${name}|${cv}|${vvr}|${pv}"
done

modarray="[]"
if [ -n "${MODULES}" ] ; then
	string_split "${MODULES}" mods
	modarray=$(array_to_json_array mods)
fi
printf "Modules: %s\n" "${modarray}" >&2

string_split "${TAG_PREFIXES}" TPS_NO_CERT
array_element_remove TPS_NO_CERT "certified"

string_split "${TAG_PREFIXES}" TPS_ONLY_CERT
array_element_keep TPS_ONLY_CERT "certified"

cat <<EOF
{
 "vulnerabilities": [
EOF

if ${COMBINE_VERSIONS} ; then
	if [ ${#TPS_NO_CERT[@]} -gt 0 ] ; then
		declare -a vvrs
		declare -a pvs
		for tp in "${TPS_NO_CERT[@]}" ; do
			string_split "${versions[$tp]}" vs "|"
			vvrs+=( "${vs[2]}" )
			pvs+=( "${vs[3]}" )
		done
		[ ${#TPS_ONLY_CERT[@]} -gt 0 ] && comma=","
		cat <<-EOF
	    {
	      "package": {
	        "ecosystem": "other",
	        "name": "${vs[0]}"
	      },
	      "vulnerable_version_range": "$(array_join vvrs ', ')",
	      "patched_versions": "$(array_join pvs ', ')",
	      "vulnerable_functions": ${modarray}
	    }${comma}
		EOF
	fi

	if [ ${#TPS_ONLY_CERT[@]} -gt 0 ] ; then
		unset vvrs pvs
		declare -a vvrs
		declare -a pvs
		for tp in "${TPS_ONLY_CERT[@]}" ; do
			string_split "${versions[$tp]}" vs "|"
			vvrs+=( "${vs[2]}" )
			pvs+=( "${vs[3]}" )
		done
		[ ${#TPS_ONLY_CERT[@]} -gt 0 ] && comma=","
		cat <<-EOF
	    {
	      "package": {
	        "ecosystem": "other",
	        "name": "${vs[0]}"
	      },
	      "vulnerable_version_range": "$(array_join vvrs ', ')",
	      "patched_versions": "$(array_join pvs ', ')",
	      "vulnerable_functions": ${modarray}
	    }
		EOF
	fi
else
	lastprefix=${TPS[-1]}
	for tp in "${TPS[@]}" ; do
		string_split "${versions[$tp]}" vs "|"
		comma=","
		[ "${tp}" = "${lastprefix}" ] && comma=""
		cat <<-EOF
	    {
	      "package": {
	        "ecosystem": "other",
	        "name": "${vs[0]}"
	      },
	      "vulnerable_version_range": "${vs[2]}",
	      "patched_versions": "${vs[3]}",
	      "vulnerable_functions": ${modarray}
	    }${comma}
		EOF
	done
fi

cat <<EOF
  ]
}
EOF
unset IFS

