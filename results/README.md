### Results

The compiler arguments evaluation results lies in the result/software directory. The file name describes the compiler options.

The file contains:
  - a list of file with the compile time
  - the overall compilation time
  - the size of the generated binary
  - its stripped size
  - a rought (and noisy) runtime of the binary on some example

The results on trunk are in the files named "4.03.0+comparison+gen_software_.result"

A sorted selection of compiler options that seems interesting are in results/software/sorted_results file. This file contains the
normalized results against the results on trunk.

The version on which the test where run is given by the commit_number file

A comprehensive table of the results can be found in results/table.html