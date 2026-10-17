#!/usr/bin/env bash
# The self-test of tools/lispm-check's network (QUUX's Ethernet contract,
# sections 3, 7 and 8 R1): a tap of the pool for every run on revision 16,
# a checkpoint for each tap index, and --network tcp beside chaos.
#
#   LISPM_CHECK_TAPS=8-9 tools/lispm-check-test/network.sh --quux W16 --band DISK --ubin DIR ...
#
# The arguments are lispm-check's and go to every run; --quux must name a
# machine of revision 16 (a wrapper that sets MUIR_QUUX_REVISION=16, say) and
# the band must be one with the network, whose SYS: is on HOST.
# LISPM_CHECK_TAPS must name two host-only taps at least, of which the first
# two, A and B, are used.  LISPM_CHECK_TEST_QUUX15, when set, names a machine
# of revision 15 for the two runs that need one.  LISPM_CHECK_TEST_TOOL names
# the tool tested (default: tools/lispm-check beside this directory), so
# that a planted copy can be run against it.  Every run uses a cache of its
# own, made empty here, so that the first one sets up over TCP; it is kept
# with the runs' files, and the end says where.  About 5 minutes on micro.
#
#   tcp          --network tcp, tap A held by another program: exit 0 on
#                tap B; the setup is made over TCP and closed cleanly, so the
#                resumed band holds only this session's connection; the
#                machine is given B's addresses and no Chaos peer (no
#                --chaos-udp), ozd is not started, the fault relay found no
#                bad Ethernet frame from the band, and the checkpoint is
#                keyed by B's address
#   order        --network chaos, both free, B alone with a checkpoint: the
#                run takes B, resuming the checkpoint tcp made (one serves
#                both networks); the machine has its Chaos cable and B's
#                addresses
#   index        B held: the run takes A and sets up A's own checkpoint
#   order-both   both free, both with checkpoints: A, the lowest, no setup
#   wait         A alone in the range and held for 5 s: the run says it
#                waits, then takes A
#   no-tap       LISPM_CHECK_TAPS naming no tap of the pool: exit 2
#   rev15-tcp    --network tcp on revision 15: exit 2, no Ethernet device
#   rev15-chaos  revision 15 over Chaos: no tap, and the key without one
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
run() {  # run NAME STATUS -- ARGS...: the tool, its exit status checked
    name=$1 want=$2; shift 3
    "$tool" "$@" > "$out" 2>&1
    got=$?
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
    elif ! head -1 "$d/quux.log" | grep -qF -- "--ethernet-socket"; then fail "the machine was given no --ethernet-socket"
    elif ! head -1 "$d/quux.log" | grep -qF -- "--ip-address $qb/30"; then fail "the machine was not given $B's address"
    elif [ -e "$d/ozd.log" ]; then fail "ozd was started"
    elif ! python3 -c 'import json, sys; d = json.load(open(sys.argv[1]))
sys.exit(not (d["bad_from_band"] == 0 and d["from_band"]["frames"] > 0))' "$d/relay.json"; then
        fail "the fault relay's report: $(cat "$d/relay.json")"
    elif ! key | grep -qE -- "-3-.*-${qb//./\\.}\.chk\$"; then fail "no checkpoint keyed by $qb: $(key)"
    else ok; fi
fi
release

# order: both free, B the only index with a checkpoint: the run takes B,
# with no setup, over Chaos this time: one checkpoint serves both networks
if run order 0 -- --network chaos --keep "$@" "$cases/chaos.cases" && has "lispm-check: tap $B, QUUX at $qb, TELNET over chaos" \
   && hasnt "setting up a checkpoint"; then
    d=$(kept)
    if ! head -1 "$d/quux.log" | grep -qF -- "--chaos-udp"; then fail "the machine has no Chaos cable"
    elif ! head -1 "$d/quux.log" | grep -qF -- "--ip-address $qb/30"; then fail "the machine was not given $B's address"
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
    run rev15-chaos 0 -- --network chaos "$@" --quux "$LISPM_CHECK_TEST_QUUX15" "$cases/plain.cases" \
        && hasnt "lispm-check: tap " && { key | grep -E -- '-2-[a-z]+(-device)?\.chk$' > /dev/null \
        || fail "no revision 15 checkpoint keyed as before: $(key)"; } && ok
else
    echo "skip rev15-tcp, rev15-chaos: no LISPM_CHECK_TEST_QUUX15"
fi

[ "$fails" = 0 ] && echo "network self-test passed" || echo "network self-test FAILED ($fails)"
[ "$fails" = 0 ]
