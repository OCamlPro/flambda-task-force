### Scripts

## make

This will generate a main.native binary. This script will setup an opam environment with 2 compilers:
  - the comparison branch based on trunk
  - the main flambda development branch

Once these two compilers are installed, it runs around 900 different sets of options on test packages. The test packages are alt-ergo, js_of_ocaml, mehnir and coq.
It mesures compilation time, binary size and run time on a small example.
This will generate result files in the results directory.

## make filter

This will generate a filter.native binary. This script will filter and sort the results found in the given directory and generates a sorted_results file.
The sorted_results file contains the results for the configuration that generates a binary which is at most 10% bigger than the comparison one.

## make table

This will generate a table.native binary. This script will generate a table.html file containing all the results found in the results directory.