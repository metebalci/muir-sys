#!/usr/bin/env bash
# The self-test of tools/lispm-check. It runs the tool eight times against the
# files beside this script, once for each way of serving files, and checks each
# exit status, and for the full case file each case's verdict against
# expected.txt:
#   selftest.cases, selftest.lisp loaded as source   exit 1, verdicts as expected.txt
#   selftest.cases, selftest.lisp compiled            exit 1, verdicts as expected.txt
#   wrong.cases (one wrong expected value)            exit 1
#   pass.cases                                        exit 0
#   selftest.cases, broken.lisp (unclosed form)       exit 2, the file's load fails
#   the same with --compile                           exit 2, qc-file reports it
#   question.cases (bare questions, an error's)       exit 1, verdicts and texts as
#                                                     expected-question.txt, in under 40 s
# (for the two with exit 2, the tool's message must name broken.lisp and the
# step that failed), and then pass.cases once more with no --file-server,
# where the default, auto, must choose the mode's server for the mode's band.
# The eight run in each mode of LISPM_CHECK_TEST_MODES, "device" by default:
#   device  --file-server device on LISPM_CHECK_DEVICE_BAND, or the tool's
#           default band run/check/band.img: a band whose SYS: is on the file
#           device's pathname host, HOST (System 2001, and the bands of 2002
#           built before the name changed) or FILES (after it), its files
#           served by quux's file device; the tool takes the name from the band
#   ozd     --file-server ozd on LISPM_CHECK_BAND, or run/check/band.img: a band
#           whose SYS: is on OZ, its files served by ozd
# On this line the default band is System 2001's (its hand-over band, on
# revision 13 with its own PROM), whose SYS: is on HOST, so only device is run
# by default.  It was System 2000's, which runs on revision 12 alone, and the
# current quux refuses revision 12 ("revision 13, 14, 15 or 16"), so the
# default no longer booted.  ozd was the default too while the default
# band was a System 1002 band on OZ; no such band boots on quux since revision
# 11 (its microcode 1000 waits for block-disk at 17377774, where revision 11
# has no register), so ozd needs LISPM_CHECK_BAND naming a band on OZ that
# the quux given runs.
# Each band's ubin/ is the one beside it, as the tool's default.  Arguments are
# passed on to every run after the mode's own (--quux and so on), so a --band
# given here overrides both: give it with a single mode.  A band of Systems 100
# to 1001 wants its FILE dates at its site's zone: pass --ozd-file-dates mit
# --ozd-timezone <zone> (-1 for System 1001's release band); no case here reads
# a date, but a check on such a band should serve it as it reads.
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../lispm-check
# The self-test runs on micro only: its question cases are bounded at 40 s of
# host time, which revision 15's rtl, the pipeline, overruns (44 s on a loaded
# host), and the tool it tests is the same on either engine.
prev=
for a in "$@"; do
    if [ "$a" = --engine=rtl ] || { [ "$prev" = --engine ] && [ "$a" = rtl ]; }; then
        echo "lispm-check-test: the self-test runs on micro only (--engine rtl given)" >&2
        exit 2
    fi
    prev=$a
done
tree=$(dirname "$(dirname "$here")")
fails=0
out=$(mktemp)
trap 'rm -f "$out"' EXIT

