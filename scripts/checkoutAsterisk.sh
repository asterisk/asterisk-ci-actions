#!/usr/bin/bash

SCRIPT_DIR=$(dirname $(realpath $0))
source ${SCRIPT_DIR}/ci.functions
set -x
set -e

if [ ${PR_NUMBER} -gt 0 ] ; then
  if ${IS_CHERRY_PICK} ; then
    CHECKOUT_REF=${BASE_BRANCH}
    echo "Cherry picking PR ${PR_NUMBER} to branch ${BASE_BRANCH}" 
  else
    CHECKOUT_REF=refs/pull/${PR_NUMBER}/head
    echo "Checking out PR ${PR_NUMBER}" 
  fi
else
  if ${IS_CHERRY_PICK} ; then
    echo "::error::Cherry-pick requested without a PR to cherry-pick"
    exit 1
  fi
  CHECKOUT_REF=${BASE_BRANCH}
  echo "Checking out branch ${BASE_BRANCH}" 
fi

mkdir -p ${DESTINATION}
git clone --depth 5 -q -b ${BASE_BRANCH} \
	${GITHUB_SERVER_URL}/${ASTERISK_REPO} ${DESTINATION}
git config --global --add safe.directory $(realpath ${DESTINATION})
cd ${DESTINATION}

if [[ ${CHECKOUT_REF} =~ refs/pull ]] ; then
	git fetch origin ${CHECKOUT_REF}
	git checkout FETCH_HEAD
else
	git checkout ${CHECKOUT_REF}
fi

if ${IS_CHERRY_PICK} ; then
	echo "Cherry-picking commits"
	commits=$(gh api repos/asterisk/asterisk-gh-test/pulls/${PR_NUMBER}/commits --jq '.[].sha')
	IFS=$'\n '
	for commit in $commits ; do
	  desc=$(git show --oneline -s ${commit})
	  echo "Cherry picking commit ${desc}"
	  git cherry-pick ${commit} || {
	    echo "::error::Unable to cherry-pick commit '${desc}'"
	    exit 1
	  }
	done 
fi
