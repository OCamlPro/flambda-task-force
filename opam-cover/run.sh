#!/bin/bash


# Config
###

export PATH=~/local/bin:$PATH

TEST_SWITCHES=(comparison flambda)

export OPAMJOBS=6
export OPAMBUILDTEST=0

cd ~/logs

switch-hash () {
  opam show ocaml --switch flambda --field pinned | sed 's/.*(\(.*\))/\1/'
}

DATE=$(date +%Y-%m-%d-%H%M)
LOGDIR_TMP=$DATE.tmp
LOGDIR=$LOGDIR_TMP
mkdir $LOGDIR

# Init
###

export OPAMSWITCH
STARTTIME=$(date +%s)

exec >$LOGDIR/log 2>&1

# Make sure we have the latest flambda compiler
###

OLD_GIT_HASH=$(switch-hash)
opam update
opam upgrade --switch flambda ocaml --yes
FLAMBDA_GIT_HASH=$(switch-hash)

LOGDIR=$DATE-$FLAMBDA_GIT_HASH
if [ "$OPAMBUILDTEST" -ne 0 ]; then LOGDIR=$LOGDIR+tests; fi
if [ "$OPAMJOBS" -ne 1 ]; then LOGDIR=$LOGDIR-x$OPAMJOBS; fi
mv $LOGDIR_TMP $LOGDIR

if [ "$OLD_GIT_HASH" = "$FLAMBDA_GIT_HASH" ]; then
    echo "Same git hash $FLAMBDA_GIT_HASH, skipping run" >$LOGDIR/log
    exit 0
fi

# Backup clean switches
###

rm -rf switch-backups
mkdir -p switch-backups
for OPAMSWITCH in "${TEST_SWITCHES[@]}"; do
    cp -a $(opam config var prefix) switch-backups
done

# Run the install tests
###

cat <<EOF >$LOGDIR/conf
TEST_SWITCHES=(${TEST_SWITCHES[*]})
OPAMJOBS=$OPAMJOBS
OPAMBUILDTEST=$OPAMBUILDTEST
EOF

# Compute coverage
for OPAMSWITCH in "${TEST_SWITCHES[@]}"; do
    couverture >$LOGDIR/couv-$OPAMSWITCH
done


for OPAMSWITCH in "${TEST_SWITCHES[@]}"; do
    readarray COUV <$LOGDIR/couv-$OPAMSWITCH
    i=1
    for step in "${COUV[@]}"; do
        echo
        echo
        echo "[41;30m======================= STEP $i on $OPAMSWITCH ===================[m"
        echo
        opam install --unset-root --yes --json=$LOGDIR/$OPAMSWITCH-$i.json $step
        opam list -s >$LOGDIR/installed-$OPAMSWITCH-$i.log
        (cd $(opam config var prefix) && tree -sfin --noreport bin && tree -sfin --noreport lib) \
            >$LOGDIR/files-$OPAMSWITCH-$i.list
        (cd $(opam config var prefix) &&
         for f in bin/*; do read -N 2 X <$f; if [ "$X" = "#!" ]; then echo $f; fi; done) \
            >$LOGDIR/byteexec-$OPAMSWITCH-$i.list
        i=$((i+1))
        # Restore backed up switch
        switchdir=$(opam config var prefix)
        rm -rf $switchdir
        cp -a switch-backups/$OPAMSWITCH $switchdir
    done
done

(cd $LOGDIR && logs2html >index.html)

rm -rf latest
mkdir latest
echo $FLAMBDA_GIT_HASH >latest/ref
echo '<!DOCTYPE html><html><head><title>Flambda latest logs redirect</title><meta http-equiv="refresh" content="0; url=../'"$LOGDIR"'/" /></head></html>' >latest/index.html

echo "Done. All logs in $PWD/$LOGDIR"
ENDTIME=$(date +%s)
echo "Ran in $(((ENDTIME - STARTTIME) / 60)) minutes"
