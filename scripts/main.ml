let create_comparison_compiler root_dir =
  Printf.printf "Creating comparison compiler...\n%!";
  let comparison_version = "4.03.0" in
  let comparison_name = comparison_version ^ "+comparison" in
  let comparison_url = 
    "https://github.com/chambart/ocaml-1/archive/comparison_branch.tar.gz" in
  let comparison_descr = "The comparison branch based on trunk" in
  Opam.create_comp comparison_name comparison_url comparison_descr comparison_version root_dir;
  comparison_name

let create_flambda_compiler root_dir =
  Printf.printf "Creating flambda compiler...\n%!";
  let flambda_version = "4.03.0" in
  let flambda_name = flambda_version ^ "+flambda" in
  let flambda_url = 
    "https://github.com/chambart/ocaml-1/archive/flambda_trunk.tar.gz" in
  let flambda_descr = "The main flambda developpement branch" in
  Opam.create_comp flambda_name flambda_url flambda_descr flambda_version root_dir;
  flambda_name

let no_install_flag = ref false

let usage = Printf.sprintf "Usage: %s root_dir [--no-install]\n%!" Sys.executable_name

let arglist = [("--no-install", Arg.Set no_install_flag, "no opam init and compilers creation")]

let () =
  Arg.parse
    arglist
    (fun root_dir -> 
       let packet = "alt-ergo" in
       if not !no_install_flag then 
         (Command.mk_dir root_dir;
          Opam.opam_initialization root_dir);
       Unix.putenv "OPAMROOT" root_dir;
       let comparison = 
         if not !no_install_flag 
         then create_comparison_compiler root_dir 
         else "4.03.0+comparison" in
       Opam.opam_switch_comp comparison;
       Opam.timed_install_comparison root_dir comparison packet;
       let flambda = 
         if not !no_install_flag 
         then create_flambda_compiler root_dir
         else "4.03.0+flambda" in
       Opam.opam_switch_comp flambda;
       Opam.timed_install_all root_dir flambda packet
    )
    usage
