
if [ "$0" == "${BASH_SOURCE[0]}" ] ; then
	echo "${BASH_SOURCE[0]} is meant to be 'sourced' not run directly" >&2
	exit 1
fi

progname=$(basename -s .sh $0)

echo "====== Entering ${progname}" >&2
trap 'echo "====== Exiting ${progname} exit code: $?" >&2' EXIT

# Scripts can use this common arg parsing like so...
# Create 3 arrays that describe the options being used:
#
# What options are required:
# declare needs=( version_type release_type branch )
# What options are wanted but not required:
# declare wants=( src_repo certified security )
# What options need to be tested if they exist:"
# declare tests=( version_type release_type branch src_repo )

# Find the script directory:
# progdir="$(dirname $(realpath $0) )"
# Source the common.sh file:
# source "${progdir}/common.sh"


# Not all the scripts use all the options
# but it'seasier to just define them all here.
[[ "$(declare -p options 2>/dev/null || : )" =~ "declare -A" ]] || declare -A options

options+=(
	     [product]="--product=[ asterisk | libpri ]    # Defaults to asterisk"
	[release_type]="--release-type=[ rc1 | rcn | ga | ganorc ]"
	   [start_tag]="--start-tag=<tag>"
	     [end_tag]="--end-tag=<tag>"
	 [new_version]="--new-version=<tag>                # Synonym for end-tag"
	        [repo]="--repo=<source github repo>"
	    [repo_dir]="--repo-dir=<source repo path>"
	    [src_repo]="--src-repo=<source repo path>"
	     [gh_repo]='--gh-repo=<github repository>      # defaults asterisk/$(basename ${SRC_REPO})'
	     [dst_dir]="--dest-dir=<destination directory> # Directory for build artifacts"
	      [branch]="--branch=<branch>                  # Release branch"
	        [norc]="--norc                             # There were no release candidates for this release"
	    [security]="--security                         # This is a security release"
	  [advisories]="--advisories=<adv>[,<adv> ...]     # A comma separated list of advisories"
	[adv_url_base]="--adv-url-base=<adv_url_base>      # The URL base for security advisories"
	      [hotfix]="--hotfix                           # This is a hotfix but not security release"
	 [cherry_pick]="--cherry-pick                      # Cherry-pick commits for rc1 releases"
[force_cherry_pick]="--force-cherry-pick                # Force cherry-pick for non-rc releases"
	     [alembic]="--alembic                          # Create alembic sql scripts"
	   [changelog]="--changelog                        # Create changelog"
	      [commit]="--commit                           # Commit changelog/alembic scripts"
	         [tag]="--tag                              # Tag the release"
	        [push]="--push                             # Push ChangeLog commit and tag upstream"
	     [tarball]="--tarball                          # Create tarball"
	   [patchfile]="--patchfile                        # Create patchfile"
	        [sign]="--sign                             # Sign the tarball and patchfile"
	[label_issues]="--label-issues                     # Label related issues with release tag"
[create_github_release]="--create-github-release            # Create and publish GitHub release"
   [push_branches]="--push-branches                    # Push release branches live"
   [push_tarballs]="--push-tarballs                    # Push tarballs live"
	  [full_monty]="--full-monty                       # Do everything"
	     [dry_run]="--dry-run                          # Don't do anything, just print commands"
	  [send_email]="--send-email                       # Send email announcement"
	[mail_list_ga]="--mail-list-ga=<list>              # Email list for GA releases"
	[mail_list_rc]="--mail-list-rc=<list>              # Email list for RC releases"
[mail_list_cert_ga]="--mail-list-cert-ga=<list>         # Email list for certified GA releases"
[mail_list_cert_rc]="--mail-list-cert-rc=<list>         # Email list for certified RC releases"
	[mail_list_sec]="--mail-list-sec=<list>             # Email list for security releases"
	 [deploy_host]="--deploy-host=<host>               # Host to deploy to"
	  [deploy_dir]="--deploy-dir=<dir>                 # Directory to deploy to"
 [gpg_private_key]="--gpg-private-key=<key>            # Private key to sign with"
[deploy_ssh_username]="--deploy-ssh-username=<username>   # Username for deploy host"
[deploy_ssh_priv_key]="--deploy-ssh-priv-key=<key>        # Private key for deploy host"
	    [gh_token]="--gh-token=<token>                 # GitHub token"
	    [user_ok]="--user-ok=<user>                 # Allow this user to run this script"
	       [help]="--help                           # Print this help"
	      [debug]="--debug                          # Print debugging info"
)

