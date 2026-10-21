#!/usr/bin/env bash
# The self-test of tools/lispm-check's network (QUUX's Ethernet contract,
# sections 3, 7 and 8 R1): a tap of the pool for every run on revision 16,
# a checkpoint for each tap index, and --network tcp beside chaos.
#
#   LISPM_CHECK_TAPS=8-9 tools/lispm-check-test/network.sh --quux W16 --band DISK --ubin DIR ...
#
# The arguments are lispm-check's and go to every run; --quux must name a
# machine of revision 16 (a wrapper that sets MUIR_QUUX_REVISION=16, say) and
# the band must be one with the network, whose SYS: is on the file device's
# pathname host (HOST or FILES, as the band names it).
# LISPM_CHECK_TAPS must name two host-only taps at least, of which the first
# two, A and B, are used.  LISPM_CHECK_TEST_QUUX15, when set, names a machine
# of revision 15 for the two runs that need one.  LISPM_CHECK_TEST_TOOL names
# the tool tested (default: tools/lispm-check beside this directory), so
# that a planted copy can be run against it.  Every run uses a cache of its
# own, made empty here, so that the first one sets up over TCP; it is kept
# with the runs' files, and the end says where.  About 5 minutes on micro.
# Last it runs files.sh, the lanes of --network files, with the same
# arguments; it needs no tap and runs alone too.
# Since step R3 of section 8 the band has no Chaos, so the Chaos cases
# (chaos-own, rev15-chaos, variable, rev15-default) run on a band from before
# R3 with both networks, LISPM_CHECK_TEST_CHAOS_BAND, its ubin/
# LISPM_CHECK_TEST_CHAOS_UBIN and its machines LISPM_CHECK_TEST_CHAOS_QUUX
# (revision 16) and LISPM_CHECK_TEST_CHAOS_QUUX15, given after the arguments;
# without that band they are skipped.
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
#   chaos-own    --network chaos, both free, B alone with tcp's checkpoint:
#                the run sets up a checkpoint of its own, keyed -chaos, as
#                its machine has --chaos-address 177201 and its Chaos cable,
#                which tcp's has not (until R3 one checkpoint served both
#                networks, the run took B and resumed tcp's: the case order)
#   index        B held: the run takes A and sets up A's own checkpoint
#   order-both   both free, both with checkpoints: A, the lowest, no setup
#   wait         A alone in the range and held for 5 s: the run says it
#                waits, then takes A
#   no-tap       LISPM_CHECK_TAPS naming no tap of the pool: exit 2
#   rev15-tcp    --network tcp on revision 15: exit 2, no Ethernet device
#   rev15-chaos  revision 15 over Chaos: no tap, and the key without one
#
# The default, since R2's switch (section 8 R2): what a run gets when
# neither --network nor LISPM_CHECK_NETWORK names a network.  ozd is given
# as a stand-in that notes each start and exits, so that any start of ozd
# fails the run and is seen; where ozd must start, the real one is given.
#   default        revision 16: over tcp, on a tap, no Chaos cable, the
#                  stand-in ozd never started
#   variable       LISPM_CHECK_NETWORK=chaos on revision 16: over chaos, as
#                  --network chaos, ozd started
#   rev15-default  revision 15: no tap, the Chaos cable, ozd started
#   cadr-default   the CADR, when LISPM_CHECK_TEST_CADR names muir-sim's cadr
#                  and LISPM_CHECK_TEST_CADR_BAND a CADR band (its ubin/ beside
#                  it; LISPM_CHECK_TEST_CADR_TREE its tree, by default this
#                  one): a copy of the tool whose MACHINE line says cadr, as
#                  the cadr line's copy differs, runs with no tap, the files
#                  and the session by ozd, over Chaos
#   rtl-flags      revision 16 on rtl through a wrapper that adds the rtl-only
#                  flags of the soak's rtl lanes (--memory-timing kria --cache
#                  65536) to --quux's machine: the revision is still asked and
#                  is 16, so the run goes over tcp, the stand-in ozd never
#                  started.  The asking once forced --micro, which quux refuses
#                  with those flags, and every such run failed (exit 2, "did
#                  not say which revision it runs").  Its setup is on rtl:
#                  about 5 minutes more
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
# setup closed cleanly; over Chaos no TCP connection at all
printf '(+ 1 2) => 3\n(length ip::tcp-connections) => 1\n' > "$cases/tcp.cases"
printf '(+ 1 2) => 3\n(length ip::tcp-connections) => 0\n' > "$cases/chaos.cases"
printf '(+ 1 2) => 3\n' > "$cases/plain.cases"

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

