#!/usr/bin/env bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))

ASTERISK_DIR=../asterisk

if [ ! -f test-config.yaml ] || [ ! -f tox.ini ] ; then
	echo "This script needs to be run from the testsuite directory"
	exit 1
fi

source $SCRIPT_DIR/db.functions

[ ! -d "${ASTERISK_DIR}" ] && \
	{ echo "Asterisk directory ${ASTERISK_DIR} doesn't exist" ; exit 1 ; }

echo "Setting up testsuite for realtime"

${SCRIPT_DIR}/setupDatabase.sh --host=${HOST} --database=${DATABASE} --user=${USER} \
	--password=${PASSWORD} --dsn=${DSN} --stop-database=${STOP_DATABASE}

pushd ${ASTERISK_DIR}/contrib/ast-db-manage &>/dev/null
echo "Running alembic upgrade"
sed -r -e "s/^sqlalchemy.url\s*=\s*mysql.*/sqlalchemy.url = postgresql:\/\/${USER}:${PASSWORD}@${HOST}\/${DATABASE}/g" config.ini.sample > .config.ini
alembic -c ./.config.ini upgrade head &>/tmp/alembic.out || {
	cat /tmp/alembic.out
	exit 1
}
popd &>/dev/null

cp test-config.yaml test-config.orig.yaml

echo "Configuring test-config.yaml"
cat >test-config.yaml <<-EOF
	global-settings:
	    test-configuration: config-realtime

	    condition-definitions:
	        -
	            name: 'threads'
	            pre:
	                typename: 'thread_test_condition.ThreadPreTestCondition'
	            post:
	                typename: 'thread_test_condition.ThreadPostTestCondition'
	                related-type: 'thread_test_condition.ThreadPreTestCondition'
	        -
	            name: 'sip-dialogs'
	            pre:
	                typename: 'sip_dialog_test_condition.SipDialogPreTestCondition'
	            post:
	                typename: 'sip_dialog_test_condition.SipDialogPostTestCondition'
	        -
	            name: 'locks'
	            pre:
	                typename: 'lock_test_condition.LockTestCondition'
	            post:
	                typename: 'lock_test_condition.LockTestCondition'
	        -
	            name: 'file-descriptors'
	            pre:
	                typename: 'fd_test_condition.FdPreTestCondition'
	            post:
	                typename: 'fd_test_condition.FdPostTestCondition'
	                related-type: 'fd_test_condition.FdPreTestCondition'
	        -
	            name: 'channels'
	            pre:
	                typename: 'channel_test_condition.ChannelTestCondition'
	            post:
	                typename: 'channel_test_condition.ChannelTestCondition'
	        -
	            name: 'sip-channels'
	            pre:
	                typename: 'sip_channel_test_condition.SipChannelTestCondition'
	            post:
	                typename: 'sip_channel_test_condition.SipChannelTestCondition'
	        -
	            name: 'memory'
	            pre:
	                typename: 'memory_test_condition.MemoryPreTestCondition'
	            post:
	                typename: 'memory_test_condition.MemoryPostTestCondition'
	                related-type: 'memory_test_condition.MemoryPreTestCondition'

	config-realtime:
	    test-modules:
	        modules:
	            -
	                typename: realtime_converter.RealtimeConverter
	                config-section: realtime-config

	    realtime-config:
	        username: "${USER}"
	        password: "${PASSWORD}"
	        host: "${HOST}"
	        db: "${DATABASE}"
	        dsn: "${DSN}"
EOF
echo "Testsuite realtime setup complete"
exit 0
