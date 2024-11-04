#!/usr/bin/env bash

echo "Setting up runner"
[ $UID -ne 0 ] && { echo "This script must be run as root!" ; exit 1 ; }

: ${SIPP_VERSION:=v3.6.1}
: ${GITHUB_SERVER_URL:=https://github.com}
SCRIPT_DIR=$(dirname $(readlink -fn $0))
. $SCRIPT_DIR/ci.functions

set -e

echo "Setting kernel.core_pattern=/tmp/core-%e-%t"
sysctl -w kernel.core_pattern=/tmp/core-%e-%t
chmod 1777 /tmp

export DEBIAN_FRONTEND="noninteractive"
apt-get update -y -qq >/dev/null
apt-get install -y wget curl file apt-utils >/dev/null

# Install packages
if ! which gh &>/dev/null ; then
	echo "Installing github cli repo"
	wget -q -O/tmp/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
	install --mode=0644 -D -t /etc/apt/keyrings /tmp/githubcli-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /tmp/github-cli.list
	install --mode=0644 -D -t /etc/apt/sources.list.d /tmp/github-cli.list
fi

echo "Installing dev packages"
apt-get install -qq sudo binutils-dev freetds-dev \
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
  libsqlite3-dev >/dev/null

addons="cmake libsctp-dev python3-dev python3*-venv \
  postgresql libpq-dev git libpcap-dev nano python3-pip \
  alembic odbc-postgresql unixodbc unixodbc-dev \
  python3-psycopg2 rsync"

if ! which gh &>/dev/null ; then
	addons+=" gh"
fi

if ! which jq &>/dev/null ; then
	addons+=" jq"
fi

echo "Installing addons" 
apt-get install -qq ${addons} >/dev/null

echo "Building and installing sipp"
SIPPDIR=$(mktemp -d -p /opt/ -t sipp.XXXXXXXX)
trap "rm -rf ${SIPPDIR}" EXIT

cd ${SIPPDIR}
echo "*** Retrieving sipp ${SIPP_VERSION}"
wget -q https://github.com/SIPp/sipp/releases/download/${SIPP_VERSION}/sipp-${SIPP_VERSION/v/}.tar.gz
tar -xf sipp-${SIPP_VERSION/v/}.tar.gz
cd sipp-${SIPP_VERSION/v/}
echo "*** Building sipp ${SIPP_VERSION}"
./build.sh --full &>/tmp/sipp.build.out || { cat /tmp/sipp.build.out ; exit 1 ; }
echo "*** Installing sipp ${SIPP_VERSION} to /usr/bin"
install -D -t /usr/bin sipp
cd
