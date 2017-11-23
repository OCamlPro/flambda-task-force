#!/bin/bash

## NOTE: this is more for documentation than to be run as a script. You're
## advised to run the steps one by one.

export PATH=~/local/bin:$PATH

TEST_SWITCHES=(comparison flambda)
export OPAMSWITCH

export OPAMJOBS=6

ulimit -s unlimited

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
opam pin add --switch comparison ocaml 'git://github.com/chambart/ocaml-1#comparison_branch' --yes --no-action


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
    # type_conv 112.01.02 (normally available soon on opam-repository official)
    opam pin add type_conv git://github.com/janestreet/type_conv.git#112.01.02 \
         --no-action --yes
done
# get the right version of camlp4 for flambda
opam pin add camlp4 git://github.com/ocaml/camlp4#2552bba33463ac1c4f00d5b74fe767d5c1873f89 --switch flambda

# Install all depexts
###

for OPAMSWITCH in "${TEST_SWITCHES[@]}"; do
    opam pin add depext --dev --yes
    OPAMYES=1 opam depext --no-sources $(opam list -sa)
    opam remove -a depext --yes
    opam unpin depext --yes
done
# We ignore packages with 'source scripts', it's too unreliable
