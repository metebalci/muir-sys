#!/usr/bin/env bash
# The self-test of tools/lispm-check's --network files (QUUX's Ethernet
# contract, section 18, Q-N13 (a)): the session through request and answer
# files on the file device's host, HC-SERVE at the band's listener
# (tools/lispm-check-lisp/hc-serve.lisp), the checkpoint taken while it
# waits.  network.sh runs it after its own lanes; it runs alone too, needing
# no tap:
#
#   tools/lispm-check-test/files.sh --quux W16 --band DISK --ubin DIR ...
#
# The arguments are lispm-check's and go to every run; --quux must name a
# machine of revision 16 and the band must be one whose SYS: is on the file
# device's pathname host.  LISPM_CHECK_TEST_QUUX15, when set, names a machine
# of revision 15 for the lanes that need one.  LISPM_CHECK_TEST_TOOL names the
# tool tested (default: tools/lispm-check beside this directory).  Every run
# uses a cache of this test's own, made empty here.  About 4 minutes on
# micro, and 10 more for the rtl lane, which LISPM_CHECK_TEST_NO_RTL skips.
#
#   files-15        revision 15, LISPM_CHECK_TAPS naming no tap of the pool:
#                   exit 1 with the verdicts of expected-files.txt (files.cases:
#                   values, errors expected and not, a question through FQUERY,
#                   output, the device in the resumed world, and early-answer,
#                   a form that writes a false hc-K.ans of its own while it
#                   runs); the setup typed the start at the glass TTY, took the
#                   checkpoint at the prompt, and its machine had no network
#                   flag; the check's machine no glass TTY; no ozd; no tap and
#                   "LISPM_CHECK_TAPS not used"; the key ends -files-<HC-SERVE>
#   files-15-again  the same, its checkpoint resumed: no setup
#   files-16        revision 16 (--quux): the same, with no tap and no
#                   --ethernet-socket
#   files-15-rtl    revision 15 on rtl: the same verdicts, its own checkpoint
#   held            a planted HC-SERVE (hc-serve-held.lisp appended) that holds
#                   a file open around its loop: exit 2, the setup failing on
#                   the checkpoint refused for a handle open, tried once
#   early           a planted tool whose FileSession takes hc-K.ans without
#                   waiting for hc-K.done: early-answer's verdict must be
#                   EARLY, so the lanes' comparison catches the plant
#   cadr            the tool as the cadr line's copy (MACHINE cadr): --network
#                   files refused, exit 2, the CADR having no file device
#   ozd-server      --file-server ozd under --network files: refused, exit 2
#   harness         LISPM_CHECK_NETWORK=files through harness_network (the
#                   tools that drive TELNET sessions of their own): refused
here=$(cd "$(dirname "$0")" && pwd)
tool=${LISPM_CHECK_TEST_TOOL:-$here/../lispm-check}
# a copy of the tool elsewhere takes the tree it is in as its default: the
# plants are given this one, before the caller's arguments
tree=$(dirname "$(dirname "$here")")
fails=0
out=$(mktemp)
mkdir -p "$here/../../run" && work=$(mktemp -d "$here/../../run/lispm-check-files-test.XXXXXX")
cleanup() {
    rm -f "$out"
    echo "files.sh: the runs' cache and kept files are in $work"
}
trap cleanup EXIT
export XDG_CACHE_HOME=$work/cache

fail() { echo "FAIL $name: $*"; sed 's/^/    /' "$out"; fails=$((fails+1)); }
run() {  # run NAME STATUS -- ARGS...: the tool, its exit status checked
    name=$1 want=$2; shift 3
    "$tool" "$@" > "$out" 2>&1
    got=$?
    [ "$got" = "$want" ] || { fail "exit $got, wanted $want"; return 1; }
}
has() { grep -qF -- "$1" "$out" || { fail "no \"$1\" in the output"; return 1; }; }
hasnt() { ! grep -qF -- "$1" "$out" || { fail "\"$1\" in the output"; return 1; }; }
kept() { sed -n "s/^lispm-check: $1 files kept in //p" "$out" | tail -1; }
ok() { echo "ok   $name"; }
key() { ls "$XDG_CACHE_HOME"/muir-sys-check/checkpoints/ 2>/dev/null; }
verdicts() {  # every line of expected-files.txt, and no other verdict line
    local line status form why n
    while IFS= read -r line; do
        status=${line%% *} form=${line#* } why=
        case $form in *'  -> '*) why="-> ${form#*  -> }"; form=${form%%  -> *} ;; esac
        grep -qF -- "$status  $form  $why" "$out" || { fail "no line \"$status  $form  $why\""; return 1; }
    done < "$here/expected-files.txt"
    n=$(grep -cE '^(PASS|FAIL|ERROR)  ' "$out")
    [ "$n" = "$(wc -l < "$here/expected-files.txt")" ] || { fail "$n verdict lines, wanted $(wc -l < "$here/expected-files.txt")"; return 1; }
}
# the setup's and the check's machines, from their kept run directories
machines() {  # machines: no network flag in either, the glass TTY at the setup alone, no ozd
    local s c
    s=$(kept setup) c=$(kept run)
    if [ -z "$s" ] || [ -z "$c" ]; then fail "no kept setup or run directory"
    elif head -1 "$s/quux.log" | grep -qE -- '--chaos-udp|--chaos-address|--ethernet-socket|--ip-address'; then
        fail "the setup's machine was given a network: $(head -1 "$s/quux.log")"
    elif ! head -1 "$s/quux.log" | grep -qF -- '--glass-tty'; then fail "the setup's machine had no glass TTY"
    elif head -1 "$c/quux.log" | grep -qE -- '--glass-tty|--chaos-udp|--ethernet-socket'; then
        fail "the check's machine: $(head -1 "$c/quux.log")"
    elif ! grep -q '^checkpoint: .* at [0-9]* microcycles' "$s/quux.log"; then fail "no checkpoint taken at the prompt"
    elif [ -e "$s/ozd.log" ] || [ -e "$c/ozd.log" ]; then fail "ozd was started"
    else return 0; fi
    return 1
}
filekey() {  # filekey ENGINE: a checkpoint keyed -ENGINE-device-files-<8 hex>
    key | grep -qE -- "-1-$1-device-files-[0-9a-f]{8}\.chk\$" || { fail "no checkpoint keyed -1-$1-device-files-...: $(key)"; return 1; }
}

