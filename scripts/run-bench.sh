#!/bin/bash

shopt -s nullglob

export PATH=~/local/bin:$PATH

unset OPAMROOT OPAMSWITCH OCAMLPARAM OCAMLRUNPARAM

# Prereq: all switches installed, with ocaml git-pinned (as well as other packages that need fixes)

OPERF_SWITCH=4.02.1

SWITCH=flambda+bench
REFSWITCH=comparison+bench
TRUNKSWITCH=trunk+bench
OPTSWITCH=flambda-opt+bench

OPT_PARAMS="inline=50,rounds=3,unroll=1,inline-call-cost=20,inline-alloc-cost=3,inline-prim-cost=3,inline-branch-cost=3,functor-heuristics=1"
# These seem problematic: branch-inline-factor=0.500000 remove-unused-arguments=1. Obsolete ?

STARTTIME=$(date +%s)

switch-hash () {
  opam show ocaml --switch $1 --field pinned | sed 's/.*(\(.*\))/\1/'
}

DATE=$(date +%Y-%m-%d-%H%M)

BASELOGDIR=~/logs/operf

LOGDIR_TMP=$BASELOGDIR/$DATE.tmp
LOGDIR=$LOGDIR_TMP

OPERFDIR=~/.cache/operf/macro/

mkdir -p $LOGDIR

exec >$LOGDIR/log 2>&1

opam update

opam install --upgrade --yes operf-macro --switch $OPERF_SWITCH --json $LOGDIR/$OPERF_SWITCH.json

upgrade_switch() {
    local OPAMSWITCH="$1"; shift
    [ $# -eq 0 ]
    export OPAMSWITCH
    opam update --dev
    echo
    echo "=== UPGRADING SWITCH $OPAMSWITCH =="
    local OLDREF=$(switch-hash $OPAMSWITCH)
    # Requires trunk opam (as of 09-19) to recompile everything properly on
    # ocaml change!
    opam upgrade ocaml all-bench --yes --json $LOGDIR/$OPAMSWITCH.json
}

upgrade_switch $REFSWITCH
upgrade_switch $SWITCH
upgrade_switch $TRUNKSWITCH
upgrade_switch $OPTSWITCH

RUNNAME=$DATE-$(switch-hash $SWITCH)-$(switch-hash $REFSWITCH)

LOGDIR=$BASELOGDIR/$RUNNAME
mv $LOGDIR_TMP $LOGDIR

opamjson2html $LOGDIR/$REFSWITCH.json* $LOGDIR/$SWITCH.json* $LOGDIR/$TRUNKSWITCH.json* $LOGDIR/$OPTSWITCH.json* >$LOGDIR/build.html

UPGRADE_TIME=$(($(date +%s) - STARTTIME))

echo -e "\n===== OPAM UPGRADE DONE in ${UPGRADE_TIME}s =====\n"

eval $(opam config env --switch $SWITCH)

loadavg() {
  awk '{print 100*$1}' /proc/loadavg
}

if [ "x$1" != "x--nowait" ]; then

    # let the loadavg settle down...
    sleep 60

    while [ $(loadavg) -gt 60 ]; do
        if [ $(($(date +%s) - STARTTIME)) -gt $((3600 * 12)) ]; then
            echo "COULD NOT START FOR THE PAST 12 HOURS; ABORTING RUN" >&2
            exit 10
        else
            echo "System load detected, waiting to run bench (retrying in 5 minutes)"
            wall "It's BENCH STARTUP TIME, but the load is too high. Please clear the way!"
            sleep 300
        fi
    done
fi

rm -f $OPERFDIR/*/$SWITCH.*
rm -f $OPERFDIR/*/$REFSWITCH.*
rm -f $OPERFDIR/*/$TRUNKSWITCH.*
rm -f $OPERFDIR/*/$OPTSWITCH.*

wall " -- STARTING BENCHES -- don't put load on the machine. Thanks"

BENCH_START_TIME=$(date +%s)

echo
echo "=== BENCH START ==="
nice -n -5 opam config exec --switch $OPERF_SWITCH -- operf-macro run --switch $SWITCH
nice -n -5 opam config exec --switch $OPERF_SWITCH -- operf-macro run --switch $REFSWITCH
nice -n -5 opam config exec --switch $OPERF_SWITCH -- operf-macro run --switch $TRUNKSWITCH
nice -n -5 opam config exec --switch $OPERF_SWITCH -- operf-macro run --switch $OPTSWITCH

mkdir -p $LOGDIR
cp -r $OPERFDIR/* $LOGDIR
opam config exec --switch $OPERF_SWITCH -- operf-macro summarize -b csv >$LOGDIR/summary.csv

BENCH_TIME=$(($(date +%s) - BENCH_START_TIME))

cd $BASELOGDIR
rm -rf latest
mkdir latest
echo '<!DOCTYPE html><html><head><title>Flambda latest logs redirect</title><meta http-equiv="refresh" content="0; url=../'"$RUNNAME"'/" /></head></html>' >latest/index.html

cat > $LOGDIR/index.html <<EOF
<html>
<head><title>Operf comparison $DATE, flambda@$(switch-hash $SWITCH)</title></head>
<body>
<h2>Operf comparison $DATE, flambda@$(switch-hash $SWITCH)</h2>
<a href="build.html">Build logs</a>
<ul>
EOF

mklog() {
    BASE=$1; shift
    TEST=$1; shift
    FILE=$1; shift
    if [ $# -gt 0 ]; then NOTE=$1; shift; else NOTE=; fi
    [ $# -eq 0 ]
    bench2html \
        "$DATE ${TEST%+bench}@$(switch-hash $TEST) versus ${BASE%+bench}@$(switch-hash $BASE)$NOTE" \
        $BASE $TEST >$LOGDIR/$FILE
    echo "<li><a href="$FILE">${TEST%+bench} vs ${BASE%+bench}$NOTE</a></li>" >> $LOGDIR/index.html
}

mklog $REFSWITCH $SWITCH flambda_base.html
mklog $TRUNKSWITCH $SWITCH flambda_trunk.html
mklog $REFSWITCH $OPTSWITCH flambdopt_base.html " with $OPT_PARAMS"
mklog $REFSWITCH $TRUNKSWITCH trunk_base.html

hours() {
    printf "%02d:%02d:%02d" $(($1 / 3600)) $(($1 / 60 % 60)) $(($1 % 60))
}

cat >> $LOGDIR/index.html <<EOF
</ul>
<p>Upgrade took $(hours $UPGRADE_TIME)</p>
<p>Running benches took $(hours $BENCH_TIME)</p>
<p>Total time $(hours $((UPGRADE_TIME + BENCH_TIME)))</p>
</body>
</html>
EOF
