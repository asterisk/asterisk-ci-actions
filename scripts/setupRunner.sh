#!/usr/bin/env bash

echo "Setting up runner"
[ $UID -ne 0 ] && { echo "This script must be run as root!" ; exit 1 ; }

set -e

echo "Setting sysctls and adding asteriskci user"
sysctl -w kernel.core_pattern=/tmp/core-%e-%t
sysctl -w net.ipv6.conf.all.disable_ipv6=0 || :
chmod 1777 /tmp
groupadd -g 2000 asteriskci
useradd -u 2000 -g 2000 asteriskci

# Install packages
echo "Installing github cli repo"
wget -q -O/tmp/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
install --mode=0644 -D -t /etc/apt/keyrings /tmp/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /tmp/github-cli.list
install --mode=0644 -D -t /etc/apt/sources.list.d /tmp/github-cli.list

echo "Installing dev packages"
apt-get update -qq >/dev/null
apt-get install -qq binutils-dev freetds-dev \
  libasound2-dev libbluetooth-dev libc-client2007e-dev \
  libcap-dev libcfg-dev libcodec2-dev libcorosync-common-dev \
  libcpg-dev libcurl4-openssl-dev libedit-dev libfftw3-dev \
  libgmime-3.0-dev libgsm1-dev libical-dev libiksemel-dev \
  libjansson-dev libldap-dev libldap2-dev \
  liblua5.2-dev libneon27-dev libnewt-dev libogg-dev libpopt-dev \
  libradcli-dev libresample1-dev libsndfile1-dev libsnmp-dev \
  libspandsp-dev libspeex-dev libspeexdsp-dev libsrtp2-dev \
  libunbound-dev liburiparser-dev libvorbis-dev libxslt1-dev \
  xmlstarlet python3-pystache >/dev/null

echo "Installing addons"
apt-get install -qq cmake libsctp-dev python3-dev python3*-venv \
  postgresql git libpcap-dev nano python3-pip alembic odbc-postgresql \
  unixodbc unixodbc-dev python3-psycopg2 rsync gh jq >/dev/null

