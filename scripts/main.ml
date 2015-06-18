open Command

let no_install_flag = ref false

let no_comparison_flag = ref false

let no_config_flag = ref false

let root_dir = ref ""

let usage = 
  Printf.sprintf "Usage: %s root_dir [--no-install] [--no-comparison] [--no-config]\n%!" Sys.executable_name

let arglist = [("--no-install", Arg.Set no_install_flag, "no opam init and compilers creation");
               ("--no-comparison", Arg.Set no_comparison_flag, "don't bother with comparison switch");
               ("--no-config", Arg.Set no_config_flag, "only use -dtimings for flambda");]

let create_compiler_in_repo repo name descr archive =
  Printf.printf "Creating %s compiler in repo...\n%!" name;
  Opam.create_comp name archive descr "4.03.0" repo

let create_flambda_in_root root_dir config =
  Printf.printf "Creating flambda compiler...\n%!";
  Opam.create_comp_with_config flambda_name flambda_url flambda_descr "4.03.0" root_dir config;
  flambda_name

let create_repo () =
  let flambda_repo = "flambda_repo" in
  let compilers_dir = Filename.concat flambda_repo "compilers" in
  let trunk_dir = Filename.concat compilers_dir "4.03.0" in
  Command.mk_dir flambda_repo;
  Command.mk_dir flambda_archives;
  Command.mk_dir compilers_dir;
  Command.mk_dir trunk_dir;
  ignore (Command.run_command "wget" [| "wget"; "-O"; comparison_local; comparison_url |]);
  ignore (Command.run_command "wget" [| "wget"; "-O"; flambda_local; flambda_url |]);
  create_compiler_in_repo flambda_repo comparison_name comparison_descr comparison_local;
  if !no_config_flag then
    create_compiler_in_repo flambda_repo flambda_name flambda_descr flambda_local;
  flambda_repo

let () =
  Arg.parse
    arglist (fun s -> root_dir := s) usage;
  if !root_dir = "" then Printf.printf "%s\n" usage
  else
    let packet = "alt-ergo" in
    if not !no_install_flag then
      (let repo = create_repo () in
       Command.mk_dir !root_dir;
       Opam.opam_initialization !root_dir repo;
       Opam.opam_add_repo !root_dir "base" base_repo_url;
       Opam.opam_add_repo !root_dir "overlay" overlay_repo_url);
    Unix.putenv "OPAMROOT" !root_dir;
    if not !no_comparison_flag
    then Opam.timed_install_comparison !root_dir comparison_name packet;
    if !no_config_flag then Opam.opam_switch_comp flambda_name;
    let configuration_nbr = List.length Configuration.configurations in
    List.iteri (fun i config ->
      Printf.printf "Configuration number %i/%i\n%!" (i + 1) configuration_nbr;
      if not !no_config_flag then
        (let flambda = create_flambda_in_root !root_dir config in
         Opam.opam_switch_comp flambda;
         Opam.timed_install_config !root_dir flambda packet config;
         Opam.opam_remove_compiler flambda comparison_name)
      else
       Opam.create_configuration !root_dir flambda_name config;
       Opam.timed_install_config !root_dir flambda_name packet config
    ) Configuration.configurations
