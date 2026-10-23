#!/usr/bin/env bash
# The self-test of tools/lispm-check's network (QUUX's Ethernet contract,
# sections 3, 7 and 8 R1): a tap of the pool for every run on QUUX, a
# checkpoint for each tap index, and --network tcp, the default; the refusal
# of a machine that names another revision than 16; and the refusal by name
# of Chaos and ozd, which left main's tools (QUUX has no Chaosnet interface).
# It read "and --network tcp beside chaos" until then.
#
#   LISPM_CHECK_TAPS=8-9 tools/lispm-check-test/network.sh --quux W16 --band DISK --ubin DIR ...
#
# The arguments are lispm-check's and go to every run; --quux must name
# QUUX's machine (a wrapper that gives the boot PROM, say: the tool sets
# MUIR_QUUX_REVISION=16) and the band must be one with the network, whose
# SYS: is on the file device's pathname host (HOST or FILES, as the band
# names it).
# LISPM_CHECK_TAPS must name two host-only taps at least, of which the first
# two, A and B, are used.  LISPM_CHECK_TEST_QUUX15, which named a machine of
# revision 15 for the lanes that needed one, left with that revision (the
# removal of revisions 13-15).  LISPM_CHECK_TEST_TOOL names
# the tool tested (default: tools/lispm-check beside this directory), so
# that a planted copy can be run against it.  Every run uses a cache of its
# own, made empty here, so that the first one sets up over TCP; it is kept
# with the runs' files, and the end says where.  About 5 minutes on micro.
# Last it runs files.sh, the lanes of --network files, with the same
# arguments; it needs no tap and runs alone too.
# The Chaos cases (chaos-own, variable) ran on a band from before step R3 of
# section 8, LISPM_CHECK_TEST_CHAOS_BAND with its LISPM_CHECK_TEST_CHAOS_UBIN
# and LISPM_CHECK_TEST_CHAOS_QUUX, skipped without it, until main's Chaos
# and ozd path left these tools; the CADR's (cadr-default) went with it.
# A stand-in ozd that notes each start and exits is given for every run
# here, files.sh's included, as LISPM_CHECK_OZD and as the first ozd on
# PATH, so that a tool that started ozd by either would be seen: no-ozd, the
# last case, wants its log empty.
#
#   tcp          --network tcp, tap A held by another program: exit 0 on
#                tap B; the setup is made over TCP and closed cleanly, so the
#                resumed band holds only this session's connection; the
#                machine is given B's addresses and no Chaos peer (no
#                --chaos-udp), ozd is not started, the fault relay found no
#                bad Ethernet frame from the band, and the checkpoint is
#                keyed by B's address
#                (and no --chaos-address: since step R3 of section 8 the
#                band has no NCP, and TCP's machine no Chaos address)
#   (chaos-own, --network chaos with a checkpoint of its own keyed -chaos,
#   left with main's Chaos path)
#   index        B held: the run takes A and sets up A's own checkpoint
#   order-both   both free, both with checkpoints: A, the lowest, no setup
#   wait         A alone in the range and held for 5 s: the run says it
#                waits, then takes A
#   no-tap       LISPM_CHECK_TAPS naming no tap of the pool: exit 2
#   (rev15-tcp, --network tcp on revision 15, exit 2 for no Ethernet device,
#   and rev15-chaos, revision 15 over Chaos with no tap, left with 15)
#
# Chaos and ozd, refused by name before the machine is asked anything or a
# tap taken, no checkpoint set up, the refusal worded for QUUX:
#   chaos-refused   --network chaos: exit 2, "QUUX has no Chaosnet interface"
#   chaos-variable  LISPM_CHECK_NETWORK=chaos: the same, naming the variable
#   harness-chaos   LISPM_CHECK_NETWORK=chaos through harness_network (the
#                   tools that drive TELNET sessions of their own): the same
#   ozd-refused     --file-server ozd: exit 2, the same words
#   ozd-variable    LISPM_CHECK_FILE_SERVER=ozd: the same, naming the variable
#   ozd-flags       --ozd, --ozd-file-dates and --ozd-timezone, each alone:
#                   exit 2, the same words
#
# The machine, asked once what it runs (no tap needed):
#   other-revision  a stand-in quux whose start names revision 15, as an
#                   older quux's or a wrapper's that sets 15 does: exit 2,
#                   refused, naming it, before any setup
#   variable-set    MUIR_QUUX_REVISION=15 in the environment: exit 2, refused
#                   rather than overridden
#   no-revision     a wrapper whose start names no revision, as quux's will
#                   once it runs one QUUX alone, over --quux's machine: exit 0,
#                   taken for the current one, over tcp on a tap
#
# The default, since R2's switch (section 8 R2): what a run gets when
# neither --network nor LISPM_CHECK_NETWORK names a network.  The stand-in
# ozd, above, notes each start, so that any start of ozd is seen.
#   default        revision 16: over tcp, on a tap, no Chaos cable, the
#                  stand-in ozd never started
#   (variable, LISPM_CHECK_NETWORK=chaos taken as --network chaos with ozd
#   started, left with main's Chaos path: chaos-variable refuses it now)
#   (rev15-default, revision 15 with no tap over Chaos, left with 15)
#   (cadr-default, a copy of the tool whose MACHINE line said cadr, run with
#   no tap over Chaos with ozd, left when main's tools stopped offering the
#   CADR; the cadr line keeps its own copy)
#   rtl-flags      revision 16 on rtl through a wrapper that adds the rtl-only
#                  flags of the soak's rtl lanes (--memory-timing kria --cache
#                  65536) to --quux's machine: the machine is still asked and
#                  says 16, so the run goes over tcp, the stand-in ozd never
#                  started.  The asking once forced --micro, which quux refuses
#                  with those flags, and every such run failed (exit 2, "did
#                  not say which revision it runs").  Its setup is on rtl:
#                  about 5 minutes more
#   no-ozd         the stand-in ozd's log empty after every run above and
#                  files.sh's
here=$(cd "$(dirname "$0")" && pwd)
tool=${LISPM_CHECK_TEST_TOOL:-$here/../lispm-check}
relay=$here/../fault-relay/relay
fails=0
out=$(mktemp)
mkdir -p "$here/../../run" && work=$(mktemp -d "$here/../../run/lispm-check-network-test.XXXXXX")
held=
cleanup() {
    [ -n "$held" ] && kill "$held" 2>/dev/null
    rm -f "$out"
    echo "network.sh: the runs' cache and kept files are in $work"
}
trap cleanup EXIT
export XDG_CACHE_HOME=$work/cache
cases=$work/cases
mkdir -p "$cases"
# the band's side: over TCP the session's own connection alone, since the
# setup closed cleanly (over Chaos, until it left these tools, no TCP
# connection at all: chaos.cases, '(length ip::tcp-connections) => 0')
printf '(+ 1 2) => 3\n(length ip::tcp-connections) => 1\n' > "$cases/tcp.cases"
printf '(+ 1 2) => 3\n' > "$cases/plain.cases"
# The stand-in ozd for every run, files.sh's too: it notes its arguments
# and exits 1.  It was made below, for default and rtl-flags alone, and
# given to them as --ozd, which is refused now.
trip=$work/ozd-bin/ozd trips=$work/ozd-stand-in.log
mkdir -p "$work/ozd-bin"
printf '#!/bin/sh\necho "$*" >> %s\nexit 1\n' "$trips" > "$trip"
chmod +x "$trip"
export LISPM_CHECK_OZD=$trip PATH=$work/ozd-bin:$PATH
ozd_lines() { if [ -e "$trips" ]; then wc -l < "$trips"; else echo 0; fi; }

