#!/usr/bin/env bash

CIDIR=$(dirname $(readlink -fn $0))
GITHUB=0
UNINSTALL=0
UNINSTALL_ALL=0
OUTPUT_DIR=/tmp/asterisk_ci/

source $CIDIR/ci.functions

if [ "${OUTPUT_DIR: -1}" != "/" ] ; then
	OUTPUT_DIR+=/
fi

mkdir -p "$OUTPUT_DIR" 2> /dev/null

MAKE=`which make`

if [ x"$DESTDIR" != x ] ; then
	mkdir -p "$DESTDIR"
fi

if [[ "$BRANCH_NAME" =~ devel(opment)?/([0-9]+)/.+ ]] ; then
	export MAINLINE_BRANCH="${BASH_REMATCH[2]}"
fi
_version=$(./build_tools/make_version .)

destdir=${DESTDIR:+DESTDIR=$DESTDIR}

begin_log "${OUTPUT_DIR}/variables"
{
declare -p _version
declare -p destdir
} >>"${log_to}"

echo "Uninstalling existing build"
begin_log "${OUTPUT_DIR}/uninstall"
(
[ $UNINSTALL -gt 0 ] && ${MAKE} ${destdir} uninstall
[ $UNINSTALL_ALL -gt 0 ] && ${MAKE} ${destdir} uninstall-all
) >>"$log_to" 2>>"$err_to"
end_log

echo "Installing"
begin_log "${OUTPUT_DIR}/install"
(
	${MAKE} ${destdir} install || ${MAKE} ${destdir} NOISY_BUILD=yes install || exit 1
	${MAKE} ${destdir} samples install-headers 
	if [ x"$DESTDIR" != x ] ; then
		sed -i -r -e "s@\[directories\]\(!\)@[directories]@g" $DESTDIR/etc/asterisk/asterisk.conf
		sed -i -r -e "s@ /(var|etc|usr)/@ $DESTDIR/\1/@g" $DESTDIR/etc/asterisk/asterisk.conf
	fi
) >>"${log_to}" 2>>"${err_to}" || { echo "::error::Install failed.  See ${err_to} for more details." ; exit 1 ; }
end_log

set +e
if [ x"$USER_GROUP" != x ] ; then
	echo "Setting permissions"
	chown -R $USER_GROUP $DESTDIR/var/cache/asterisk
	chown -R $USER_GROUP $DESTDIR/var/lib/asterisk
	chown -R $USER_GROUP $DESTDIR/var/spool/asterisk
	chown -R $USER_GROUP $DESTDIR/var/log/asterisk
	chown -R $USER_GROUP $DESTDIR/var/run/asterisk
	chown -R $USER_GROUP $DESTDIR/etc/asterisk
fi
ldconfig
