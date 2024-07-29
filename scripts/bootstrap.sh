# This file should be 'sourced' from reusable workflows
# to set to the environment variables that would normally
# be set up if it were an action instead. 
# THIS FILE MUST BE SOURCED NOT EXECUTED!!

set_and_export() {
	vname=${1}
	shift
	value="$@"
	echo "${vname}=${value}" >> "${GITHUB_ENV}"
	eval export ${vname}=\"${value}\"
}

GITHUB_ENV=/dev/stdout

[ -n '${{inputs.asterisk_repo}}' ] && set_and_export ASTERISK_REPO '${{inputs.asterisk_repo}}'
[ -n '${{inputs.base_branch}}' ] && set_and_export BASE_BRANCH '${{ inputs.base_branch }}'
[ -n '${{inputs.is_cherry_pick}}' ] && set_and_export IS_CHERRY_PICK '${{ inputs.is_cherry_pick }}'
[ -n '${{inputs.pr_number}}' ] && set_and_export PR_NUMBER '${{ inputs.pr_number }}'
[ -n '${{inputs.build_script}}' ] && set_and_export BUILD_SCRIPT '${{ inputs.build_script }}'
[ -n '${{inputs.build_options}}' ] && set_and_export BUILD_OPTIONS '${{ inputs.build_options }}'
[ -n '${{inputs.modules_blacklist}}' ] && set_and_export MODULES_BLACKLIST '${{ inputs.modules_blacklist }}'
[ -n '${{inputs.output_cache_dir}}' ] && set_and_export CACHE_DIR '${{github.workspace}}/${{inputs.output_cache_dir}}'
[ -n '${{github.event.repository.name}}' ] && set_and_export REPO_DIR '${{github.event.repository.name}}'
[ -n '${{github.event.repository.owner.login}}' ] && set_and_export REPO_ORG '${{github.event.repository.owner.login}}'
[ -n '${{inputs.output_cache_dir}}' ] && set_and_export OUTPUT_DIR '${{github.workspace}}/${{inputs.output_cache_dir}}/output'
[ -n '${{inputs.build_cache_dir}}' ] && set_and_export BUILD_CACHE_DIR '${{github.workspace}}/${{inputs.build_cache_dir}}'
[ -n '${{inputs.build_cache_key}}' ] && set_and_export BUILD_CACHE_KEY '${{inputs.build_cache_key}}'

set_and_export ACTION_DIR 'asterisk-ci-actions'
set_and_export SCRIPT_DIR '${{github.workspace}}/asterisk-ci-actions/scripts'


[ -n '${{inputs.test_type}}' ] && [ -n '${{inputs.base_branch}}' ] && \
	set_and_export UNIT_TEST_NAME '${{inputs.test_type}}-unit-${BASE_BRANCH//\//-}'

[ -n '${{inputs.testsuite_repo}}' ] && set_and_export GC_TESTSUITE_DIR '$(basename ${{inputs.testsuite_repo}})'

[ -n '${{inputs.test_type}}' ] && [ -n 'inputs.gatetest_group' ] && [ -n '${{inputs.base_branch}}' ] && \
	set_and_export GC_TEST_NAME '${{inputs.test_type}}-${{inputs.gatetest_group}}-${BASE_BRANCH//\//-}'

echo '*** Cloning ${GITHUB_ACTION_REPOSITORY}'
git clone ${GITHUB_SERVER_URL}/${REPO_ORG}/${ACTION_DIR}
git -C ${ACTION_DIR} checkout main-cache-builds