cases=$here/files.cases
q15=${LISPM_CHECK_TEST_QUUX15:-}
if [ -n "$q15" ]; then
    # LISPM_CHECK_TAPS naming no tap of the pool: tcp would fail on it
    # (network.sh's no-tap), files must not use it
    LISPM_CHECK_TAPS=63 run files-15 1 -- --network files --keep "$@" --quux "$q15" "$cases" \
        && has "setting up a checkpoint" && has "over files (cold boot)" && has "(LISPM_CHECK_TAPS not used)" \
        && hasnt "lispm-check: tap " && verdicts && machines && filekey micro && ok
    run files-15-again 1 -- --network files "$@" --quux "$q15" "$cases" \
        && hasnt "setting up a checkpoint" && verdicts && ok
else
    echo "skip files-15, files-15-again, files-15-rtl: no LISPM_CHECK_TEST_QUUX15"
fi

run files-16 1 -- --network files --keep "$@" "$cases" \
    && has "setting up a checkpoint" && hasnt "lispm-check: tap " && verdicts && machines && ok

# the plants: each tool copy beside its own lispm-check-lisp/, as the tree's
plant() {  # plant DIR: a copy of the tool and of its HC-SERVE in DIR
    mkdir -p "$1/lispm-check-lisp"
    cp "$tool" "$1/lispm-check" && chmod +x "$1/lispm-check"
    cp "$(dirname "$tool")/lispm-check-lisp/hc-serve.lisp" "$1/lispm-check-lisp/hc-serve.lisp"
}
q=${q15:-}
qarg=(); [ -n "$q" ] && qarg=(--quux "$q")
plant "$work/held"
cat "$here/hc-serve-held.lisp" >> "$work/held/lispm-check-lisp/hc-serve.lisp"
tool_was=$tool tool=$work/held/lispm-check
run held 2 -- --tree "$tree" --network files "$@" "${qarg[@]}" "$cases" \
    && has "the checkpoint was refused: the file device has 1 handle open" && ok
tool=$tool_was

plant "$work/early"
sed -i "s/        done = self.path(k, 'done')/        done = self.path(k, 'ans')/" "$work/early/lispm-check"
if ! grep -qF "done = self.path(k, 'ans')" "$work/early/lispm-check"; then
    name=early; fail "no FileSession wait to plant in $tool"
else
    tool=$work/early/lispm-check
    run early 1 -- --tree "$tree" --network files "$@" "${qarg[@]}" "$cases" \
        && has "FAIL  (progn (hc-write (hc-path *hc-k* \"ans\")" && has "-> EARLY, expected 42" && ok
    tool=$tool_was
fi

# the cadr line's copy differs in its MACHINE line alone; any executable will
# do as --cadr, since the refusal comes before the machine runs
mkdir -p "$work/cadr"
sed "s/^MACHINE = 'quux'\$/MACHINE = 'cadr'/" "$tool" > "$work/cadr/lispm-check" && chmod +x "$work/cadr/lispm-check"
tool=$work/cadr/lispm-check
run cadr 2 -- --tree "$tree" --network files "$@" --cadr /bin/true "$cases" && has "which has no file device" && ok
tool=$tool_was

run ozd-server 2 -- --network files --file-server ozd "$@" "$cases" && has "--network files: the session goes through" && ok

name=harness
if python3 - "$tool" > "$out" 2>&1 <<'EOF'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader('lispm_check', sys.argv[1])
spec = importlib.util.spec_from_loader('lispm_check', loader)
lc = importlib.util.module_from_spec(spec)
loader.exec_module(lc)
os.environ['LISPM_CHECK_NETWORK'] = 'files'
try:
    lc.harness_network('/bin/true')
except lc.RunFailed as e:
    print('refused: %s' % e)
    sys.exit(0)
print('not refused')
sys.exit(1)
EOF
then has "LISPM_CHECK_NETWORK=files: " && has "drives a TELNET session of its own" && ok
else fail "harness_network took files"; fi

if [ -n "$q15" ] && [ -n "${LISPM_CHECK_TEST_NO_RTL:-}" ]; then
    echo "skip files-15-rtl: LISPM_CHECK_TEST_NO_RTL"
elif [ -n "$q15" ]; then
    run files-15-rtl 1 -- --network files --keep --engine rtl "$@" --quux "$q15" "$cases" \
        && has "setting up a checkpoint" && verdicts && machines && filekey rtl && ok
fi

[ "$fails" = 0 ] && echo "files self-test passed" || echo "files self-test FAILED ($fails)"
[ "$fails" = 0 ]
