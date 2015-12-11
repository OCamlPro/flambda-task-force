#!/bin/bash

shopt -s nullglob

export PATH=~/local/bin:$PATH

unset OPAMROOT OPAMSWITCH OCAMLPARAM OCAMLRUNPARAM

# Prereq: all switches installed, with ocaml git-pinned (as well as other packages that need fixes)

OPERF_SWITCH=4.02.1

SWITCHES=(flambda+bench comparison+bench trunk+bench flambda-opt+bench flambda-classic+bench)

STARTTIME=$(date +%s)

DATE=$(date +%Y-%m-%d-%H%M)

BASELOGDIR=~/logs/operf

LOGDIR=$BASELOGDIR/$DATE

OPERFDIR=~/.cache/operf/macro/

mkdir -p $LOGDIR

echo "Output and log written into $LOGDIR" >&2

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
    # Requires trunk opam (as of 09-19) to recompile everything properly on
    # ocaml change!
    opam upgrade ocaml all-bench --yes --json $LOGDIR/$OPAMSWITCH.json
}

for SWITCH in "${SWITCHES[@]}"; do upgrade_switch $SWITCH; done

LOGSWITCHES=("${SWITCHES[@]/#/$LOGDIR/}")
opamjson2html ${LOGSWITCHES[@]/%/.json*} >$LOGDIR/build.html

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

for SWITCH in "${SWITCHES[@]}"; do
    rm -f $OPERFDIR/*/$SWITCH.*
done

wall " -- STARTING BENCHES -- don't put load on the machine. Thanks"

BENCH_START_TIME=$(date +%s)

echo
echo "=== BENCH START ==="

for SWITCH in "${SWITCHES[@]}"; do
    nice -n -5 opam config exec --switch $OPERF_SWITCH -- operf-macro run --switch $SWITCH
done

opam config exec --switch $OPERF_SWITCH -- operf-macro summarize -b csv >$LOGDIR/summary.csv
mkdir -p $LOGDIR
cp -r $OPERFDIR/* $LOGDIR

BENCH_TIME=$(($(date +%s) - BENCH_START_TIME))

ocaml-params() {
    SWITCH=$1; shift
    [ $# -eq 0 ]
    opam config env --switch $SWITCH | sed -n 's/\(OCAMLPARAM="[^"]*"\).*$/\1/p'
}

for SWITCH in "${SWITCHES[@]}"; do
    opam show ocaml --switch $SWITCH --field pinned | sed 's/.*(\(.*\))/\1/' >$LOGDIR/${SWITCH%+bench}.hash
    opam config env --switch $SWITCH | sed -n 's/\(OCAMLPARAM="[^"]*"\).*$/\1/p' >$LOGDIR/${SWITCH%+bench}.params
    opam pin --switch $SWITCH >$LOGDIR/${SWITCH%+bench}.pinned
done

hours() {
    printf "%02d:%02d:%02d" $(($1 / 3600)) $(($1 / 60 % 60)) $(($1 % 60))
}

cat > $LOGDIR/timings <<EOF
Upgrade: $(hours $UPGRADE_TIME)
Benches: $(hours $BENCH_TIME)
Total: $(hours $((UPGRADE_TIME + BENCH_TIME)))
EOF

cd $BASELOGDIR && tar -u $DATE/{*/*.summary,build.html,*.hash,*.params,timings,summary.csv} -f results.tar
gzip -c --rsyncable results.tar >results.tar.gz.2
mv results.tar.gz.2 results.tar.gz

# Static logs (should not be needed anymore, but in case)
(cat <<EOF
<html>
<head><title>Operf comparison $DATE</title></head>
<body>
<h2>Operf comparison $DATE</h2>
<a href="build.html">Build logs</a>
<ul>
EOF
for SWITCH in "${SWITCHES[@]}"; do
    if [ "$SWITCH" = "comparison+bench" ]; then continue; fi
    HASH=$(cat $LOGDIR/${SWITCH%+bench}.hash)
    FILE="${SWITCH%+bench}@$HASH.html"
    bench2html \
        "$DATE ${SWITCH%+bench}@${HASH}" \
        comparison+bench $SWITCH >$LOGDIR/$FILE
    echo "<li><a href=\"$FILE\">${SWITCH%+bench}</a></li>"
done
cat <<EOF
</ul>
<p>Upgrade took $(hours $UPGRADE_TIME)</p>
<p>Running benches took $(hours $BENCH_TIME)</p>
<p>Total time $(hours $((UPGRADE_TIME + BENCH_TIME)))</p>
</body>
</html>
EOF
) >$LOGDIR/index.html

cd $BASELOGDIR && echo "<html><head><title>bench index</title></head><body><ul>$(ls -d 201* latest | sed 's%\(.*\)%<li><a href="\1">\1</a></li>%')</ul></body></html>" >index.html

echo "Done"