taps=()
for part in ${LISPM_CHECK_TAPS//,/ }; do
    case $part in
        *-*) for ((i=${part%-*}; i<=${part#*-}; i++)); do taps+=("$i"); done ;;
        *) taps+=("$part") ;;
    esac
done
if [ "${#taps[@]}" -lt 2 ]; then
    echo "network.sh: LISPM_CHECK_TAPS must name two taps at least (now: '${LISPM_CHECK_TAPS:-}')" >&2
    exit 2
fi
A=quux${taps[0]} B=quux${taps[1]}
addr() {  # QUUX's address behind tap $1: the /30's other host address
    local host; host=$(ip -4 -o addr show dev "$1" | awk '{print $4}' | cut -d/ -f1)
    awk -v h="$host" 'BEGIN { split(h, o, "."); x = o[4] % 4; o[4] += (x == 1 ? 1 : -1);
                              print o[1] "." o[2] "." o[3] "." o[4] }'
}
qa=$(addr "$A") qb=$(addr "$B")

hold() {  # hold tap $1 by a relay of the test's own, until release
    rm -f "$work/hold.out"
    python3 "$relay" --tap "$1" "$work/hold.sock" > "$work/hold.out" 2>&1 &
    held=$!
    for _ in $(seq 100); do [ -s "$work/hold.out" ] && break; sleep 0.1; done
    grep -q "^$1 " "$work/hold.out" || { echo "network.sh: could not hold $1: $(cat "$work/hold.out")" >&2; exit 2; }
}
release() { kill "$held" 2>/dev/null; wait "$held" 2>/dev/null; held=; }

fail() { echo "FAIL $name: $*"; sed 's/^/    /' "$out"; fails=$((fails+1)); }
extra=()
run() {  # run NAME STATUS -- ARGS...: the tool, its exit status checked
    name=$1 want=$2; shift 3
    "$tool" "$@" "${extra[@]}" > "$out" 2>&1
    got=$? extra=()
    [ "$got" = "$want" ] || { fail "exit $got, wanted $want"; return 1; }
}
has() { grep -qF -- "$1" "$out" || { fail "no \"$1\" in the output"; return 1; }; }
hasnt() { ! grep -qF -- "$1" "$out" || { fail "\"$1\" in the output"; return 1; }; }
kept() { sed -n 's/^lispm-check: run files kept in //p' "$out" | tail -1; }
ok() { echo "ok   $name"; }
key() { ls "$XDG_CACHE_HOME"/muir-sys-check/checkpoints/ 2>/dev/null; }

# tcp: A held by another program, so the run takes B, sets up B's own
# checkpoint over TCP and resumes it
hold "$A"
if run tcp 0 -- --network tcp --keep "$@" "$cases/tcp.cases" && has "lispm-check: tap $B, QUUX at $qb, TELNET over tcp" \
   && has "setting up a checkpoint" && has "tap index ${taps[1]}, over tcp"; then
    d=$(kept)
    # the command line heads the machine's log; quux's own lines name the
    # flag too ("--chaos-udp is the cable")
    if head -1 "$d/quux.log" | grep -qF -- '--chaos-udp'; then fail "the machine was given --chaos-udp"
    elif head -1 "$d/quux.log" | grep -qF -- '--chaos-address'; then fail "the machine was given --chaos-address"
    elif ! head -1 "$d/quux.log" | grep -qF -- "--ethernet-socket"; then fail "the machine was given no --ethernet-socket"
    elif ! head -1 "$d/quux.log" | grep -qF -- "--ip-address $qb/30"; then fail "the machine was not given $B's address"
    elif [ -e "$d/ozd.log" ]; then fail "ozd was started"
    elif ! python3 -c 'import json, sys; d = json.load(open(sys.argv[1]))
sys.exit(not (d["bad_from_band"] == 0 and d["from_band"]["frames"] > 0))' "$d/relay.json"; then
        fail "the fault relay's report: $(cat "$d/relay.json")"
    elif ! key | grep -qE -- "-4-.*-${qb//./\\.}\.chk\$"; then fail "no checkpoint keyed by $qb: $(key)"
    else ok; fi
fi
release

# chaos-own ran here, on a band from before R3 given as the run's last
# arguments by chaos(), until main's Chaos path left these tools:
#   chaos() {
#       [ -n "${LISPM_CHECK_TEST_CHAOS_BAND:-}" ] || { echo "skip $1: no LISPM_CHECK_TEST_CHAOS_BAND"; return 1; }
#       [ $# -lt 2 ] || [ -n "$2" ] || { echo "skip $1: no LISPM_CHECK_TEST_CHAOS_QUUX15"; return 1; }
#       extra=(--band "$LISPM_CHECK_TEST_CHAOS_BAND" --ubin "$LISPM_CHECK_TEST_CHAOS_UBIN"
#              --quux "${2:-$LISPM_CHECK_TEST_CHAOS_QUUX}")
#   }
#   if chaos chaos-own && run chaos-own 0 -- --network chaos --keep "$@" "$cases/chaos.cases" && has "TELNET over chaos" \
#      && has "setting up a checkpoint"; then
#       d=$(kept)
#       if ! head -1 "$d/quux.log" | grep -qF -- "--chaos-udp"; then fail "the machine has no Chaos cable"
#       elif ! head -1 "$d/quux.log" | grep -qF -- "--chaos-address 177201"; then fail "the machine has no --chaos-address 177201"
#       elif ! key | grep -qE -- "-4-.*-chaos-"; then fail "no checkpoint keyed -chaos: $(key)"
#       else ok; fi
#   fi

# index: B held, so the run takes A and sets up A's own checkpoint
hold "$B"
run index 0 -- --network tcp "$@" "$cases/tcp.cases" && has "lispm-check: tap $A, QUUX at $qa" \
    && has "tap index ${taps[0]}, over tcp" && { key | grep -qF -- "-$qa.chk" || fail "no checkpoint keyed by $qa: $(key)"; } && ok
release

# order-both: both free, both with checkpoints: the lowest, A, with no setup
run order-both 0 -- --network tcp "$@" "$cases/tcp.cases" && has "lispm-check: tap $A, QUUX at $qa" \
    && hasnt "setting up a checkpoint" && ok

hold "$A"
( sleep 5; kill "$held" ) &
LISPM_CHECK_TAPS=${taps[0]} run wait 0 -- --network tcp "$@" "$cases/tcp.cases" \
    && has "is held; waiting for one" && has "lispm-check: tap $A, QUUX at $qa" && ok
wait; held=

LISPM_CHECK_TAPS=63 run no-tap 2 -- --network tcp "$@" "$cases/tcp.cases" && has "no host-only tap of the pool" && ok

# Chaos and ozd, refused by name: nothing asked of the machine, no tap, no
# setup.  refused NAME WORDS [VAR=VALUE] -- ARGS...: the run, exit 2, the
# refusal's words WORDS (its name, then "QUUX has no Chaosnet interface")
refused() {
    local n=$1 words=$2; shift 2
    local env=()
    [ "$1" != -- ] && { env=("$1"); shift; }
    shift
    name=$n
    env "${env[@]}" "$tool" "$@" > "$out" 2>&1
    got=$?
    [ "$got" = 2 ] || { fail "exit $got, wanted 2"; return 1; }
    has "$words: QUUX has no Chaosnet interface" && hasnt "setting up a checkpoint" && hasnt "lispm-check: tap " && ok
}
refused chaos-refused --network\ chaos -- --network chaos "$@" "$cases/plain.cases"
refused chaos-variable LISPM_CHECK_NETWORK=chaos LISPM_CHECK_NETWORK=chaos -- "$@" "$cases/plain.cases"
refused ozd-refused --file-server\ ozd -- --file-server ozd "$@" "$cases/plain.cases"
refused ozd-variable LISPM_CHECK_FILE_SERVER=ozd LISPM_CHECK_FILE_SERVER=ozd -- "$@" "$cases/plain.cases"
refused "ozd-flags --ozd" --ozd -- "$@" --ozd "$trip" "$cases/plain.cases"
refused "ozd-flags --ozd-file-dates" --ozd-file-dates -- "$@" --ozd-file-dates mit "$cases/plain.cases"
refused "ozd-flags --ozd-timezone" --ozd-timezone -- "$@" --ozd-timezone 5 "$cases/plain.cases"
name=harness-chaos
if LISPM_CHECK_NETWORK=chaos python3 - "$tool" > "$out" 2>&1 <<'PYEOF'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader('lispm_check', sys.argv[1])
spec = importlib.util.spec_from_loader('lispm_check', loader)
lc = importlib.util.module_from_spec(spec)
loader.exec_module(lc)
try:
    lc.harness_network('/bin/true')
except lc.RunFailed as e:
    print('refused: %s' % e)
    sys.exit(0)
print('not refused')
sys.exit(1)
PYEOF
then has "refused: LISPM_CHECK_NETWORK=chaos: QUUX has no Chaosnet interface" && ok
else fail "harness_network took LISPM_CHECK_NETWORK=chaos"; fi

# rev15-tcp and rev15-chaos ran on LISPM_CHECK_TEST_QUUX15 until revision
# 15 left these tools:
# if [ -n "${LISPM_CHECK_TEST_QUUX15:-}" ]; then
#     run rev15-tcp 2 -- --network tcp "$@" --quux "$LISPM_CHECK_TEST_QUUX15" "$cases/tcp.cases" \
#         && has "which has no Ethernet device" && ok
#     chaos rev15-chaos "${LISPM_CHECK_TEST_CHAOS_QUUX15:-}" && run rev15-chaos 0 -- --network chaos "$@" --quux "$LISPM_CHECK_TEST_QUUX15" "$cases/plain.cases" \
#         && hasnt "lispm-check: tap " && { key | grep -E -- '-2-[a-z]+(-device)?\.chk$' > /dev/null \
#         || fail "no revision 15 checkpoint keyed as before: $(key)"; } && ok
# else
#     echo "skip rev15-tcp, rev15-chaos: no LISPM_CHECK_TEST_QUUX15"
# fi

# The machine asked what it runs: one QUUX is current, and a machine that
# names another revision than 16 is refused before any setup.  The stand-in
# prints an older quux's start and exits; given last, it is the --quux run.
stand=$work/quux15-stand-in
printf '#!/bin/sh\necho "machine: quux, revision 15: a stand-in"\nexit 0\n' > "$stand"
chmod +x "$stand"
run other-revision 2 -- "$@" --quux "$stand" "$cases/plain.cases" \
    && has "says it runs QUUX revision 15" && hasnt "setting up a checkpoint" && ok
MUIR_QUUX_REVISION=15 run variable-set 2 -- "$@" "$cases/plain.cases" \
    && has "MUIR_QUUX_REVISION=15: " && hasnt "setting up a checkpoint" && ok
# no-revision: a start naming no revision, over the caller's --quux, the last
# one given; only the asking (-c /dev/null --stop-after 1) is answered by the
# wrapper, every other start is the machine's own
qn=
prev=
for x in "$@"; do [ "$prev" = --quux ] && qn=$x; case $x in --quux=*) qn=${x#--quux=} ;; esac; prev=$x; done
if [ -n "$qn" ]; then
    printf '#!/bin/sh\ncase " $* " in *" --stop-after 1 "*) echo "machine: quux: a stand-in naming no revision"; exit 0 ;; esac\nexec %s "$@"\n' "$qn" > "$work/quux-no-revision"
    chmod +x "$work/quux-no-revision"
    LISPM_CHECK_NETWORK= run no-revision 0 -- "$@" --quux "$work/quux-no-revision" "$cases/tcp.cases" \
        && has "TELNET over tcp (the default)" && ok
else
    echo "skip no-revision: no --quux given"
fi

# The default (section 8 R2).  The stand-in ozd (above) was made here and
# given as --ozd; chaos_cable, the check of a run over Chaos with ozd, went
# with main's Chaos path:
#   chaos_cable() {  # the kept run's machine had its Chaos cable and ozd ran
#       local d; d=$(kept)
#       if ! head -1 "$d/${1:-quux}.log" | grep -qF -- '--chaos-udp'; then fail "the machine has no Chaos cable"
#       elif [ ! -e "$d/ozd.log" ]; then fail "ozd was not started"
#       else return 0; fi
#       return 1
#   }

# default: revision 16, neither the flag nor the variable: tcp, and no ozd
# (it was given --ozd "$trip", with the log removed first)
t0=$(ozd_lines)
if LISPM_CHECK_NETWORK= run default 0 -- --keep "$@" "$cases/tcp.cases" \
   && has "TELNET over tcp"; then
    d=$(kept)
    if [ "$(ozd_lines)" != "$t0" ]; then fail "ozd was started: $(tail -1 "$trips")"
    elif [ -e "$d/ozd.log" ]; then fail "ozd was started (its log in $d)"
    elif head -1 "$d/quux.log" | grep -qF -- '--chaos-udp'; then fail "the machine was given --chaos-udp"
    elif ! head -1 "$d/quux.log" | grep -qF -- '--ethernet-socket'; then fail "the machine was given no --ethernet-socket"
    else ok; fi
elif [ "$(ozd_lines)" != "$t0" ]; then
    echo "    ozd was started: $(tail -1 "$trips")"
fi

# variable ran LISPM_CHECK_NETWORK=chaos as --network chaos, until main's
# Chaos path left these tools (chaos-variable, above, refuses it now):
#   chaos variable && LISPM_CHECK_NETWORK=chaos run variable 0 -- --keep "$@" "$cases/chaos.cases" \
#       && has "TELNET over chaos" && chaos_cable && ok

# rev15-default, until revision 15 left these tools:
# if [ -n "${LISPM_CHECK_TEST_QUUX15:-}" ]; then
#     chaos rev15-default "${LISPM_CHECK_TEST_CHAOS_QUUX15:-}" && LISPM_CHECK_NETWORK= run rev15-default 0 -- --keep "$@" --quux "$LISPM_CHECK_TEST_QUUX15" "$cases/plain.cases" \
#         && hasnt "lispm-check: tap " && chaos_cable && ok
# else
#     echo "skip rev15-default: no LISPM_CHECK_TEST_QUUX15"
# fi

# cadr-default ran a copy of the tool as the CADR, until main's tools stopped
# offering it (the cadr line keeps its own copy):
#   if [ -n "${LISPM_CHECK_TEST_CADR:-}" ] && [ -n "${LISPM_CHECK_TEST_CADR_BAND:-}" ]; then
#       # the cadr line's copy of the tool differs in its MACHINE line alone
#       mkdir -p "$work/cadr-tool"
#       sed "s/^MACHINE = 'quux'\$/MACHINE = 'cadr'/" "$tool" > "$work/cadr-tool/lispm-check"
#       chmod +x "$work/cadr-tool/lispm-check"
#       cb=$LISPM_CHECK_TEST_CADR_BAND
#       if ! grep -q "^MACHINE = 'cadr'\$" "$work/cadr-tool/lispm-check"; then
#           name=cadr-default; fail "no MACHINE line to change in $tool"
#       else
#           tool_was=$tool tool=$work/cadr-tool/lispm-check
#           LISPM_CHECK_NETWORK= run cadr-default 0 -- --keep "$@" --cadr "$LISPM_CHECK_TEST_CADR" --band "$cb" \
#               --ubin "$(dirname "$cb")/ubin" --tree "${LISPM_CHECK_TEST_CADR_TREE:-$(dirname "$(dirname "$here")")}" \
#               --file-server auto "$cases/plain.cases" \
#               && hasnt "lispm-check: tap " && has "files served by ozd: cadr has no file device" && chaos_cable cadr && ok
#           tool=$tool_was
#       fi
#   else
#       echo "skip cadr-default: no LISPM_CHECK_TEST_CADR and LISPM_CHECK_TEST_CADR_BAND"
#   fi

# rtl-flags: the caller's --quux, the last one given, wrapped with the soak's
# rtl-only flags (on a resume too, as the lane wrappers give them)
q16=
prev=
for x in "$@"; do [ "$prev" = --quux ] && q16=$x; case $x in --quux=*) q16=${x#--quux=} ;; esac; prev=$x; done
if [ -n "$q16" ]; then
    printf '#!/bin/sh\nexec %s "$@" --memory-timing kria --cache 65536\n' "$q16" > "$work/q16-rtl-flags"
    chmod +x "$work/q16-rtl-flags"
    # it was given --ozd "$trip", with the log removed first
    t0=$(ozd_lines)
    if LISPM_CHECK_NETWORK= run rtl-flags 0 -- --keep "$@" --quux "$work/q16-rtl-flags" --engine rtl \
           "$cases/tcp.cases" && has "TELNET over tcp (the default)"; then
        d=$(kept)
        if [ "$(ozd_lines)" != "$t0" ]; then fail "ozd was started: $(tail -1 "$trips")"
        elif ! grep -q '^cache: 65536 words' "$d/quux.log"; then fail "the machine ran without the wrapper's flags (no 'cache: 65536 words' in its log)"
        else ok; fi
    fi
else
    echo "skip rtl-flags: no --quux given"
fi

# --network files, which needs no tap: its own script, with the same
# arguments (and LISPM_CHECK_TEST_TOOL)
"$here/files.sh" "$@" || fails=$((fails+1))

# no-ozd: the stand-in, given to every run above and to files.sh's, never
# started
name=no-ozd
if [ "$(ozd_lines)" != 0 ]; then echo "FAIL no-ozd: ozd was started $(ozd_lines) times: $(head -3 "$trips")"; fails=$((fails+1))
else ok; fi

[ "$fails" = 0 ] && echo "network self-test passed" || echo "network self-test FAILED ($fails)"
[ "$fails" = 0 ]
