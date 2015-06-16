let create_comparison_compiler root_dir =
  Printf.printf "Creating comparison compiler...\n%!";
  let comparison_version = "4.03.0" in
  let comparison_name = comparison_version ^ "+comparison" in
  let comparison_url = 
    "https://github.com/chambart/ocaml-1/archive/comparison_branch.tar.gz" in
  let comparison_descr = "The comparison branch based on trunk" in
  Opam.create_comp comparison_name comparison_url comparison_descr comparison_version root_dir;
  comparison_name

let create_flambda_compiler root_dir config =
  Printf.printf "Creating flambda compiler...\n%!";
  let flambda_version = "4.03.0" in
  let flambda_name = flambda_version ^ "+flambda" in
  let flambda_url = 
    "https://github.com/chambart/ocaml-1/archive/flambda_trunk.tar.gz" in
  let flambda_descr = "The main flambda developpement branch" in
  Opam.create_comp_with_config flambda_name flambda_url flambda_descr flambda_version root_dir config;
  flambda_name

let no_install_flag = ref false

let no_comparison_flag = ref false

let root_dir = ref ""

let usage = 
  Printf.sprintf "Usage: %s root_dir [--no-install] [--no-comparison]\n%!" Sys.executable_name

let arglist = [("--no-install", Arg.Set no_install_flag, "no opam init and compilers creation");
               ("--no-comparison", Arg.Set no_comparison_flag, "don't bother with comparison switch")]

let () =
  Arg.parse
    arglist (fun s -> root_dir := s) usage;
  if !root_dir = "" then Printf.printf "%s\n" usage
  else
    let packet = "alt-ergo" in
    if not !no_install_flag then
      (Command.mk_dir !root_dir;Opam.opam_initialization !root_dir);
    Unix.putenv "OPAMROOT" !root_dir;
    let comparison =
      if not !no_install_flag && not !no_comparison_flag
      then create_comparison_compiler !root_dir
      else "4.03.0+comparison" in
    if not !no_comparison_flag
    then (Opam.opam_switch_comp comparison;
          Opam.timed_install_comparison !root_dir comparison packet);
    let configuration_nbr = List.length Configuration.configurations in
    List.iteri (fun i config ->
      Printf.printf "Configuration number %i/%i\n%!" (i + 1) configuration_nbr;
      let flambda = create_flambda_compiler !root_dir config in
      Opam.opam_switch_comp flambda;
      Opam.timed_install_config !root_dir flambda packet config;
      Opam.opam_remove_compiler flambda
    ) Configuration.configurations
