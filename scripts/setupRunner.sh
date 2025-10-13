#!/usr/bin/env bash

FOR_RELEASE=false
: ${SIPP_VERSION:=v3.7.5}
: ${GITHUB_SERVER_URL:=https://github.com}
SCRIPT_DIR=$(dirname $(readlink -fn $0))
. $SCRIPT_DIR/ci.functions

[ $UID -ne 0 ] && {
	log_error_msgs "This script must be run as root!"
	exit 1
}
set -e

cat /etc/os-release
echo "RUNNER_ENVIRONMENT=${RUNNER_ENVIRONMENT}"

export DEBIAN_FRONTEND="noninteractive"
debug_out "Running apt update"
run_silent_unless_error apt-get update -y -qq
debug_out "Installing wget, curl, file, apr-utils pre-reqs"
run_silent_unless_error apt-get install -y -qq wget curl file apt-utils

if ! which gh &>/dev/null ; then
	debug_out "Installing github cli repo"
	wget -q -O/tmp/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
	install --mode=0644 -D -t /etc/apt/keyrings /tmp/githubcli-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /tmp/github-cli.list
	install --mode=0644 -D -t /etc/apt/sources.list.d /tmp/github-cli.list
fi

debug_out "Installing dev packages"
run_silent_unless_error apt-get install -qq sudo build-essential gdb binutils-dev freetds-dev \
  libasound2-dev libbluetooth-dev libc-client2007e-dev \
  libcap-dev libcfg-dev libcodec2-dev libcorosync-common-dev \
  libcpg-dev libcurl4-openssl-dev libedit-dev libfftw3-dev \
  libgmime-3.0-dev libgsm1-dev libical-dev libiksemel-dev \
  libjansson-dev libldap-dev libldap2-dev \
  liblua5.2-dev libneon27-dev libnewt-dev libogg-dev libpopt-dev \
  libradcli-dev libresample1-dev libsndfile1-dev libsnmp-dev \
  libspandsp-dev libspeex-dev libspeexdsp-dev libsrtp2-dev \
  libunbound-dev liburiparser-dev libvorbis-dev libxslt1-dev \
  xmlstarlet python3-pystache sqlite3 sqlite3-tools\
  libsqlite3-dev

addons="cmake libsctp-dev libgsl-dev python3-dev python3*-venv \
  postgresql libpq-dev git libpcap-dev nano python3-pip \
  alembic odbc-postgresql unixodbc unixodbc-dev \
  python3-psycopg2 rsync"

if ! which jq &>/dev/null ; then
	addons+=" jq"
fi

debug_out "Installing addons" 
run_silent_unless_error apt-get install -qq ${addons}

if [ -n "${RUNNER_ENVIRONMENT}" ] ; then
	debug_out "Setting kernel.core_pattern=/tmp/core-%e-%t"
	sysctl -w kernel.core_pattern=/tmp/core-%e-%t
	chmod 1777 /tmp
fi

if $FOR_RELEASE ; then
	debug_out "Installing release packages"
	run_silent_unless_error  apt-get install -qq python3-markdown python3-markdown-*
	debug_out "Installed release packages.  sipp not needed."
	exit 0
fi

debug_out "Removing bison"
run_silent_unless_error apt-get remove -y -qq bison || :
run_silent_unless_error apt-get remove -y -qq byacc || :


debug_out "Building and installing sipp"
SIPPDIR=$(mktemp -d -p /opt/ -t sipp.XXXXXXXX)

cd ${SIPPDIR}
debug_out "Retrieving sipp ${SIPP_VERSION}"
wget -q https://github.com/SIPp/sipp/releases/download/${SIPP_VERSION}/sipp-${SIPP_VERSION/v/}.tar.gz
tar -xf sipp-${SIPP_VERSION/v/}.tar.gz
cd sipp-${SIPP_VERSION/v/}
debug_out "Building sipp ${SIPP_VERSION}"
run_silent_unless_error cmake . -DUSE_GSL=1 -DUSE_PCAP=1 -DUSE_SSL=1 -DUSE_SCTP=1 -DCMAKE_POLICY_VERSION_MINIMUM=3.5
run_silent_unless_error make -j$(nproc --all 2>/dev/null || echo 1)
debug_out "Installing sipp ${SIPP_VERSION} to /usr/bin"
run_silent_unless_error install -D -t /usr/bin sipp

exit 0
