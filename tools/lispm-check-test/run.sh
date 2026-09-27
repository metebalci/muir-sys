#!/usr/bin/env bash
# The self-test of tools/lispm-check. It runs the tool seven times against the
# files beside this script, once for each way of serving files, and checks each
# exit status, and for the full case file each case's verdict against
# expected.txt:
#   selftest.cases, selftest.lisp loaded as source   exit 1, verdicts as expected.txt
#   selftest.cases, selftest.lisp compiled            exit 1, verdicts as expected.txt
#   wrong.cases (one wrong expected value)            exit 1
#   pass.cases                                        exit 0
#   selftest.cases, broken.lisp (unclosed form)       exit 2, the file's load fails
#   the same with --compile                           exit 2, qc-file reports it
# (for the two with exit 2, the tool's message must name broken.lisp and the
# step that failed), and then pass.cases once more with no --file-server,
# where the default, auto, must choose the mode's server for the mode's band.
# The seven run in each mode of LISPM_CHECK_TEST_MODES, "ozd device" by default:
#   ozd     --file-server ozd on LISPM_CHECK_BAND, or run/check/band.img: a band
#           whose SYS: is on OZ, its files served by ozd
#   device  --file-server device on LISPM_CHECK_DEVICE_BAND, or
#           run/check/device/band.img: a band whose SYS: is on HOST, its files
#           served by quux's file device
# Each band's ubin/ is the one beside it, as the tool's default.  Arguments are
# passed on to every run after the mode's own (--quux and so on), so a --band
# given here overrides both: give it with a single mode.
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../lispm-check
tree=$(dirname "$(dirname "$here")")
fails=0
out=$(mktemp)
trap 'rm -f "$out"' EXIT

check() {  # check NAME EXPECTED-STATUS VERDICTS-FILE-OR-EMPTY [TEXT] -- TOOL-ARGS...
    # TEXT, when given, must appear in the output: a status 2 must be the
    # broken file's and not, say, a flag the tool refused or a boot that failed.
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
            local status=${line%% *} form=${line#* }
            if ! grep -qF -- "$status  $form  " "$out"; then
                echo "FAIL $name: no line \"$status  $form\""; sed 's/^/    /' "$out"; fails=$((fails+1)); return
            fi
        done < "$verdicts"
        local n; n=$(grep -cE '^(PASS|FAIL|ERROR)  ' "$out")
        if [ "$n" != "$(wc -l < "$verdicts")" ]; then
            echo "FAIL $name: $n verdict lines, wanted $(wc -l < "$verdicts")"; fails=$((fails+1)); return
        fi
    fi
    echo "ok   $name (exit $got)"
}

for mode in ${LISPM_CHECK_TEST_MODES:-ozd device}; do
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
    check "$mode auto" 0 "" "lispm-check: files served by $mode: " -- --band "$band" --files "$here/selftest.lisp" "$@" "$here/pass.cases"
done
[ "$fails" = 0 ] && echo "self-test passed" || echo "self-test FAILED ($fails)"
[ "$fails" = 0 ]
