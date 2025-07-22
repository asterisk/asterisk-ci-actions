#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $(readlink -fn $0))

# These variables can all be set on the command line.
# To enable an option, convert the variable to lower case and
# replace '_' with '-'. 
# Examples: --optimize --build-native
# To disable an option use the same name but with prefix with
# '--no-' or '--dont-'.
# Examples: --no-dev-mode --dont-configure
GITHUB=false
COVERAGE=false
OPTIMIZE=false
DEV_MODE=true
COMPILE_DOUBLE=false
BUILD_NATIVE=false
DISTCLEAN=false
REF_DEBUG=false
MALLOC_DEBUG=false
BETTER_BACKTRACES=false
DEBUG_FD_LEAKS=false
DEBUG_THREADS=false
LEAK_SANITIZER=false
DO_CRASH=false
TEST_FRAMEWORK=false
DISABLE_BINARY_MODULES=false
CONFIGURE=true
MENUSELECT=true
MAKE=true
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
	mkdir -p $CACHE_DIR 2> /dev/null
fi

GMAKE=`which make`
PKGCONFIG=`which pkg-config`
_libdir=`${SCRIPT_DIR}/findLibdir.sh`

ulimit -a
_version=$(./build_tools/make_version .)

if $DEV_MODE ; then
	DO_CRASH=true
	TEST_FRAMEWORK=true
fi

printvars BRANCH_NAME MAINLINE_BRANCH OUTPUT_DIR CACHE_DIR CCACHE_DISABLE \
	CCACHE_DIR _libdir _version \
	DISTCLEAN \
	CONFIGURE DEV_MODE DISABLE_BINARY_MODULES \
	MENUSELECT OPTIMIZE COMPILE_DOUBLE BUILD_NATIVE \
	MALLOC_DEBUG \
	BETTER_BACKTRACES \
	DEBUG_FD_LEAKS \
	DEBUG_THREADS \
	REF_DEBUG \
	LEAK_SANITIZER \
	DO_CRASH \
	TEST_FRAMEWORK \
	MAKE

debug_out "Creating configure arguments"

common_config_args="--prefix=/usr ${_libdir:+--libdir=${_libdir}} --sysconfdir=/etc --with-pjproject-bundled"

source <(sed -r -e "s/\s+//g" third-party/versions.mak)
[ -n "${JANSSON_VERSION}" ] && { $PKGCONFIG "jansson >= ${JANSSON_VERSION}" || common_config_args+=" --with-jansson-bundled" ; }
[ -n "${LIBJWT_VERSION}" ] && { $PKGCONFIG "libjwt >= ${LIBJWT_VERSION}" && common_config_args+=" --with-libjwt" || common_config_args+=" --with-libjwt-bundled" ; } 

common_config_args+=" ${CACHE_DIR:+--with-download-cache=${CACHE_DIR}}"
if $DEV_MODE ; then
	common_config_args+=" --enable-dev-mode"
fi
if $COVERAGE ; then
	common_config_args+=" --enable-coverage"
fi
if [ "$BRANCH_NAME" == "master" ] || $DISABLE_BINARY_MODULES ] ; then
	common_config_args+=" --disable-binary-modules"
fi

export WGET_EXTRA_ARGS="--quiet"

if $DISTCLEAN ; then
	debug_out "Running distclean"
	# Yes, we do it twice.
	${GMAKE} distclean &> /dev/null || :
	rm -rf menuselect.makeopts menuselect.makedeps &>/dev/null || :
fi

if $CONFIGURE ; then
	debug_out "Running configure"
	SUCCESS=true
	runner ./configure ${common_config_args} > /dev/null || SUCCESS=false
	$SUCCESS || { SUCCESS=true ; runner ./configure ${common_config_args} NOISY_BUILD=yes || SUCCESS=false ; }
	cp config.{status,log} makeopts ${OUTPUT_DIR}/ || :
	$SUCCESS || {
		log_error_msgs "./configure failed"
		exit 1
	}
fi

set_menuselect_options() {
	args=""
	for opt in $@ ; do
		local value=${!opt}
		if $value ; then
			args+=" --enable $opt"
		else
			args+=" --disable $opt"
		fi
	done
	runner menuselect/menuselect $args menuselect.makeopts
}