check() {  # check NAME EXPECTED-STATUS VERDICTS-FILE-OR-EMPTY [TEXT] -- TOOL-ARGS...
    # TEXT, when given, must appear in the output: a status 2 must be the
    # broken file's and not, say, a flag the tool refused or a boot that failed.
    # WITHIN, when set in the environment of the call, bounds the cases' time.
    local name=$1 want=$2 verdicts=$3 text=; shift 3
    [ "$1" != -- ] && { text=$1; shift; }
    shift
    "$tool" "$@" > "$out" 2>&1
    local got=$?
    if [ "$got" != "$want" ]; then
        echo "FAIL $name: exit $got, wanted $want"; sed 's/^/    /' "$out"; fails=$((fails+1)); return
    fi
    if [ -n "$text" ] && ! grep -qF -- "$text" "$out"; then
        echo "FAIL $name: no \"$text\" in the output"; sed 's/^/    /' "$out"; fails=$((fails+1)); return
    fi
    if [ -n "$verdicts" ]; then
        while IFS= read -r line; do
            # STATUS FORM, or STATUS FORM  -> TEXT when the line's text after
            # the arrow must match too
            local status=${line%% *} form=${line#* } why=
            case $form in *'  -> '*) why="-> ${form#*  -> }"; form=${form%%  -> *} ;; esac
            if ! grep -qF -- "$status  $form  $why" "$out"; then
                echo "FAIL $name: no line \"$status  $form  $why\""; sed 's/^/    /' "$out"; fails=$((fails+1)); return
            fi
        done < "$verdicts"
        local n; n=$(grep -cE '^(PASS|FAIL|ERROR)  ' "$out")
        if [ "$n" != "$(wc -l < "$verdicts")" ]; then
            echo "FAIL $name: $n verdict lines, wanted $(wc -l < "$verdicts")"; fails=$((fails+1)); return
        fi
    fi
    if [ -n "$within" ]; then
        # the cases' time, the summary's "all", must stay under WITHIN seconds
        local all; all=$(sed -n 's/.*, all \([0-9.]*\) s)$/\1/p' "$out")
        if [ -z "$all" ] || ! awk -v a="$all" -v w="$within" 'BEGIN { exit !(a < w) }'; then
            echo "FAIL $name: the cases took ${all:-?} s, wanted under $within s"; sed 's/^/    /' "$out"; fails=$((fails+1)); return
        fi
    fi
    echo "ok   $name (exit $got)"
}

for mode in ${LISPM_CHECK_TEST_MODES:-device}; do
    case $mode in
        ozd) band=${LISPM_CHECK_BAND:-$tree/run/check/band.img} ;;
        # the default band, System 2001's (System 2000's before quux
        # refused its revision, 12), is on HOST: run/check/device/ was the
        # device's own band while the default was a System 1002 band on OZ
        device) band=${LISPM_CHECK_DEVICE_BAND:-${LISPM_CHECK_BAND:-$tree/run/check/band.img}} ;;
        *) echo "FAIL unknown mode $mode"; fails=$((fails+1)); continue ;;
    esac
    # The mode's band and server come first, so that the caller's flags win.
    m=(--file-server "$mode" --band "$band")
    check "$mode source" 1 "$here/expected.txt" -- "${m[@]}" --files "$here/selftest.lisp" "$@" "$here/selftest.cases"
    check "$mode compile" 1 "$here/expected.txt" -- "${m[@]}" --compile --files "$here/selftest.lisp" "$@" "$here/selftest.cases"
    check "$mode wrong-value" 1 "" -- "${m[@]}" --files "$here/selftest.lisp" "$@" "$here/wrong.cases"
    check "$mode all-pass" 0 "" -- "${m[@]}" --files "$here/selftest.lisp" "$@" "$here/pass.cases"
    check "$mode broken-file" 2 "" "lispm-check: $here/broken.lisp: (let " -- "${m[@]}" --files "$here/broken.lisp" "$@" "$here/selftest.cases"
    check "$mode broken-compile" 2 "" "lispm-check: $here/broken.lisp: (qc-file " -- "${m[@]}" --compile --files "$here/broken.lisp" "$@" "$here/selftest.cases"
    # the default, --file-server auto, must choose this mode for this band
    # a bare (Y or N) or (Yes or No) fails its case at once, answered No: with
    # --timeout 60, a run that waited for any question takes 60 s or more.
    # the bound was 20 s with --timeout 30: on revision 16, micro, at 20 ns,
    # over tcp the cases took 19.2-22.3 s (six runs; over chaos 7.5-11.3 s),
    # so the bound failed a run that asked nothing.  40 s leaves 18 s over the
    # slowest and 20 s under a single wait for an answer, which --timeout 60 makes
    # 60 s at least.  before:
    #within=20 check "$mode question" 1 "$here/expected-question.txt" -- "${m[@]}" --files "$here/selftest.lisp" "$@" --timeout 30 "$here/question.cases"
    within=40 check "$mode question" 1 "$here/expected-question.txt" -- "${m[@]}" --files "$here/selftest.lisp" "$@" --timeout 60 "$here/question.cases"
    check "$mode auto" 0 "" "lispm-check: files served by $mode: " -- --band "$band" --files "$here/selftest.lisp" "$@" "$here/pass.cases"
done
[ "$fails" = 0 ] && echo "self-test passed" || echo "self-test FAILED ($fails)"
[ "$fails" = 0 ]
