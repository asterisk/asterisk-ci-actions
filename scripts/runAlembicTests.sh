#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))
source $SCRIPT_DIR/db.functions

[ ! -f contrib/ast-db-manage/config.ini.sample ] && {
	echo "contrib/ast-db-manage/config.ini.sample not found"
	exit 1
}

ALEMBIC=$(which alembic 2>/dev/null || : )
[ x"$ALEMBIC" = x ] && {
	>&2 echo "::error::Alembic not installed"
	exit 1
}

_pg_ctl status || {
	echo "Database is not running or isn't initialized."
	exit 1
}

run_alembic_heads_branches() {
	config=$1
	echo "Running heads/branches for $config"
	pushd contrib/ast-db-manage >/dev/null
	[ ! -f $config ] && { echo "Config file $config not found" ; return 1 ; }
	out=$( alembic -c $config heads )
	[ $? -ne 0 ] && { echo "heads: $out" ; return 1 ; }
	lc=$(echo "$out" | wc -l)
	[ $lc != 1 ] && { echo "Expecting 1 head but found $lc" ; echo $out ; return 1 ; }
	out=$( alembic -c $config branches )
	[ $? -ne 0 ] && { echo "branches: $out" ; return 1 ; }
	lc=$(echo "$out" | sed -r -e "/^\s*$/d" | wc -l)
	[ $lc != 0 ] && { echo "Expecting no branches but found $(( $lc - 1 ))" ; echo $out ; return 1 ; }
	popd > /dev/null
	echo "Running heads/branches for $config succeeded"
	return 0
}

upgrade_downgrade() {
	config=$1
	echo "Running upgrade/downgrade for ${config}"
	sed -r -e "s/^sqlalchemy.url\s*=\s*mysql.*/sqlalchemy.url = postgresql:\/\/${USER}:${PASSWORD}@${HOST}\/${DATABASE}/g" ${config}.sample > .${config}	
	alembic -c ./.${config} upgrade head &>/tmp/alembic.out || {
		cat /tmp/alembic.out
		echo "Alembic upgrade failed for ${config}"
		rm -rf .${config} || :
		return 1
	}
	alembic -c ./.${config} downgrade base &>/tmp/alembic.out || {
		cat /tmp/alembic.out
		echo "Alembic downgrade failed for ${config}"
		rm -rf .${config} || :
		return 1
	}
	rm -rf .${config} || :
	echo "Running upgrade/downgrade for ${config} succeeded"
	return 0
}

run_alembic_upgrade_downgrade() {
	pushd contrib/ast-db-manage >/dev/null

	RC=0
	upgrade_downgrade config.ini || RC=1
	[ $RC == 0 ] && upgrade_downgrade cdr.ini || RC=1
	[ $RC == 0 ] && upgrade_downgrade voicemail.ini || RC=1

	popd > /dev/null
	return $RC
}

echo "Running Alembic"

find contrib/ast-db-manage -name *.pyc -delete

run_alembic_heads_branches config.ini.sample || {
	>&2 echo "::error::Alembic head/branch check failed for config.ini"
	exit 1
}

run_alembic_heads_branches cdr.ini.sample || {
	>&2 echo "::error::Alembic head/branch check failed for cdr.ini"
	exit 1
}

run_alembic_heads_branches voicemail.ini.sample || {
	>&2 echo "::error::Alembic head/branch check failed for voicemail.ini"
	exit 1
}

run_alembic_upgrade_downgrade || {
	>&2 echo "::error::Alembic upgrade/downgrade failed"
	exit 1
}
