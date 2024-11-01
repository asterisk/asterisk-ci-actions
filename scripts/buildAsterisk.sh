#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))
GITHUB=false
COVERAGE=false
REF_DEBUG=false
DISABLE_BINARY_MODULES=false
NO_CONFIGURE=false
NO_MENUSELECT=false
NO_MAKE=false
NO_ALEMBIC=false
NO_DEV_MODE=false
OUTPUT_DIR=/tmp/asterisk_ci/
TESTED_ONLY=false

source $SCRIPT_DIR/ci.functions

if [ "${OUTPUT_DIR: -1}" != "/" ] ; then
	OUTPUT_DIR+=/
fi

set -e

if [ -z $BRANCH_NAME ]; then
	BRANCH_NAME=$(sed -n -r -e "s/AC_INIT\(\[asterisk\],\s*\[([^]]+)],\s*\[[^]]+\]\)/\1/gp" configure.ac)
fi

if [[ "$BRANCH_NAME" =~ devel(opment)?/([0-9]+)/.+ ]] ; then
	export MAINLINE_BRANCH="${BASH_REMATCH[2]}"
fi

gen_cats() {
	set +x
	action=$1
	shift
	cats=$@

	for x in $cats ; do
		echo " --${action}-category ${x}"
	done
}

gen_mods() {
	set +x
	action=$1
	shift
	mods=$@

	for x in $mods ; do
		echo " --${action} ${x}"
	done
}

mkdir -p "$OUTPUT_DIR" 2> /dev/null

if [ -z $TESTED_ONLY ]; then
	# Skip building untested modules by default if coverage is enabled.
	TESTED_ONLY=$COVERAGE
fi

if [ -z $LCOV_DIR ]; then
	LCOV_DIR="${OUTPUT_DIR}/lcov"
fi

if [ -n "$CACHE_DIR" ] ; then
	mkdir -p $CACHE_DIR/sounds $CACHE_DIR/externals 2> /dev/null
fi

MAKE=`which make`
PKGCONFIG=`which pkg-config`
_libdir=`${SCRIPT_DIR}/findLibdir.sh`

git config --global --add safe.directory $PWD

runner ulimit -a
_version=$(./build_tools/make_version .)
for var in BRANCH_NAME MAINLINE_BRANCH OUTPUT_DIR CACHE_DIR CCACHE_DISABLE CCACHE_DIR _libdir _version ; do
	declare -p $var 2>/dev/null || :
done

echo "Creating configure arguments"

common_config_args="--prefix=/usr ${_libdir:+--libdir=${_libdir}} --sysconfdir=/etc --with-pjproject-bundled"


source <(sed -r -e "s/\s+//g" third-party/versions.mak)
[ -n "${JANSSON_VERSION}" ] && { $PKGCONFIG "jansson >= ${JANSSON_VERSION}" || common_config_args+=" --with-jansson-bundled" ; }
[ -n "${LIBJWT_VERSION}" ] && { $PKGCONFIG "libjwt >= ${LIBJWT_VERSION}" && common_config_args+=" --with-libjwt" || common_config_args+=" --with-libjwt-bundled" ; } 

common_config_args+=" ${CACHE_DIR:+--with-sounds-cache=${CACHE_DIR}/sounds --with-externals-cache=${CACHE_DIR}/externals}"
if ! $NO_DEV_MODE ; then
	common_config_args+=" --enable-dev-mode"
fi
if $COVERAGE ; then
	common_config_args+=" --enable-coverage"
fi
if [ "$BRANCH_NAME" == "master" -o $DISABLE_BINARY_MODULES ] ; then
	common_config_args+=" --disable-binary-modules"
fi

export WGET_EXTRA_ARGS="--quiet"

if ! $NO_CONFIGURE ; then
	echo "Running configure"
	SUCCESS=true
	runner ./configure ${common_config_args} > /dev/null || SUCCESS=false
	$SUCCESS || { SUCCESS=true ; runner ./configure ${common_config_args} NOISY_BUILD=yes || SUCCESS=false ; }
	cp config.{status,log} makeopts ${OUTPUT_DIR}/ || :
	$SUCCESS || exit 1
fi

