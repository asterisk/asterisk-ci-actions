#!/bin/bash

if [ -n "$HOSTNAME" ] ; then
	[ ! -f /etc/hosts ] && touch /etc/hosts

	if ! grep -q -E "^127.0.0.1" /etc/hosts ; then
		echo "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4 $HOSTNAME" >> /etc/hosts
	else
		sed -i -r -e "s/(^127.0.0.1.*)/\1 $HOSTNAME/g" /etc/hosts
	fi
	if ! grep -q -E "^::1" /etc/hosts ; then
		echo "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6 $HOSTNAME" >> /etc/hosts
	else
		sed -i -r -e "s/(^::1.*)/\1 $HOSTNAME/g" /etc/hosts
	fi
fi

if [ "x$GITHUB_ACTIONS" == "x" ] ; then
	exec /bin/bash --init-file /.startup -i
fi
if [ "x$1" == "x" ] ; then
	echo "::error::Running in github actions but no script was provided"
	exit 1
fi
printenv
ACTION_DIR=${GITHUB_WORKSPACE}/$(basename ${GITHUB_ACTION_REPOSITORY})
cd ${GITHUB_WORKSPACE}
if [ ! -d ${ACTION_DIR} ] ; then
	git clone ${GITHUB_SERVER_URL}/${GITHUB_ACTION_REPOSITORY}
fi
git -C $(basename ${GITHUB_ACTION_REPOSITORY}) checkout test

SCRIPT_DIR=${ACTION_DIR}/scripts
if [ ! -x ${SCRIPT_DIR}/$1 ] ; then
	echo "::error::Script ${SCRIPT_DIR}/$1 was not found"
	exit 1
fi

ls -al ${GITHUB_WORKSPACE}

exec ${SCRIPT_DIR}/$1