wants+=( help debug )
needs+=( )
tests+=( )

bail() {
	# Join lines that start with whitespace.
	sed -E ':a ; $!N ; s/\n\s+/ / ; ta ; P ; D' <<<"${progname}: $@" >&2
	exit 1
}

debug() {
	# Join lines that start with whitespace.
	${DEBUG} && sed -E ':a ; $!N ; s/\n\s+/ / ; ta ; P ; D' <<<"${progname}: $@" >&2
	return 0
}

booloption() {
	converted=${1//-/_}
	declare -n option=${converted^^}
	[ -n "${option}" ] && ${option} && echo "--${1}"
}

stringoption() {
	converted=${1//-/_}
	declare -n option=${converted^^}
	[ -n "${option}" ] && echo "--${1}=\"${option}\""
}

print_help() {
	unset IFS
	echo "$@" >/dev/stdout
	echo "Usage: $0 " >/dev/stdout

	for x in "${needs[@]}" ; do
		echo -e "\t${options[$x]}" >/dev/stdout
	done

	for x in "${wants[@]}" ; do
		echo -e "\t[ ${options[$x]} ]" >/dev/stdout
	done

	exit 1
}

VERSION_TYPE=
RELEASE_TYPE=
START_TAG=
END_TAG=
SRC_REPO=
GH_REPO=
DST_DIR=
BRANCH=
: ${USER_OK:=false}
: ${SECURITY:=false}
: ${HOTFIX:=false}
: ${NORC:=false}
: ${CHERRY_PICK:=false}
: ${FORCE_CHERRY_PICK:=false}
: ${ALEMBIC:=false}
: ${CHANGELOG:=false}
: ${COMMIT:=false}
: ${TAG:=false}
: ${PUSH_BRANCHES:=false}
: ${TARBALL:=false}
: ${PATCHFILE:=false}
: ${SIGN:=false}
: ${PUSH_TARBALLS:=false}
: ${CREATE_GITHUB_RELEASE:=false}
: ${SEND_EMAIL:=false}

: ${FULL_MONTY:=false}
: ${HELP:=false}
: ${DRY_RUN:=false}
: ${DEBUG:=false}
ECHO_CMD=

declare -a args
for a in "$@" ; do
	if [[ $a =~ --no-([^=]+)$ ]] ; then
		var=${BASH_REMATCH[1]//-/_}
		eval "${var^^}"="false"
	elif [[ $a =~ --([^=]+)=(.+)$ ]] ; then
		var=${BASH_REMATCH[1]//-/_}
		eval "${var^^}"="\"${BASH_REMATCH[2]}\""
	elif [[ $a =~ --([^=]+)$ ]] ; then
		var=${BASH_REMATCH[1]//-/_}
		eval "${var^^}"="true"
		${FULL_MONTY} && {
			CHERRY_PICK=true
			ALEMBIC=true
			CHANGELOG=true
			COMMIT=true
			TAG=true
			PUSH_BRANCHES=true
			TARBALL=true
			PATCHFILE=true
			SIGN=true
			PUSH_TARBALLS=true
			CREATE_GITHUB_RELEASE=true
		}
	else
		args+=( "$a" )
	fi
done

{ $SECURITY || $HOTFIX ; } && NORC=true


debug "$@"

[ -n "${SRC_REPO}" ] && SRC_REPO=$(realpath "${SRC_REPO}")
[ -n "${DST_DIR}" ] && DST_DIR=$(realpath "${DST_DIR}")
[ -z "${GH_REPO}" ] && GH_REPO=asterisk/$(basename "${SRC_REPO}")

for opt in "${needs[@]}" ; do
	declare -n var=${opt^^}
	if [ -z "${var}" ] ; then
		echo "You must supply --${opt//_/-} or ${opt^^} in the environment" >/dev/stdout
		HELP=true
	fi
done

$HELP && print_help


for opt in "${tests[@]}" ; do
	declare -n var="${opt^^}"
	if [ -z "${var}" ] ; then
		continue
	fi
	case ${opt} in
		src_repo)
			if [ -n "$var" ] && [ ! -d "$var" ] ; then
				bail "${opt//_/-} '$var' doesn't exist"
			fi
			
			if [ -n "$var" ] && [ ! -d "$var/.git" ] ; then
				bail "${opt//_/-} '$var' isn't a git repo"
			fi
			;;
		dst_dir)
			if [ -n "$var" ] && [ ! -d "$var" ] ; then
				bail "${opt//_/-} '$var' doesn't exist"
			fi
			;;
		*_tag)
			if [ -n "$var" ] && [ -z "$(git -C ${SRC_REPO} tag -l ${var})" ] ; then
				bail "${opt//_/-} '${var}' doesn't exist"
			fi
			;;
		branch)
			if [ -n "$var" ] && [ -z "$(git -C ${SRC_REPO} branch --list ${var})" ] ; then
				bail "${opt//_/-} '${var}' doesn't exist"
			fi
			;;
		release_type)
			[ -n "$var" ] && [[ ${var} =~ (rc1|rcn|ga|ga-norc) ]] || bail "${opt//_/-} '${var}' is invalid"
			;;
		version_type)
			[ -n "$var" ] && [[ ${var} =~ (major|minor|patch) ]] || bail "${opt//_/-} '${var}' is invalid"
			;;
		*)
			bail "Option '--${opt//_/-}' doesn't have a test"
	esac
