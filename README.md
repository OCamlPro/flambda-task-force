
### Repositories:

* The main flambda developpement branch is https://github.com/chambart/ocaml-1/tree/flambda_trunk
* The fork point from the trunk is the tag `flambda_fork_point` https://github.com/chambart/ocaml-1/tree/flambda_fork_point
* The comparison branch based on trunk is https://github.com/chambart/ocaml-1/tree/comparison_branch

* The opam-repository snapshot we use for all "external" benchmark is https://github.com/OCamlPro/opam-flambda-repository
* For packages not compiling with trunk or flambda, we maintain patches in https://github.com/OCamlPro/opam-flambda-repository-overlay
* Upstreamed patches are cherry-picked into `opam-flambda-repository`

#### The `comparison_branch`

The `comparison_branch` contains:

* `-dtimings` option to print each pass duration:
```
../boot/ocamlrun ../ocamlopt -strict-sequence -w +33..39 -g -warn-error A -bin-annot -nostdlib -safe-string `./Compflags pervasives.cmx` -c -dtimings pervasives.ml
clambda(pervasives.ml): 0.004s
all: 0.092s
generate(pervasives.ml): 0.040s
cmm(pervasives.ml): 0.000s
assemble(pervasives.ml): 0.000s
parsing(pervasives.ml): 0.004s
typing(pervasives.ml): 0.044s
transl(pervasives.ml): 0.004s
compile_phrases(pervasives.ml): 0.028s
```
* `ocaml/lib/compiler_configuration` to set global and per file name configuration:
```
*: inline = 10
queue.ml: unroll = 1
```

### Code coverage

See: https://github.com/OCamlPro/flambda-task-force/issues/2
