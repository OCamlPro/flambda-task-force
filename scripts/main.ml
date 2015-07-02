open Command

let no_install_flag = ref false

let no_comparison_flag = ref false

let no_config_flag = ref false

let with_dep_flag = ref false

let root_dir = ref ""

let usage = 
  Printf.sprintf "Usage: %s root_dir [--no-install] [--no-comparison] [--no-config]\n%!" Sys.executable_name

let arglist = [("--no-install", Arg.Set no_install_flag, "no opam init and compilers creation");
               ("--no-comparison", Arg.Set no_comparison_flag, "don't bother with comparison switch");
               ("--no-config", Arg.Set no_config_flag, "only use -dtimings for flambda");
               ("--with-dep", Arg.Set with_dep_flag, "run opam install \"packet\" once before mesuring")]

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

let get_commit_number () =
  let url = "https://github.com/chambart/ocaml-1.git" in
  let success, output = Command.run_command ~parse_stdout:true 
   "git" [| "git"; "ls-remote"; url; "flambda_trunk" |] in
  match output with
  | Some s when s <> "" -> 
    if success 
    then 
      let commit_number = List.hd (Str.split (Str.regexp_string "\t") s) in
      Printf.printf "Commit number = %s\n%!" commit_number;
      commit_number
    else (Printf.eprintf "failed to retrieve commit_number\n%!"; assert false)
  | _ -> (Printf.eprintf "failed to retrieve commit_number\n%!"; assert false)

let time_str () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%i-%i-%i_%i-%i" 
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday tm.Unix.tm_hour tm.Unix.tm_min

let mk_results_dir packet time_str commit_number =
  let results_dir = "results" in
  let packet_dir = Filename.concat results_dir packet in
  let time_dir = Filename.concat packet_dir time_str in
  Printf.printf "Creating %s...\n%!" time_dir;
  if Sys.file_exists results_dir
  then 
    if Sys.file_exists packet_dir
    then 
      if Sys.file_exists time_dir
      then ()
      else Unix.mkdir time_dir 0o777
    else 
      (Unix.mkdir packet_dir 0o777;
       Unix.mkdir time_dir 0o777)
  else 
    (Unix.mkdir results_dir 0o777;
    Unix.mkdir packet_dir 0o777;
    Unix.mkdir time_dir 0o777);
  let commit_file = Filename.concat time_dir "commit_number" in
  Printf.printf "Creating %s...\n%!" commit_file;
  let oc = open_out commit_file in
   Printf.fprintf oc "%s%!" commit_number;
  close_out oc;
  time_dir

let run_packet_test root_dir packet res_dir =
  if not !no_comparison_flag
  then
    (Opam.opam_switch_comp Command.comparison_name;
     if !with_dep_flag then Opam.opam_install_packets [packet];
     Opam.timed_install_comparison !root_dir res_dir comparison_name packet);
  if !no_config_flag
  then
    (Opam.opam_switch_comp flambda_name;
     if !with_dep_flag then Opam.opam_install_packets [packet]);
  let configuration_nbr = List.length Configuration.configurations in
  List.iteri (fun i config ->
    Printf.printf "Configuration number %i/%i\n%!" (i + 1) configuration_nbr;
    Printf.printf "\n==== config =====\n\n%s\n\n%!" (Configuration.to_string config);
    if not !no_config_flag then
      (let flambda = create_flambda_in_root !root_dir config in
       Opam.opam_switch_comp flambda;
       if !with_dep_flag then Opam.opam_install_packets [packet];
       Opam.timed_install_config !root_dir res_dir flambda packet config;
       Opam.opam_remove_compiler flambda comparison_name)
    else
     Opam.create_configuration !root_dir flambda_name config;
     Opam.timed_install_config !root_dir res_dir flambda_name packet config
  ) Configuration.configurations

let () =
  Arg.parse
    arglist (fun s -> root_dir := s) usage;
  if !root_dir = "" then Printf.printf "%s\n" usage
  else
    let packets = [ (* "coq.8.4.6~camlp4"; "alt-ergo"; "js_of_ocaml";*) "menhir" ] in
    let time_str = time_str () in
    let commit_number = get_commit_number () in
    if not !no_install_flag then
      (let repo = create_repo () in
       Command.mk_dir !root_dir;
       Opam.opam_initialization !root_dir repo;
       Opam.opam_add_repo !root_dir "base" base_repo_url;
       Opam.opam_add_repo !root_dir "overlay" overlay_repo_url);
    Unix.putenv "OPAMROOT" !root_dir;
    Unix.putenv "OPAMJOBS" "8";
    List.iter (fun packet ->
      let res_dir = mk_results_dir packet time_str commit_number in
      run_packet_test root_dir packet res_dir
    ) packets
