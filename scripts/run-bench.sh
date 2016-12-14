#!/bin/bash

shopt -s nullglob

export PATH=~/local/bin:$PATH

unset OPAMROOT OPAMSWITCH OCAMLPARAM OCAMLRUNPARAM

OPERF_SWITCH=operf

SWITCHES=($(opam switch list -s |grep '+bench$'))


## Initial setup:
#
# opam 2.0~alpha6
# the "operf" switch with operf-macro installed
# the following repositories configured by default:
#  1 benches git://github.com/OCamlPro/opam-bench-repo#opam2
#  2 default https://opam.ocaml.org/2.0~dev
#  3 overlay git://github.com/OCamlPro/opam-flambda-repository-overlay#opam2
#
# The switches to benches configured using the following function


setup-new-switch() {
    version="$1"; shift
    variant="$1"; shift
    target="$1"; shift
    ocamlparam="$1"; shift
    configflags="$*"; shift

    name="${version}${variant:++$variant}"
    configflags_escaped=${configflags:+ \"${configflags// /\" \"}\"}
    setenv_line=${ocamlparam:+setenv: [OCAMLPARAM = \"_,$ocamlparam\"]}

    opam switch create "$name+bench" --empty --no-switch
    COMPILERDEF=$(mktemp /tmp/compilerdef.XXXX)
    cat <<EOF >$COMPILERDEF
opam-version: "2.0"
name: "ocaml-variants"
version: "$name"
maintainer: "flambda@ocamlpro.com"
flags: "compiler"
build: [
  ["./configure" "-prefix" prefix "-with-debug-runtime"$configflags_escaped]
  [make "world"]
  [make "world.opt"]
]
install: [make "install"]
$setenv_line
EOF
    OPAMEDITOR="cp -f $COMPILERDEF" \
      opam pin add ocaml-variants.$name "$target" --switch "$name+bench" --edit --yes </dev/null
    rm -f $COMPILERDEF
    opam switch set-base ocaml-variants --switch "$name+bench"
}

# Create bench switches:
# setup-new-switch 4.03.1+dev   ""      "git://github.com/ocaml/ocaml#4.03"
# setup-new-switch 4.04.1+dev   ""      "git://github.com/ocaml/ocaml#4.04"
# setup-new-switch 4.05.0+trunk ""      "git://github.com/ocaml/ocaml#trunk"
# setup-new-switch 4.05.0+trunk flambda "git://github.com/ocaml/ocaml#trunk" ""   -flambda
# setup-new-switch 4.05.0+trunk opt     "git://github.com/ocaml/ocaml#trunk" O3=1 -flambda

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

echo "=== UPGRADING operf-macro at $DATE ==="

touch $LOGDIR/stamp
publish stamp

opam update --all

opam install --upgrade --yes operf-macro --switch $OPERF_SWITCH --json $LOGDIR/$OPERF_SWITCH.json

BENCHES="frama-c-bench jsonm-bench lexifi-g2pp-bench patdiff-bench sauvola-bench yojson-bench kb-bench nbcodec-bench almabench-bench bdd-bench coq-bench sequence-bench menhir-bench compcert-bench minilight-bench numerical-analysis-bench cpdf-bench async-echo-bench core-micro-bench async-rpc-bench chameneos-bench thread-bench valet-bench cohttp-bench core-sequence-bench js_of_ocaml-bench"
# disabled (takes forever): alt-ergo-bench


for SWITCH in "${SWITCHES[@]}"; do opam update --dev --switch $SWITCH; done
for SWITCH in "${SWITCHES[@]}"; do
    echo "=== UPGRADING SWITCH $SWITCH =="
    opam upgrade $BENCHES --soft --yes --switch $SWITCH --json $LOGDIR/$SWITCH.json
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
    opam config env --switch $SWITCH | sed -n 's/\(OCAMLPARAM="[^"]*"\).*$/\1/p'
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
