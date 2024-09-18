#!/usr/bin/env bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))
source $SCRIPT_DIR/db.functions

[ -f test-config.orig.yaml ] && {
	echo "Restoring test-config.yaml"
	mv test-config.orig.yaml test-config.yaml
}
echo "Tearing down database"
${SCRIPT_DIR}/teardownDatabase.sh \
	--host=${HOST} --database=${DATABASE} --user=${USER} --password=${PASSWORD} \
	--dsn=${DSN} --stop-database=${STOP_DATABASE}
