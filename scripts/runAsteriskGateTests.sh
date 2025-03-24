#!/usr/bin/env bash
SCRIPT_DIR=$(dirname $(readlink -fn $0))
REALTIME=false
STOP_DATABASE=false
TEST_TIMEOUT=600

source $SCRIPT_DIR/ci.functions

ASTETCDIR="$DESTDIR/etc/asterisk"
ASTERISK="$DESTDIR/usr/sbin/asterisk"
CONFFILE="$ASTETCDIR/asterisk.conf"

assert_env_variables --print TEST_NAME TESTSUITE_DIR ASTERISK_DIR \
	TESTSUITE_COMMAND TEST_TIMEOUT || exit 1
printvars LOG_DIR LOG_FILE

debug_out "Starting gate tests"
[ ! -x "$ASTERISK" ] && { log_error_msgs "Asterisk isn't installed." ; exit 1 ; }
[ ! -f "$CONFFILE" ] && { log_error_msgs "Asterisk samples aren't installed." ; exit 1 ; }

if [ x"$WORK_DIR" != x ] ; then
	export AST_WORK_DIR="$(readlink -f $WORK_DIR)"
	mkdir -p "$AST_WORK_DIR"
fi

if [ -n "$TESTSUITE_DIR" ] ; then
	pushd $TESTSUITE_DIR  &>/dev/null
fi

./cleanup-test-remnants.sh
coreglob=$(asterisk_corefile_glob)
corefiles=$(find $(dirname $coreglob) -name $(basename $coreglob) 2>&1)
if [ -n "$corefiles" ] ; then
	debug_out "*** Found one or more core files before running tests ***" \
		"Search glob: ${coreglob}" \
		"Corefiles: ${corefiles}"
	if [[ "$coreglob" =~ asterisk ]] ; then
		debug_out "Removing matching corefiles: $corefiles"
		rm -rf $corefiles || :
	fi
fi

if $REALTIME ; then
	$SCRIPT_DIR/setupRealtime.sh --asterisk-dir=${ASTERISK_DIR} || exit 1
	USE_REALTIME=--realtime
fi

# check to see if venv scripts exist so we can use them
if [ -f ./setupVenv.sh ] ; then
	debug_out "Running in Virtual Environment"
	# explicitly invoking setupVenv to capture output in case of failure
	./setupVenv.sh ${USE_REALTIME} &>/tmp/setupVenv.out || { cat /tmp/setupVenv.out ; exit 1 ; }
	VENVPREFIX="runInVenv.sh python "
else
	debug_out "Running in Legacy Mode"
	export PYTHONPATH=./lib/python/
fi

TESTRC=0
$REALTIME && TESTSUITE_COMMAND+=" -G realtime-incompatible"

debug_out "Running tests ${TESTSUITE_COMMAND} ${AST_WORK_DIR:+with work directory ${AST_WORK_DIR}}"
./${VENVPREFIX}runtests.py --cleanup --timeout=${TEST_TIMEOUT} \
	${TESTSUITE_COMMAND} \
	| contrib/scripts/pretty_print --no-color --no-timer \
		--term-width=100 --show-errors || :
	
if [ ! -f ./asterisk-test-suite-report.xml ] ; then
	log_error_msgs "./asterisk-test-suite-report.xml not found"
	TESTRC=1
else
	cp asterisk-test-suite-report.xml logs/ || :
	failures=$(xmlstarlet sel -t -v "//testsuite/@failures" ./asterisk-test-suite-report.xml)
	for f in $failures ; do
		[ $f -gt 0 ] && TESTRC=1
	done
	log_failed_tests $(xmlstarlet sel -t -m "//testcase[count(failure) > 0]" \
			-v "translate(@classname,'.','/')" -o '/' -v "@name" -n \
			./asterisk-test-suite-report.xml)
fi

if $REALTIME ; then
	$SCRIPT_DIR/teardownRealtime.sh --stop-database=${STOP_DATABASE}
fi

coreglob=$(asterisk_corefile_glob)
corefiles=$(find $(dirname $coreglob) -name $(basename $coreglob) >&2)
if [ -n "$corefiles" ] ; then
	debug_out "*** Found one or more core files after running tests ***" \
		"Search glob: ${coreglob}" \
		"Matching corefiles: ${corefiles}"
	TESTRC=1
	$SCRIPT_DIR/ast_coredumper.sh --no-conf-file --outputdir=./logs/ \
		--tarball-coredumps --delete-coredumps-after $coreglob
	# If the return code was 2, none of the coredumps actually came from asterisk.
	[ $? -eq 2 ] && TESTRC=0 || log_error_msgs "Coredumps found after running tests"
fi

if [ -n "$TESTSUITE_DIR" ] ; then
	popd &>/dev/null
fi
debug_out "Exiting gate tests"
exit $TESTRC
