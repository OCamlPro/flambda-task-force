#!/bin/bash

shopt -s nullglob

export PATH=~/local/bin:$PATH

unset OPAMROOT OPAMSWITCH OCAMLPARAM OCAMLRUNPARAM

STARTTIME=$(date +%s)

DATE=$(date +%Y-%m-%d-%H%M)

BASELOGDIR=~/logs/operf

LOGDIR=$BASELOGDIR/$DATE

OPERFDIR=~/.cache/operf/macro/

LOCK=$BASELOGDIR/lock

if [ -e $LOCK ]; then
    RUNNING_PID=$(cat $LOCK)
    if ps -p $RUNNING_PID >/dev/null; then
        echo "Another run-bench.sh is running (pid $RUNNING_PID). Aborting." >&2
        exit 1
    else
        echo "Removing stale lock file $LOCK." >&2
        rm $LOCK
    fi
fi

trap "rm $LOCK" EXIT

echo $$ >$LOCK

publish() {
    local FILES=$(cd $LOGDIR && for x in $*; do echo $DATE/$x; done)
    tar -C $BASELOGDIR -u $FILES -f $BASELOGDIR/results.tar
    gzip -c --rsyncable $BASELOGDIR/results.tar >$BASELOGDIR/results.tar.gz
    rsync $BASELOGDIR/results.tar.gz flambda-mirror:
    ssh flambda-mirror  "tar -C /var/www/flambda.ocamlpro.com/bench/ --keep-newer-files -xzf ~/results.tar.gz 2>/dev/null"
}

unpublish() {
    mv $BASELOGDIR/$DATE $BASELOGDIR/broken/
    tar --delete $DATE -f $BASELOGDIR/results.tar
    ssh flambda-mirror  "rm -rf /var/www/flambda.ocamlpro.com/bench/$DATE"
}

trap "unpublish; exit 2" INT

mkdir -p $LOGDIR

echo "Output and log written into $LOGDIR" >&2

exec >$LOGDIR/log 2>&1

echo "=== SETTING UP BENCH SWITCHES AT $DATE ==="

## Initial setup:
#
# opam 2.0~alpha6 an "operf" switch with operf-macro installed (currently
# working: ocaml 4.02.3, operf pinned to git://github.com/ocamlpro/ocaml-perf,
# operf-macro pinned to git://github.com/OCamlPro/operf-macro#opam2)
#
# opam repo add benches git+https://github.com/AltGr/ocamlbench-repo --dont-select

OPERF_SWITCH=operf

opam update benches

COMPILERS=($(opam list --no-switch --has-flag compiler --repo=benches --all-versions --short))
SWITCHES=()
INSTALLED_BENCH_SWITCHES=($(opam switch list -s |grep '+bench$'))

for C in "${COMPILERS[@]}"; do
    SWITCH=${C#*.}+bench
    SWITCHES+=("$SWITCH")

    if [[ ! " ${INSTALLED_BENCH_SWITCHES[@]} " =~ " $SWITCH " ]]; then
        opam switch create "$SWITCH" --empty --no-switch --repositories benches,default
    fi

    opam pin add "${C%%.*}" "${C#*.}" --switch "$SWITCH" --yes --no-action
    opam switch set-base "${C%%.*}" --switch "$SWITCH" --yes
done

# Remove switches that are no longer needed
for SW in "${INSTALLED_BENCH_SWITCHES[@]}"; do
    if [[ ! " ${SWITCHES[@]} " =~ " $SW " ]]; then
        opam switch remove "$SW" --yes;
    fi;
done

echo "=== UPGRADING operf-macro at $DATE ==="

touch $LOGDIR/stamp
publish stamp

opam update --switch $OPERF_SWITCH

opam install --upgrade --yes operf-macro --switch $OPERF_SWITCH --json $LOGDIR/$OPERF_SWITCH.json

BENCHES=($(opam list --no-switch --required-by all-bench --short --column name))

for SWITCH in "${SWITCHES[@]}"; do opam update --dev --switch $SWITCH; done
for SWITCH in "${SWITCHES[@]}"; do
    echo "=== UPGRADING SWITCH $SWITCH =="
    opam upgrade "${BENCHES[@]}" --soft --yes --switch $SWITCH --json $LOGDIR/$SWITCH.json
done

LOGSWITCHES=("${SWITCHES[@]/#/$LOGDIR/}")
opamjson2html ${LOGSWITCHES[@]/%/.json*} >$LOGDIR/build.html

UPGRADE_TIME=$(($(date +%s) - STARTTIME))

echo -e "\n===== OPAM UPGRADE DONE in ${UPGRADE_TIME}s =====\n"


eval $(opam config env --switch $OPERF_SWITCH)

loadavg() {
  awk '{print 100*$1}' /proc/loadavg
}

if [ "x$1" != "x--nowait" ]; then

    # let the loadavg settle down...
    sleep 60

    while [ $(loadavg) -gt 60 ]; do
        if [ $(($(date +%s) - STARTTIME)) -gt $((3600 * 12)) ]; then
            echo "COULD NOT START FOR THE PAST 12 HOURS; ABORTING RUN" >&2
            unpublish
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

ocaml-params() {
    SWITCH=$1; shift
    [ $# -eq 0 ]
    opam config env --switch $SWITCH | sed -n "s/\(OCAMLPARAM='[^']*'\).*$/\1/p"
}

for SWITCH in "${SWITCHES[@]}"; do
    opam show ocaml-variants --switch $SWITCH --field source-hash >$LOGDIR/${SWITCH%+bench}.hash
    opam config env --switch $SWITCH | sed -n 's/\(OCAMLPARAM="[^"]*"\).*$/\1/p' >$LOGDIR/${SWITCH%+bench}.params
    opam pin --switch $SWITCH >$LOGDIR/${SWITCH%+bench}.pinned
done

publish log build.html "*.hash" "*.params" "*.pinned"

wall " -- STARTING BENCHES -- don't put load on the machine. Thanks"

BENCH_START_TIME=$(date +%s)

echo
echo "=== BENCH START ==="

for SWITCH in "${SWITCHES[@]}"; do
    nice -n -5 opam config exec --switch $OPERF_SWITCH -- timeout 90m operf-macro run --switch $SWITCH
done

opam config exec --switch $OPERF_SWITCH -- operf-macro summarize -b csv >$LOGDIR/summary.csv
cp -r $OPERFDIR/* $LOGDIR

BENCH_TIME=$(($(date +%s) - BENCH_START_TIME))

hours() {
    printf "%02d:%02d:%02d" $(($1 / 3600)) $(($1 / 60 % 60)) $(($1 % 60))
}

cat > $LOGDIR/timings <<EOF
Upgrade: $(hours $UPGRADE_TIME)
Benches: $(hours $BENCH_TIME)
Total: $(hours $((UPGRADE_TIME + BENCH_TIME)))
EOF

publish log timings summary.csv "*/*.summary"

cd $BASELOGDIR && echo "<html><head><title>bench index</title></head><body><ul>$(ls -d 201* latest | sed 's%\(.*\)%<li><a href="\1">\1</a></li>%')</ul></body></html>" >index.html

echo "Done"
