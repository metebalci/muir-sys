#!/usr/bin/env bash
# The self-test of tools/lispm-check. It runs the tool five times against the
# files beside this script and checks each exit status, and for the full case
# file each case's verdict against expected.txt:
#   selftest.cases, selftest.lisp loaded as source   exit 1, verdicts as expected.txt
#   selftest.cases, selftest.lisp compiled            exit 1, verdicts as expected.txt
#   wrong.cases (one wrong expected value)            exit 1
#   pass.cases                                        exit 0
#   selftest.cases, broken.lisp (unclosed form)       exit 2, the file's load fails
#   the same with --compile                           exit 2, qc-file reports it
# Arguments are passed on to every run (--band, --quux and so on).
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../lispm-check
fails=0
out=$(mktemp)
trap 'rm -f "$out"' EXIT

check() {  # check NAME EXPECTED-STATUS VERDICTS-FILE-OR-EMPTY -- TOOL-ARGS...
    local name=$1 want=$2 verdicts=$3; shift 4
    "$tool" "$@" > "$out" 2>&1
    local got=$?
    if [ "$got" != "$want" ]; then
        echo "FAIL $name: exit $got, wanted $want"; sed 's/^/    /' "$out"; fails=$((fails+1)); return
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

check source 1 "$here/expected.txt" -- --files "$here/selftest.lisp" "$@" "$here/selftest.cases"
check compile 1 "$here/expected.txt" -- --compile --files "$here/selftest.lisp" "$@" "$here/selftest.cases"
check wrong-value 1 "" -- --files "$here/selftest.lisp" "$@" "$here/wrong.cases"
check all-pass 0 "" -- --files "$here/selftest.lisp" "$@" "$here/pass.cases"
check broken-file 2 "" -- --files "$here/broken.lisp" "$@" "$here/selftest.cases"
check broken-compile 2 "" -- --compile --files "$here/broken.lisp" "$@" "$here/selftest.cases"
[ "$fails" = 0 ] && echo "self-test passed" || echo "self-test FAILED ($fails)"
[ "$fails" = 0 ]
