#!/bin/bash -ue

## NOTE: this is more for documentation than to be run as a script. You're
## advised to run the steps one by one.

export PATH=~/local/bin:$PATH

TEST_SWITCHES=(comparison flambda)
export OPAMSWITCH

export OPAMJOBS=6

#################
# SETUP
#################


# Bootstrap trunk opam and install couverture script
###

if [ "$(opam --version)" != "1.3.0~dev" ]; then
    if command -v opam; then
        opam init
    else
        wget -O - https://raw.github.com/ocaml/opam/master/shell/opam_installer.sh | sh -s ~/local/bin
    fi

    eval $(opam config env)
    opam install ocamlgraph cmdliner dose.3.3 cudf re ocamlfind jsonm
    git clone git://github.com/ocaml/opam
    (
        cd opam
        ./configure --prefix ~/local
        make
        make install libinstall
        make -C admin-scripts couverture
        cp admin-scripts/couverture ~/local/bin
    )
fi

# Setup the repos
###

opam repo add --priority 10 benches git://github.com/OCamlPro/opam-bench-repo
opam repo add --priority 20 base http://flambda.ocamlpro.com/opam-flambda-repository
opam repo add --priority 30 overlay git://github.com/OCamlPro/opam-flambda-repository-overlay
opam repo remove default
opam update


# Install the switches
###

for SWITCH in "${TEST_SWITCHES[@]}"; do
  opam switch install --no-switch $SWITCH --alias-of 4.03.0+$SWITCH
done

# Pin the flambda compiler so that it can be later upgraded
opam pin add --switch flambda ocaml 'git://github.com/chambart/ocaml-1#flambda_trunk' --yes --no-action


# Package fixes
###

# These packages are unavailable upstream, pin them to unavailable so that opam
# doesn't try (and fail) to get them.
unavailable_upstream=(ago.0.3 ascii85.0.3 combine.0.55 frama-c-base.20150201 lipsum.0.2 omake-mode.1.1.1 p3.0.0.6 patoline.0.1 quest.0.1 riakc_ppx.3.1.1 sundialsml.2.5.0p2 unison.2.40.102 vrt.0.1.0 why3-base.0.86 ibx.0.7.4 ocaml-zmq.0)

mkdir dummy
cat >dummy/opam <<EOF
opam-version: "1.2"
available: false
EOF

for OPAMSWITCH in "${TEST_SWITCHES[@]}"; do
    for p in "${unavailable_upstream[@]}"; do
        opam pin add --yes $p dummy
    done
    # llvm 3.6 is unavailable on current debian
    opam pin add llvm 3.5 --no-action --yes
    # dev version working on 4.3 (earlier versions broken)
    opam pin add lwt 2.4.8 --no-action --yes
    # # camlp4 crashes on bin_prot 111
    # opam pin add bin_prot.112
done

# Install all depexts
###

for OPAMSWITCH in "${TEST_SWITCHES[@]}"; do
    OPAMYES=1 opam depext --no-sources $(opam list -sa)
done
# We ignore packages with 'source scripts', it's too unreliable


#################
# RUN
#################

# Make sure we have the latest flambda compiler
###

opam upgrade --switch flambda ocaml --yes

# Backup clean switches
###

rm -rf switch-backups
mkdir -p switch-backups
for OPAMSWITCH in "${TEST_SWITCHES[@]}"; do
    cp -a $(opam config var prefix) switch-backups
done

# Run the install tests
###

LOGDIR=$(date +%Y-%m-%d-%H%M)-$(opam show ocaml --switch flambda --field pinned | sed 's/.*(\(.*\))/\1/')
mkdir $LOGDIR

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
        (cd $(opam config var prefix) && tree -sfin --noreport bin && tree -sfin --noreport lib -P '*.cm*|*.so|*.a') >$LOGDIR/files-$OPAMSWITCH-$i.list
        i=$((i+1))
        # Restore backed up switch
        switchdir=$(opam config var prefix)
        rm -rf $switchdir
        cp -a switch-backups/$OPAMSWITCH $switchdir
    done
done

echo "Done. All logs gathered into $LOGDIR. You may cd there and run:"
echo "    logs2html >index.html"
