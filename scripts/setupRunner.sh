#!/usr/bin/env bash

FOR_RELEASE=false
INSTALL_PACKAGES=false
INSTALL_SIPP=true
PACKAGES="build-essential gdb binutils-dev freetds-dev
libasound2-dev libbluetooth-dev libc-client2007e-dev
libcap-dev libcfg-dev libcodec2-dev libcorosync-common-dev
libcpg-dev libcurl4-openssl-dev libedit-dev libfftw3-dev
libgmime-3.0-dev libgsm1-dev libical-dev libiksemel-dev
libjansson-dev libldap-dev libldap2-dev
liblua5.2-dev libneon27-dev libnewt-dev libogg-dev libpopt-dev
libradcli-dev libresample1-dev libsndfile1-dev libsnmp-dev
libspandsp-dev libspeex-dev libspeexdsp-dev libsrtp2-dev
libunbound-dev liburiparser-dev libvorbis-dev libxslt1-dev
xmlstarlet python3-pystache sqlite3 sqlite3-tools
libsqlite3-dev cmake libsctp-dev libgsl-dev python3-dev python3-venv
postgresql libpq-dev git libpcap-dev nano python3-pip
alembic odbc-postgresql unixodbc unixodbc-dev
python3-psycopg2 rsync
python3-markdown python3-markdown-*
dahdi-source libtonezone-dev libopenr2-dev libpri-dev libss7-dev"

SCRIPT_DIR=$(dirname "$(readlink -fn "$0")")
. "${SCRIPT_DIR}/ci.functions"

[ $UID -ne 0 ] && {
	log_error_msgs "This script must be run as root!"
	exit 1
}
set -e
shopt -s extglob

if [ "${RUNNER_ENVIRONMENT}" != "github-hosted" ] ; then
	PACKAGES+=" jq gh"
fi

: "${APT_RETRIES:=1}"
: "${APT_HTTP_TIMEOUT:=20}" 
: "${APT_TIMEOUT:=300}"
: "${SIPP_VERSION:=v3.7.5}"
: "${GITHUB_SERVER_URL:=https://github.com}"
export DEBIAN_FRONTEND="noninteractive"

printvars FOR_RELEASE INSTALL_PACKAGES INSTALL_SIPP \
	APT_RETRIES APT_HTTP_TIMEOUT APT_TIMEOUT \
	SIPP_VERSION GITHUB_SERVER_URL RUNNER_ENVIRONMENT VERBOSE \
	PACKAGES

debug_out "/etc/os-release: "
cat /etc/os-release

declare -a apt_update_options=( "-y"
	"-o" "Acquire::Retries=${APT_RETRIES}"
	"-o" "Acquire::http::Timeout=${APT_HTTP_TIMEOUT}"
	"-o" "Acquire::https::Timeout=${APT_HTTP_TIMEOUT}") 

declare -a apt_install_options=( "-y" "--no-install-recommends" "--no-upgrade"
	"-o" "Acquire::Retries=${APT_RETRIES}"
	"-o" "Acquire::http::Timeout=${APT_HTTP_TIMEOUT}"
	"-o" "Acquire::https::Timeout=${APT_HTTP_TIMEOUT}") 

run_apt_get() {
	if ${VERBOSE} ; then
		# The stdin redirect from /dev/null is important because some packages
		# (libpcap-dev for one) would prompt for input and apt needs /dev/stdin even if
		# noninteractive is set.  timeout doesn't pass it however so we need to either
		# set the -f flag on timeout (which has consequences) or redirect stdin
		# from /dev/null. 
		timeout -v -s KILL "${APT_TIMEOUT}" apt-get "${@}" </dev/null
	else
		_TMPFILE=$(mktemp -t rsue-XXXXXX.log)
		timeout -v -s KILL "${APT_TIMEOUT}" apt-get "${@}" </dev/null &>"${_TMPFILE}" || { RC=$? ; cat "${_TMPFILE}" >&2 ; return $RC ; }
	fi
}

install_packages() {
	mapfile -t  pkgs <<<"${PACKAGES//[[:space:]]/$'\n'}"

	debug_out "Running apt update"
	run_apt_get "${apt_update_options[@]}" update
	
	debug_out "Installing packages"
	run_apt_get "${apt_install_options[@]}" install "${pkgs[@]}"
}

# We're now using an action that installs and caches apt packages so
# we usually don't need to install them ourselves any more.  This
# is here "just in case".
if ${INSTALL_PACKAGES} ; then
	install_packages
fi

# Bison needs to be removed because the installed versions don't regenerate
# the AEL parsers correctly.
debug_out "Removing bison and byacc"
run_apt_get "${apt_install_options[@]}" remove bison || :
run_apt_get "${apt_install_options[@]}" remove byacc || :


if [ "${RUNNER_ENVIRONMENT}" == "github-hosted" ] ; then
	debug_out "Current kernel.core_pattern: $(sysctl kernel.core_pattern)"
	sysctl -w kernel.core_pattern=/tmp/core-%e-%t
	chmod 1777 /tmp
	debug_out "New kernel.core_pattern: $(sysctl kernel.core_pattern)"
fi

if ${FOR_RELEASE} ; then
	debug_out "Installing release packages"
	run_apt_get "${apt_install_options[@]}" install python3-markdown python3-markdown-*
	debug_out "Installed release packages.  sipp not needed."
	exit 0
fi

if ${INSTALL_SIPP} ; then

	debug_out "Building and installing sipp"
	SIPPDIR=$(mktemp -d -p /opt/ -t sipp.XXXXXXXX)
	
	cd "${SIPPDIR}"
	debug_out "Retrieving sipp ${SIPP_VERSION}"
	run_silent_unless_error wget --no-verbose \
		"https://github.com/SIPp/sipp/releases/download/${SIPP_VERSION}/sipp-${SIPP_VERSION/v/}.tar.gz"
	tar -xf "sipp-${SIPP_VERSION/v/}.tar.gz"
	cd "sipp-${SIPP_VERSION/v/}"
	debug_out "Building sipp ${SIPP_VERSION}"
	run_silent_unless_error cmake . -DUSE_GSL=1 -DUSE_PCAP=1 -DUSE_SSL=1 -DUSE_SCTP=1 -DCMAKE_POLICY_VERSION_MINIMUM=3.5
	run_silent_unless_error make -j "$(nproc --all 2>/dev/null || echo 1)"
	debug_out "Installing sipp ${SIPP_VERSION} to /usr/bin"
	run_silent_unless_error install -D -t /usr/bin sipp

else
	debug_out "SIPP not required"
fi

exit 0