if $MENUSELECT ; then
	SUCCESS=true
	debug_out "Running initial menuselect"
	runner ${GMAKE} menuselect.makeopts || SUCCESS=false
	cp menuselect-tree menuselect.{makedeps,makeopts} ${OUTPUT_DIR}/
	$SUCCESS || {
		log_error_msgs "Initial menuselect failed"
		exit 1
	}

	debug_out "Setting menuselect options"

	if $OPTIMIZE ; then
		runner menuselect/menuselect `gen_mods disable DONT_OPTIMIZE` menuselect.makeopts
	else
		runner menuselect/menuselect `gen_mods enable DONT_OPTIMIZE` menuselect.makeopts
	fi

	set_menuselect_options \
		BUILD_NATIVE \
		COMPILE_DOUBLE \
		REF_DEBUG \
		MALLOC_DEBUG \
		BETTER_BACKTRACES \
		DEBUG_FD_LEAKS \
		DEBUG_THREADS \
		LEAK_SANITIZER

	if $DEV_MODE ; then
		set_menuselect_options \
			DO_CRASH \
			TEST_FRAMEWORK
	fi
	
	grep -q ADD_CFLAGS_TO_BUILDOPTS_H ./build_tools/cflags.xml && \
		runner menuselect/menuselect --enable ADD_CFLAGS_TO_BUILDOPTS_H menuselect.makeopts

	cat_enables=""
	cat_disables=""
	debug_out "Setting category enables/disables"

	if [[ ! "${BRANCH_NAME}" =~ ^certified ]] ; then
		cat_enables+=" MENUSELECT_BRIDGES MENUSELECT_CEL MENUSELECT_CDR"
		cat_enables+=" MENUSELECT_CHANNELS MENUSELECT_CODECS MENUSELECT_FORMATS MENUSELECT_FUNCS"
		cat_enables+=" MENUSELECT_PBX MENUSELECT_RES"
	fi

	if $DEV_MODE ; then
		cat_enables+=" MENUSELECT_TESTS"
	fi

	if [ -f "main/channelstorage_makeopts.xml" ] ; then
		cat_enables+=" MENUSELECT_CHANNELSTORAGE"
	fi

	debug_out "Committing category enables/disables"

	if [ -n "$cat_enables" ] ; then
		runner menuselect/menuselect `gen_cats enable $cat_enables` menuselect.makeopts || SUCCESS=false
	fi
	if [ -n "$cat_disables" ] ; then
		runner menuselect/menuselect `gen_cats disable $cat_disables` menuselect.makeopts || SUCCESS=false
	fi

	cp menuselect.makedeps ${OUTPUT_DIR}/menuselect.makedeps.postcats
	cp menuselect.makeopts ${OUTPUT_DIR}/menuselect.makeopts.postcats
	$SUCCESS || {
		log_error_msgs "menuselect failed"
		exit 1
	}

	debug_out "Setting module enables/disables"
	mod_disables="codec_ilbc codec_silk codec_siren7 codec_siren14 codec_g729a res_digium_phone"
	grep -q res_pjsip_config_sangoma res/res.xml && mod_disables+=" res_pjsip_config_sangoma"

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

	debug_out "Setting module disables"
	runner menuselect/menuselect `gen_mods disable $mod_disables` menuselect.makeopts || SUCCESS=false
	cp menuselect.makedeps ${OUTPUT_DIR}/menuselect.makedeps.moddisables
	cp menuselect.makeopts ${OUTPUT_DIR}/menuselect.makeopts.moddisables
	$SUCCESS || {
		log_error_msgs "menuselect failed"
		exit 1
	}

	debug_out "Setting module enables"
	mod_enables="app_voicemail app_directory"
	mod_enables+=" res_mwi_external res_ari_mailboxes res_mwi_external_ami res_stasis_mailbox"
	mod_enables+=" CORE-SOUNDS-EN-GSM MOH-OPSOUND-GSM EXTRA-SOUNDS-EN-GSM"
	runner menuselect/menuselect `gen_mods enable $mod_enables` menuselect.makeopts || SUCCESS=false
	cp menuselect.makedeps ${OUTPUT_DIR}/menuselect.makedeps.modenables
	cp menuselect.makeopts ${OUTPUT_DIR}/menuselect.makeopts.modenables
	$SUCCESS || {
		log_error_msgs "menuselect failed"
		exit 1
	}
fi

debug_out "Running make ari-stubs"
runner ${GMAKE} ari-stubs || {
		log_error_msgs "make ari-stubs failed"
		exit 1
	}

if [ -d .git ] ; then
	changes=$(git status --porcelain)
	if [ -n "$changes" ] ; then
			log_error_msgs "ERROR: 'make ari-stubs' generated new files which were not checked in.
	Perhaps you forgot to run 'make ari-stubs' yourself?
	Files:
	$changes
	"
		exit 1
	fi
fi

if $MAKE ; then
	np=$(nproc 2>/dev/null || echo 8)
	runner ${GMAKE} -j ${np} full || runner ${GMAKE} -j1 NOISY_BUILD=yes full || {
		log_error_msgs "compile failed"
		exit 1
	}
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
	runner ${GMAKE} validate-docs || ${GMAKE} NOISY_BUILD=yes validate-docs || {
		log_error_msgs "Documentation validation failed"
		exit 1
	}
fi
