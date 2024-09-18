#!/usr/bin/env bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))
source $SCRIPT_DIR/db.functions

echo "Dropping ${USER} user, ${DATABASE} database and ${DSN} ODBC DSN"
dropdb $PGOPTS --if-exists -e ${DATABASE_CDR} &>/dev/null || :
dropdb $PGOPTS --if-exists -e ${DATABASE_VOICEMAIL} &>/dev/null || :
dropdb $PGOPTS --if-exists -e ${DATABASE} &>/dev/null 2>&1 || :
dropuser $PGOPTS --if-exists -e ${USER} &>/dev/null 2>&1 || :
odbcinst -u -s -l -n ${DSN} &>/dev/null || :

${STOP_DATABASE} && {
	echo "Stopping database"
	_pg_ctl stop &>/dev/null || :
}

exit 0