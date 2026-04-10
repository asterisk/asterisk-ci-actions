#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))
source $SCRIPT_DIR/ci.functions
[ $UID -ne 0 ] && { log_error_msgs "This script must be run as root!" ; exit 1 ; }
source $SCRIPT_DIR/db.functions

printvars PGSQLCONF PGDATA PG_VERSION PGHBA

[ ! -f ${PGDATA}/PG_VERSION ] && {
	debug_out "Initializing database in ${PGDATA}"
	_pg_ctl initdb &>/tmp/pg_ctl_initdb.out || {
		log_error_msgs "Unable to initialize database engine"
		cat /tmp/pg_ctl_initdb.out
		exit 1
	}
}

_pg_ctl status &>/dev/null && {
	debug_out "Stopping running database"
	_pg_ctl stop
}

debug_out "Starting database"
_pg_ctl start || {
	log_error_msgs "Unable to start database"
	exit 1
}
ls -al /var/run/postgresql

debug_out "Dropping any existing objects"
dropdb $PGOPTS --if-exists -e ${DATABASE_CDR} &>/dev/null || :
dropdb $PGOPTS --if-exists -e ${DATABASE_VOICEMAIL} &>/dev/null || :
dropdb $PGOPTS --if-exists -e ${DATABASE} &>/dev/null || :
dropuser $PGOPTS --if-exists -e ${USER} &>/dev/null || :

debug_out "Creating ${USER} user using $PGOPTS"
psql $PGOPTS -c "create user ${USER} with login password '${PASSWORD}';" &>/tmp/create_user.out || {
	log_error_msgs "Unable to create database user"
	cat /tmp/create_user.out
	exit 1
}

debug_out "Creating ${DATABASE} database"
createdb $PGOPTS -E UTF-8 -T template0 -O ${USER} ${DATABASE} &>/tmp/create_db.out || {
	log_error_msgs "Unable to create database"
	cat /tmp/create_db.out
	exit 1
}

debug_out "Creating ${DSN} ODBC DSN"
odbcinst -d -q >&2

declare -a DRIVERS=( "PostgreSQL Unicode" "PostgreSQL ANSI" "PostgreSQL" )
DRIVER=
for d in "${DRIVERS[@]}" ; do
	debug_out "Checking for '${d}' ODBC driver"
	odbcinst -d -q -n "$d" && {
		DRIVER="$d"
		break
	}
done

[ -z "$DRIVER" ] && {
	log_error_msgs "No ODBC Postgres driver found"
	cat /etc/odbcinst.ini
	exit 1
}

odbcinst -u -s -l -n ${DSN} &>/dev/null || :
odbcinst -i -s -l -n ${DSN} -f /dev/stdin <<-EOF
	[${DSN}]
	Description        = PostgreSQL connection to 'asterisk' database
	Driver             = ${DRIVER}
	Servername         = ${HOST}
	Database           = ${DATABASE}
	UserName           = ${USER}
	Port               = 5432
	ReadOnly           = No
	RowVersioning      = No
	ShowSystemTables   = No
	ShowOldColumn      = No
	FakeOldIndex       = No
	ConnSettings       =
EOF

debug_out "Testing ${DSN} ODBC DSN"
echo "help;" | isql ${DSN} ${USER} ${PASSWORD} -b &>/tmp/isql_test.out || {
	log_error_msgs "ODBC DSN test failed"
	cat /tmp/isql_test.out
	exit 1
}
debug_out "Database setup complete"
exit 0
