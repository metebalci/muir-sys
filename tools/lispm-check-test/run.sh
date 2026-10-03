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
#                                                     expected-question.txt, in under 20 s
# (for the two with exit 2, the tool's message must name broken.lisp and the
# step that failed), and then pass.cases once more with no --file-server,
# where the default, auto, must choose the mode's server for the mode's band.
# The eight run in each mode of LISPM_CHECK_TEST_MODES, "ozd" by default:
#   ozd     --file-server ozd on LISPM_CHECK_BAND, or run/check/band.img: a band
#           whose SYS: is on OZ, its files served by ozd
#   device  --file-server device on LISPM_CHECK_DEVICE_BAND, or
#           run/check/device/band.img: a band whose SYS: is on HOST, its files
#           served by quux's file device
# On this line the band runs on cadr, which has no file device (that is
# QUUX's), so only ozd runs here; device is main's.
# Each band's ubin/ is the one beside it, as the tool's default.  Arguments are
# passed on to every run after the mode's own (--quux and so on), so a --band
# given here overrides both: give it with a single mode.  A band of Systems 100
# to 1001 wants its FILE dates at its site's zone: pass --ozd-file-dates mit
# --ozd-timezone <zone> (-1 for System 1001's release band); no case here reads
# a date, but a check on such a band should serve it as it reads.
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../lispm-check
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

for mode in ${LISPM_CHECK_TEST_MODES:-ozd}; do
    case $mode in
        ozd) band=${LISPM_CHECK_BAND:-$tree/run/check/band.img} ;;
        device) band=${LISPM_CHECK_DEVICE_BAND:-$tree/run/check/device/band.img} ;;
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
    # --timeout 30, a run that waited for any question takes 30 s or more
    within=20 check "$mode question" 1 "$here/expected-question.txt" -- "${m[@]}" --files "$here/selftest.lisp" "$@" --timeout 30 "$here/question.cases"
    check "$mode auto" 0 "" "lispm-check: files served by $mode: " -- --band "$band" --files "$here/selftest.lisp" "$@" "$here/pass.cases"
done
[ "$fails" = 0 ] && echo "self-test passed" || echo "self-test FAILED ($fails)"
[ "$fails" = 0 ]
