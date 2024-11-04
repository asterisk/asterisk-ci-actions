#!/usr/bin/env bash
echo "Setting up database"

[ $UID -ne 0 ] && { echo "This script must be run as root!" ; exit 1 ; }

SCRIPT_DIR=$(dirname $(readlink -fn $0))
source $SCRIPT_DIR/db.functions

echo " PGSQLCONF: ${PGSQLCONF}"
echo "    PGDATA: ${PGDATA}"
echo "PG_VERSION: ${PG_VERSION}"
echo "     PGHBA: ${PGHBA}"

[ ! -f ${PGDATA}/PG_VERSION ] && {
	echo "Initializing database in ${PGDATA}"
	_pg_ctl initdb &>/tmp/pg_ctl_initdb.out || {
		echo "FAILED"
		cat /tmp/pg_ctl_initdb.out
		exit 1
	}
}

_pg_ctl status &>/dev/null && {
	echo "Stopping running database"
	_pg_ctl stop
}

echo "Starting database"
_pg_ctl start || {
	echo "FAILED"
	exit 1
}
ls -al /var/run/postgresql

echo "Dropping any existing objects"
dropdb $PGOPTS --if-exists -e ${DATABASE_CDR} &>/dev/null || :
dropdb $PGOPTS --if-exists -e ${DATABASE_VOICEMAIL} &>/dev/null || :
dropdb $PGOPTS --if-exists -e ${DATABASE} &>/dev/null || :
dropuser $PGOPTS --if-exists -e ${USER} &>/dev/null || :

echo "Creating ${USER} user using $PGOPTS"
psql $PGOPTS -c "create user ${USER} with login password '${PASSWORD}';" &>/tmp/create_user.out || {
	echo "FAILED"
	cat /tmp/create_user.out
	exit 1
}

echo "Creating ${DATABASE} database"
createdb $PGOPTS -E UTF-8 -T template0 -O ${USER} ${DATABASE} &>/tmp/create_db.out || {
	echo "FAILED"
	cat /tmp/create_db.out
	exit 1
}

echo "Creating ${DSN} ODBC DSN"
declare -a DRIVERS=( "PostgreSQL" "PostgreSQL Unicode" )
DRIVER=
for d in "${DRIVERS[@]}" ; do
	odbcinst -d -q -n "$d" &>/dev/null && {
		DRIVER="$d"
		break
	}
done

[ -z "$DRIVER" ] && {
	echo "No ODBC Postgres driver found"
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

echo "Testing ${DSN} ODBC DSN"
echo "help;" | isql ${DSN} ${USER} ${PASSWORD} -b &>/tmp/isql_test.out || {
	echo "FAILED"
	cat /tmp/isql_test.out
	exit 1
}
echo "Database setup complete"
exit 0