if ! $NO_MENUSELECT ; then
	SUCCESS=true
	runner ${MAKE} menuselect.makeopts || SUCCESS=false
	cp menuselect-tree menuselect.{makedeps,makeopts} ${OUTPUT_DIR}/
	$SUCCESS || exit 1

	runner menuselect/menuselect `gen_mods enable DONT_OPTIMIZE` menuselect.makeopts
	if ! $NO_DEV_MODE ; then
		runner menuselect/menuselect `gen_mods enable DO_CRASH TEST_FRAMEWORK` menuselect.makeopts
	fi
	runner menuselect/menuselect `gen_mods disable COMPILE_DOUBLE BUILD_NATIVE` menuselect.makeopts
	if $REF_DEBUG ; then
		runner menuselect/menuselect --enable REF_DEBUG menuselect.makeopts
	fi

	cat_enables=""
	cat_disables=""

	if [[ ! "${BRANCH_NAME}" =~ ^certified ]] ; then
		cat_enables+=" MENUSELECT_BRIDGES MENUSELECT_CEL MENUSELECT_CDR"
		cat_enables+=" MENUSELECT_CHANNELS MENUSELECT_CODECS MENUSELECT_FORMATS MENUSELECT_FUNCS"
		cat_enables+=" MENUSELECT_PBX MENUSELECT_RES"
	fi

	if ! $NO_DEV_MODE ; then
		cat_enables+=" MENUSELECT_TESTS"
	fi
	runner menuselect/menuselect `gen_cats enable $cat_enables` menuselect.makeopts || SUCCESS=false
	if [ -n "$cat_disables" ] ; then
		runner menuselect/menuselect `gen_cats disable $cat_disables` menuselect.makeopts || SUCCESS=false
	fi
	
	cp menuselect.makedeps ${OUTPUT_DIR}/menuselect.makedeps.postcats
	cp menuselect.makeopts ${OUTPUT_DIR}/menuselect.makeopts.postcats
	$SUCCESS || exit 1

	mod_disables="codec_ilbc res_digium_phone res_pjsip_config_sangoma"
	if $TESTED_ONLY ; then
		# These modules are not tested at all.  They are loaded but nothing is ever done
		# with them, no testsuite tests depend on them.
		mod_disables+=" app_adsiprog app_alarmreceiver app_celgenuserevent app_db app_dictate"
		mod_disables+=" app_dumpchan app_externalivr app_festival app_getcpeid"
		mod_disables+=" app_jack app_milliwatt app_minivm app_morsecode app_mp3 app_privacy"
		mod_disables+=" app_readexten app_sms app_speech_utils app_test app_waitforring"
		mod_disables+=" app_waitforsilence app_waituntil app_zapateller"
		mod_disables+=" cdr_adaptive_odbc cdr_custom cdr_manager cdr_odbc cdr_pgsql cdr_radius"
		mod_disables+=" cdr_tds"
		mod_disables+=" cel_odbc cel_pgsql cel_radius cel_sqlite3_custom cel_tds"
		mod_disables+=" chan_console chan_motif chan_rtp chan_unistim"
		mod_disables+=" func_frame_trace func_pitchshift func_speex func_volume func_dialgroup"
		mod_disables+=" func_periodic_hook func_sprintf func_enum func_extstate func_sysinfo func_iconv"
		mod_disables+=" func_callcompletion func_version func_rand func_sha1 func_module func_md5"
		mod_disables+=" pbx_dundi pbx_loopback"
		mod_disables+=" res_ael_share res_calendar res_config_ldap res_config_pgsql res_corosync"
		mod_disables+=" res_http_post res_rtp_multicast res_snmp res_xmpp"
	fi
	mod_disables+=" ${MODULES_BLACKLIST//,/ }"

	runner menuselect/menuselect `gen_mods disable $mod_disables` menuselect.makeopts || SUCCESS=false
	cp menuselect.makedeps ${OUTPUT_DIR}/menuselect.makedeps.moddisables
	cp menuselect.makeopts ${OUTPUT_DIR}/menuselect.makeopts.moddisables
	$SUCCESS || exit 1

	mod_enables="app_voicemail app_directory"
	mod_enables+=" res_mwi_external res_ari_mailboxes res_mwi_external_ami res_stasis_mailbox"
	mod_enables+=" CORE-SOUNDS-EN-GSM MOH-OPSOUND-GSM EXTRA-SOUNDS-EN-GSM"
	runner menuselect/menuselect `gen_mods enable $mod_enables` menuselect.makeopts || SUCCESS=false
	cp menuselect.makedeps ${OUTPUT_DIR}/menuselect.makedeps.modenables
	cp menuselect.makeopts ${OUTPUT_DIR}/menuselect.makeopts.modenables
	$SUCCESS || exit 1
fi

runner ${MAKE} ari-stubs
changes=$(git status --porcelain)
if [ -n "$changes" ] ; then
		echo "ERROR: 'make ari-stubs' generated new files which were not checked in.
Perhaps you forgot to run 'make ari-stubs' yourself?
Files:
$changes
" >&2
	exit 1
fi

if ! $NO_MAKE ; then
	runner ${MAKE} -j8 full || runner ${MAKE} -j1 NOISY_BUILD=yes full
fi

runner rm -f ${LCOV_DIR}/*.info 2>/dev/null || :

if $COVERAGE ; then
	runner mkdir -p ${LCOV_DIR}

	# Zero counter data
	runner lcov --quiet --directory . --zerocounters

	# Branch coverage is not supported by --initial.  Disable to suppresses a notice
	# printed if it was enabled in lcovrc.
	# This initial capture ensures any module which was built but never loaded is
	# reported with 0% coverage for all sources.
	runner lcov --quiet --directory . --no-external --capture --initial --rc lcov_branch_coverage=0 \
		--output-file ${LCOV_DIR}/initial.info
fi

if [ -f "doc/core-en_US.xml" ] ; then
	runner ${MAKE} validate-docs || ${MAKE} NOISY_BUILD=yes validate-docs
fi
