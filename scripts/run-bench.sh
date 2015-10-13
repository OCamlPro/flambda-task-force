#!/bin/bash

shopt -s nullglob

export PATH=~/local/bin:$PATH

unset OPAMROOT OPAMSWITCH OCAMLPARAM OCAMLRUNPARAM

# Prereq: all switches installed, with ocaml git-pinned (as well as other packages that need fixes)

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

upgrade_switch() {
    local OPAMSWITCH="$1"; shift
    export OPAMSWITCH
    echo
    echo "=== UPGRADING SWITCH $OPAMSWITCH =="
    if [ $# -gt 0 ]; then
        local OCAMLPARAM="$1"; shift
        export OCAMLPARAM
    fi
    [ $# -eq 0 ]
    local OLDREF=$(switch-hash $OPAMSWITCH)
    # Requires trunk opam (as of 09-19) to recompile everything properly on
    # ocaml change!
    opam install --upgrade ocaml all-bench operf-macro --yes --json $LOGDIR/$OPAMSWITCH.json
    # Install operf-macro on all switches, because it pulls dependencies that
    # trigger depopts in some benches, and we want exactly the same setup.
    # opam install operf-macro --yes --json $LOGDIR/$OPAMSWITCH-operf.json
}

upgrade_switch $REFSWITCH
upgrade_switch $SWITCH
upgrade_switch $TRUNKSWITCH
upgrade_switch $OPTSWITCH "_,$OPT_PARAMS"

RUNNAME=$DATE-$(switch-hash $SWITCH)-$(switch-hash $REFSWITCH)

LOGDIR=$BASELOGDIR/$RUNNAME
mv $LOGDIR_TMP $LOGDIR

opamjson2html $LOGDIR/$REFSWITCH.json* $LOGDIR/$SWITCH.json* $LOGDIR/$TRUNKSWITCH.json* $LOGDIR/$OPTSWITCH.json* >$LOGDIR/build.html

eval $(opam config env --switch $SWITCH)

loadavg() {
  awk '{print 100*$1}' /proc/loadavg
}
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

rm -f $OPERFDIR/*/$SWITCH.*
rm -f $OPERFDIR/*/$REFSWITCH.*
rm -f $OPERFDIR/*/$TRUNKSWITCH.*
rm -f $OPERFDIR/*/$OPTSWITCH.*

wall " -- STARTING BENCHES -- don't put load on the machine. Thanks"

echo
echo "=== BENCH START ==="
nice -n -5 opam config exec --switch $REFSWITCH -- operf-macro run --switch $SWITCH
nice -n -5 opam config exec --switch $REFSWITCH -- operf-macro run --switch $REFSWITCH
nice -n -5 opam config exec --switch $REFSWITCH -- operf-macro run --switch $TRUNKSWITCH
nice -n -5 opam config exec --switch $REFSWITCH -- operf-macro run --switch $OPTSWITCH

mkdir -p $LOGDIR
cp -r $OPERFDIR/* $LOGDIR
opam config exec --switch $REFSWITCH -- operf-macro summarize -b csv >$LOGDIR/summary.csv

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

cat >> $LOGDIR/index.html <<EOF
</ul>
</body>
</html>
EOF