# a Chaos case's band and machine, before R3's (above), as the next run's last
# arguments (extra): chaos NAME [QUUX]; or the case skipped
chaos() {
    [ -n "${LISPM_CHECK_TEST_CHAOS_BAND:-}" ] || { echo "skip $1: no LISPM_CHECK_TEST_CHAOS_BAND"; return 1; }
    [ $# -lt 2 ] || [ -n "$2" ] || { echo "skip $1: no LISPM_CHECK_TEST_CHAOS_QUUX15"; return 1; }
    extra=(--band "$LISPM_CHECK_TEST_CHAOS_BAND" --ubin "$LISPM_CHECK_TEST_CHAOS_UBIN"
           --quux "${2:-$LISPM_CHECK_TEST_CHAOS_QUUX}")
}
# chaos-own: both free, B the only index with tcp's checkpoint: over Chaos
# the run sets up its own, keyed -chaos, since its machine's Chaos switches
# are not tcp's (QUUX's Ethernet contract, section 8, step R3)
if chaos chaos-own && run chaos-own 0 -- --network chaos --keep "$@" "$cases/chaos.cases" && has "TELNET over chaos" \
   && has "setting up a checkpoint"; then
    d=$(kept)
    if ! head -1 "$d/quux.log" | grep -qF -- "--chaos-udp"; then fail "the machine has no Chaos cable"
    elif ! head -1 "$d/quux.log" | grep -qF -- "--chaos-address 177201"; then fail "the machine has no --chaos-address 177201"
    elif ! key | grep -qE -- "-4-.*-chaos-"; then fail "no checkpoint keyed -chaos: $(key)"
    else ok; fi
fi

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

if [ -n "${LISPM_CHECK_TEST_QUUX15:-}" ]; then
    run rev15-tcp 2 -- --network tcp "$@" --quux "$LISPM_CHECK_TEST_QUUX15" "$cases/tcp.cases" \
        && has "which has no Ethernet device" && ok
    chaos rev15-chaos "${LISPM_CHECK_TEST_CHAOS_QUUX15:-}" && run rev15-chaos 0 -- --network chaos "$@" --quux "$LISPM_CHECK_TEST_QUUX15" "$cases/plain.cases" \
        && hasnt "lispm-check: tap " && { key | grep -E -- '-2-[a-z]+(-device)?\.chk$' > /dev/null \
        || fail "no revision 15 checkpoint keyed as before: $(key)"; } && ok
else
    echo "skip rev15-tcp, rev15-chaos: no LISPM_CHECK_TEST_QUUX15"
fi

# The default (section 8 R2).  The stand-in ozd notes its arguments and
# exits 1; given after the caller's arguments, it is the one the tool runs.
trip=$work/ozd-stand-in trips=$work/ozd-stand-in.log
printf '#!/bin/sh\necho "$*" >> %s\nexit 1\n' "$trips" > "$trip"
chmod +x "$trip"
chaos_cable() {  # the kept run's machine had its Chaos cable and ozd ran
    local d; d=$(kept)
    if ! head -1 "$d/${1:-quux}.log" | grep -qF -- '--chaos-udp'; then fail "the machine has no Chaos cable"
    elif [ ! -e "$d/ozd.log" ]; then fail "ozd was not started"
    else return 0; fi
    return 1
}

# default: revision 16, neither the flag nor the variable: tcp, and no ozd
rm -f "$trips"
if LISPM_CHECK_NETWORK= run default 0 -- --keep "$@" --ozd "$trip" "$cases/tcp.cases" \
   && has "TELNET over tcp"; then
    d=$(kept)
    if [ -e "$trips" ]; then fail "ozd was started: $(cat "$trips")"
    elif head -1 "$d/quux.log" | grep -qF -- '--chaos-udp'; then fail "the machine was given --chaos-udp"
    elif ! head -1 "$d/quux.log" | grep -qF -- '--ethernet-socket'; then fail "the machine was given no --ethernet-socket"
    else ok; fi
elif [ -e "$trips" ]; then
    echo "    ozd was started: $(cat "$trips")"
fi

# variable: LISPM_CHECK_NETWORK still names the network, as --network does
chaos variable && LISPM_CHECK_NETWORK=chaos run variable 0 -- --keep "$@" "$cases/chaos.cases" \
    && has "TELNET over chaos" && chaos_cable && ok

if [ -n "${LISPM_CHECK_TEST_QUUX15:-}" ]; then
    chaos rev15-default "${LISPM_CHECK_TEST_CHAOS_QUUX15:-}" && LISPM_CHECK_NETWORK= run rev15-default 0 -- --keep "$@" --quux "$LISPM_CHECK_TEST_QUUX15" "$cases/plain.cases" \
        && hasnt "lispm-check: tap " && chaos_cable && ok
else
    echo "skip rev15-default: no LISPM_CHECK_TEST_QUUX15"
fi

if [ -n "${LISPM_CHECK_TEST_CADR:-}" ] && [ -n "${LISPM_CHECK_TEST_CADR_BAND:-}" ]; then
    # the cadr line's copy of the tool differs in its MACHINE line alone
    mkdir -p "$work/cadr-tool"
    sed "s/^MACHINE = 'quux'\$/MACHINE = 'cadr'/" "$tool" > "$work/cadr-tool/lispm-check"
    chmod +x "$work/cadr-tool/lispm-check"
    cb=$LISPM_CHECK_TEST_CADR_BAND
    if ! grep -q "^MACHINE = 'cadr'\$" "$work/cadr-tool/lispm-check"; then
        name=cadr-default; fail "no MACHINE line to change in $tool"
    else
        tool_was=$tool tool=$work/cadr-tool/lispm-check
        LISPM_CHECK_NETWORK= run cadr-default 0 -- --keep "$@" --cadr "$LISPM_CHECK_TEST_CADR" --band "$cb" \
            --ubin "$(dirname "$cb")/ubin" --tree "${LISPM_CHECK_TEST_CADR_TREE:-$(dirname "$(dirname "$here")")}" \
            --file-server auto "$cases/plain.cases" \
            && hasnt "lispm-check: tap " && has "files served by ozd: cadr has no file device" && chaos_cable cadr && ok
        tool=$tool_was
    fi
else
    echo "skip cadr-default: no LISPM_CHECK_TEST_CADR and LISPM_CHECK_TEST_CADR_BAND"
fi

# rtl-flags: the caller's --quux, the last one given, wrapped with the soak's
# rtl-only flags (on a resume too, as the lane wrappers give them)
q16=
prev=
for x in "$@"; do [ "$prev" = --quux ] && q16=$x; case $x in --quux=*) q16=${x#--quux=} ;; esac; prev=$x; done
if [ -n "$q16" ]; then
    printf '#!/bin/sh\nexec %s "$@" --memory-timing kria --cache 65536\n' "$q16" > "$work/q16-rtl-flags"
    chmod +x "$work/q16-rtl-flags"
    rm -f "$trips"
    if LISPM_CHECK_NETWORK= run rtl-flags 0 -- --keep "$@" --quux "$work/q16-rtl-flags" --engine rtl \
           --ozd "$trip" "$cases/tcp.cases" && has "TELNET over tcp (the default on revision 16)"; then
        d=$(kept)
        if [ -e "$trips" ]; then fail "ozd was started: $(cat "$trips")"
        elif ! grep -q '^cache: 65536 words' "$d/quux.log"; then fail "the machine ran without the wrapper's flags (no 'cache: 65536 words' in its log)"
        else ok; fi
    fi
else
    echo "skip rtl-flags: no --quux given"
fi

# --network files, which needs no tap: its own script, with the same
# arguments (and LISPM_CHECK_TEST_QUUX15, LISPM_CHECK_TEST_TOOL)
"$here/files.sh" "$@" || fails=$((fails+1))

[ "$fails" = 0 ] && echo "network self-test passed" || echo "network self-test FAILED ($fails)"
[ "$fails" = 0 ]
