#!/bin/bash
set -e

declare needs=( end_tag )
declare wants=( src_repo dry_run )
declare tests=( src_repo )

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

pushd "${SRC_REPO}/contrib/ast-db-manage" &>/dev/null

debug "Generating alembic scripts"

# The sample config files are all set up for MySql
# so we'll do those first.
$ECHO_CMD mkdir -p ../realtime/mysql || : 
for schema in config voicemail queue_log cdr ; do
	debug "Creating mysql files for ${schema}"
	if $DRY_RUN ; then
		echo "alembic -c ./${schema}.ini.sample upgrade --sql head > ../realtime/mysql/mysql_${schema}.sql"
	else
		alembic -c ./${schema}.ini.sample upgrade --sql head \
			> ../realtime/mysql/mysql_${schema}.sql
	fi
done

trap "rm -f /tmp/*.sample.ini &>/dev/null " EXIT

# We need to generate a config file for postgresql.
$ECHO_CMD mkdir -p ../realtime/postgresql || : 
for schema in config voicemail queue_log cdr ; do
	debug "Creating postgres files for ${schema}"
	if $DRY_RUN ; then
		echo "alembic -c ./${schema}.ini.sample upgrade --sql head > ../realtime/postgresql/postgresql_${schema}.sql"
	else
		# We need to take the samples and copy them to a temp location
		# replacing mysql with postgresql.  Then run alembic with the
		# temp sample ini file.
		sed -r -e "s/^#(sqlalchemy.url\s*=\s*postgresql)/\1/g" -e "s/^(sqlalchemy.url\s*=\s*mysql)/#\1/g" ./${schema}.ini.sample > /tmp/${schema}.ini.sample	
		alembic -c /tmp/${schema}.ini.sample upgrade --sql head \
			> ../realtime/postgresql/postgresql_${schema}.sql
	fi
done

popd &>/dev/null

debug "Done"