done

$DRY_RUN && ECHO_CMD="echo"

# tag_parser takes a tag and the _name_ of an existing
# associative array and parses the former into the latter
tag_parser() {
	{ [ -z "$1" ] || [ -z "$2" ] ; } && return 1 
	local tagin=$1
	local -n tagarray=$2
	tagarray[certified]=false
	tagarray[no_patches]=false
	tagarray[artifact_prefix]="$PRODUCT"
	tagarray[download_dir]="$PRODUCT"

	if [[ "$tagin" =~  ^(certified-)?([0-9]+)[.]([0-9]+)(-cert|[.])([0-9]+)(-(rc|pre)([0-9]+))?$ ]]  ; then
		tagarray[certprefix]=${BASH_REMATCH[1]}
		tagarray[major]=${BASH_REMATCH[2]}
		tagarray[minor]=${BASH_REMATCH[3]}
		tagarray[patchsep]=${BASH_REMATCH[4]}
		tagarray[patch]=${BASH_REMATCH[5]}
		tagarray[release]=${BASH_REMATCH[6]}
		tagarray[release_type]=${BASH_REMATCH[7]:-ga}
		tagarray[release_num]=${BASH_REMATCH[8]}
		tagarray[base_version]=${BASH_REMATCH[2]}.${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}

		tagarray[current_linkname]=${tagarray[major]}-current
		[ "${BASH_REMATCH[1]}" == "certified-" ] && {
			tagarray[certified]=true
			tagarray[download_dir]="certified-asterisk"
			tagarray[current_linkname]=${tagarray[major]}.${tagarray[minor]}-current
		}

		tagarray[tag]=$tagin
	else
		return 1
	fi
	if ${tagarray[certified]} ; then
		[[ ${tagarray[patch]} == 1 ]] && \
			( [[ ${tagarray[release_type]} == ga ]] || [[ ${tagarray[release]} == -rc1 ]] ) && tagarray[no_patches]=true || :
		tagarray[branch]="releases/certified-${tagarray[major]}.${tagarray[minor]}"
		tagarray[source_branch]="certified/${tagarray[major]}.${tagarray[minor]}"
		tagarray[startpatch]=1
	else
		[[ $tagin =~ ^[0-9]+[.]0[.]0(-rc1)?$ ]] && tagarray[no_patches]=true || :
		tagarray[branch]="releases/${tagarray[major]}"
		tagarray[source_branch]="${tagarray[major]}"
		tagarray[startpatch]=0
	fi
	return 0
}

mdtohtml() {
	cat <<-EOF
	<html><head><title>$1</title></head><body>
	EOF
	python3 -m markdown --extension=extra -o html -e utf-8 $2
	cat <<-EOF
	
	</body></html>
	EOF
	return 0
}

