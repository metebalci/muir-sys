#!/usr/bin/env bash
# The network of the tools that build their own sessions from lispm-check's
# classes (QUUX's Ethernet contract, sections 3 and 8 R2): since R2's switch
# they take a tap through lispm-check's helper and, with no network named,
# carry the session over TCP on revision 16 and over Chaos on revisions 13-15.
# Tested here: tools/system-check/warm-boot, and
# tools/microcode-check/generational-save, whose session and whose boot's
# lispm-check run are tools/cross-build/run's (Run.session, Run.lispm_check).
#
#   LISPM_CHECK_TAPS=16-17 LISPM_CHECK_PORTS=44000-44099 \
#     tools/lispm-check-test/harnesses.sh W16 W15 DISK UBIN OZD [ENGINE]
#
# W16 and W15 are machines of revisions 16 and 15 (wrappers that set
# MUIR_QUUX_REVISION and give the boot PROM); DISK holds a band with the
# network current in LOD1, with LOD2 free for generational-save's save, and
# UBIN its ubin/ with the PROM's promh.mcr; OZD is ozd, for the Chaos runs;
# ENGINE is micro (the default) or rtl.  LISPM_CHECK_TEST_TREE names the tree
# whose tools are tested (default: this one), so that another tree's can be
# run against the same checks.  Neither --network nor LISPM_CHECK_NETWORK is
# given: what is checked is the default.  On revision 16 ozd is a stand-in
# that notes each start and exits, so that any start of ozd fails the run and
# is seen.  About 30 minutes on micro.
#
#   warm-boot-16  RESULT PASS; the machine given --ethernet-socket and no
#                 --chaos-udp; the stand-in ozd never started
#   gsave-16      the same for generational-save's session and its boot
#   warm-boot-15  RESULT PASS; the machine given --chaos-udp and no
#                 --ethernet-socket; ozd started (its log)
#   gsave-15      the same for generational-save's session and its boot
here=$(cd "$(dirname "$0")" && pwd)
tree=${LISPM_CHECK_TEST_TREE:-$(dirname "$(dirname "$here")")}
w16=$1 w15=$2 disk=$3 ubin=$4 ozd=$5 engine=${6:-micro}
if [ -z "$ozd" ] || [ -z "${LISPM_CHECK_TAPS:-}" ] || [ -z "${LISPM_CHECK_PORTS:-}" ]; then
    echo "usage: LISPM_CHECK_TAPS=.. LISPM_CHECK_PORTS=LO-HI harnesses.sh W16 W15 DISK UBIN OZD [ENGINE]" >&2
    exit 2
fi
unset LISPM_CHECK_NETWORK
mkdir -p "$here/../../run" && work=$(mktemp -d "$here/../../run/lispm-check-harnesses-test.XXXXXX")
echo "harnesses.sh: tree $tree, outputs in $work"
export XDG_CACHE_HOME=$work/cache
trip=$work/ozd-stand-in trips=$work/ozd-stand-in.log
printf '#!/bin/sh\necho "$*" >> %s\nexit 1\n' "$trips" > "$trip"
chmod +x "$trip"
fails=0
fail() { echo "FAIL $name: $*"; fails=$((fails+1)); }
ok() { echo "ok   $name"; }

# head1 LOG: the machine's command line, the first line of its log
head1() { head -1 "$1" 2>/dev/null; }
tcp_machine() {  # LOG: a revision 16 machine over TCP
    if [ ! -f "$1" ]; then fail "no machine log $1"
    elif head1 "$1" | grep -qF -- '--chaos-udp'; then fail "$1: the machine was given --chaos-udp"
    elif ! head1 "$1" | grep -qF -- '--ethernet-socket'; then fail "$1: the machine was given no --ethernet-socket"
    else return 0; fi
    return 1
}
chaos_machine() {  # LOG OZDLOG: a machine over Chaos, ozd started
    if [ ! -f "$1" ]; then fail "no machine log $1"
    elif ! head1 "$1" | grep -qF -- '--chaos-udp'; then fail "$1: the machine has no Chaos cable"
    elif head1 "$1" | grep -qF -- '--ethernet-socket'; then fail "$1: the machine was given --ethernet-socket"
    elif [ ! -e "$2" ]; then fail "ozd was not started (no $2)"
    else return 0; fi
    return 1
}
passed() {  # OUT STATUS: the harness's exit and its RESULT
    if [ "$2" != 0 ]; then fail "exit $2; the end of its output:"; tail -5 "$1" | sed 's/^/    /'; return 1; fi
    grep -q '^RESULT PASS' "$1" || grep -q 'RESULT PASS$' "$1" || { fail "no RESULT PASS in $1"; return 1; }
}
lo=${LISPM_CHECK_PORTS%-*} hi=${LISPM_CHECK_PORTS#*-}

for rev in 16 15; do
    if [ "$rev" = 16 ]; then q=$w16 o=$trip; else q=$w15 o=$ozd; fi
    rm -f "$trips"

    name=warm-boot-$rev d=$work/$name
    python3 "$tree/tools/system-check/warm-boot" --out "$d" --band "$disk" --ubin "$ubin" --quux "$q" \
        --ozd "$o" --engine "$engine" > "$work/$name.out" 2>&1
    rc=$?
    if passed "$work/$name.out" $rc; then
        if [ "$rev" = 16 ]; then
            if [ -e "$trips" ]; then fail "ozd was started: $(cat "$trips")"
            else tcp_machine "$d/quux.log" && ok; fi
        else chaos_machine "$d/quux.log" "$d/ozd.log" && ok; fi
    fi

    name=gsave-$rev d=$work/$name
    rm -f "$trips"
    python3 "$tree/tools/microcode-check/generational-save" --out "$d" --work "$work/gsave-work-$rev" \
        --disk "$disk" --ubin "$ubin" --quux "$q" --ozd "$o" --ports "$lo-$hi" --engine "$engine" \
        > "$work/$name.out" 2>&1
    rc=$?
    if passed "$work/$name.out" $rc; then
        if [ "$rev" = 16 ]; then
            if [ -e "$trips" ]; then fail "ozd was started: $(cat "$trips")"
            elif tcp_machine "$d/session/session/quux.log" && tcp_machine "$d/boot/quux.log"; then
                grep -q 'TELNET over tcp' "$d/boot/lispm-check.out" && ok || fail "the boot's run was not over tcp"
            fi
        elif chaos_machine "$d/session/session/quux.log" "$d/session/session/ozd.log" \
             && chaos_machine "$d/boot/quux.log" "$d/boot/ozd.log"; then ok; fi
    fi
done

[ "$fails" = 0 ] && echo "harnesses self-test passed" || echo "harnesses self-test FAILED ($fails)"
[ "$fails" = 0 ]
