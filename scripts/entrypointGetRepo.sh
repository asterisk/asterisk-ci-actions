#!/usr/bin/bash
set -x
set -e

export GITHUB_TOKEN=${INPUT_GITHUB_TOKEN}
export GH_TOKEN=${INPUT_GITHUB_TOKEN}

SCRIPT_DIR=${GITHUB_WORKSPACE}/$(basename ${GITHUB_ACTION_REPOSITORY})/scripts
REPO_DIR=${GITHUB_WORKSPACE}/$(basename ${INPUT_REPO})
OUTPUT_DIR=${GITHUB_WORKSPACE}/${INPUT_CACHE_DIR}/output

mkdir -p ${REPO_DIR}
mkdir -p ${OUTPUT_DIR}

cd ${GITHUB_WORKSPACE}

	cat <<EOF > ~/.pgpass
*:*:*:postgres:postgres
*:*:*:asterisk_test:asterisk_test
EOF
	PGHOST=postgres-asterisk
	sleep 5
	ping -c 1 $PGHOST || sleep 5
	ping -c 1 $PGHOST || PGHOST=localhost
	export PGOPTS="-h $PGHOST -w --username=postgres"
	chmod go-rwx ~/.pgpass
	export PGPASSFILE=~/.pgpass
	echo "Creating asterisk_test user and database"
	dropdb $PGOPTS --if-exists -e asterisk_test >/dev/null 2>&1 || :
	dropuser $PGOPTS --if-exists -e asterisk_test >/dev/null  2>&1 || :
	psql $PGOPTS -c "create user asterisk_test with login password 'asterisk_test';" || return 1
#	createuser $PGOPTS -RDIElS asterisk_test || return 1
	createdb $PGOPTS -E UTF-8 -O asterisk_test asterisk_test || return 1

exit 0
${SCRIPT_DIR}/checkoutRepo.sh --repo=${INPUT_REPO} \
	--branch=${INPUT_BASE_BRANCH} --is-cherry-pick=${INPUT_IS_CHERRY_PICK} \
	--pr-number=${INPUT_PR_NUMBER} --destination=${REPO_DIR}

cd ${REPO_DIR}

if [ "x${INPUT_BUILD_SCRIPT}" != "x" ] ; then
	${SCRIPT_DIR}/${INPUT_BUILD_SCRIPT} --github --branch-name=${INPUT_BASE_BRANCH} \
		--ccache-disable ${INPUT_BUILD_OPTIONS} \
		--modules-blacklist="${INPUT_MODULES_BLACKLIST// /}" \
		--output-dir=${OUTPUT_DIR}
fi
