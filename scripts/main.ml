open Command

let no_install_flag = ref false

let no_comparison_flag = ref false

let no_config_flag = ref false

let with_dep_flag = ref false

let benchs_run_flag = ref false

let root_dir = ref ""

let usage = 
  Printf.sprintf 
    "Usage: %s root_dir [--no-install] [--no-comparison] [--no-config] [--with-dep-flag] [--benchs-run]\n%!"
    Sys.executable_name

let arglist = [("--no-install", Arg.Set no_install_flag, "no opam init and compilers creation");
               ("--no-comparison", Arg.Set no_comparison_flag, "don't bother with comparison switch");
               ("--no-config", Arg.Set no_config_flag, "only use -dtimings for flambda");
               ("--with-dep", Arg.Set with_dep_flag, "run opam install \"packet\" once before mesuring");
               ("--benchs-run", Arg.Set benchs_run_flag, "run benchmarks test")]

let benchs = 
  [ (* "almabench-bench"; *) (* "alt-ergo-bench"; *) (* "async-echo-bench"; *)
    (* "async-rpc-bench"; *) (* "async-smtp-bench"; *) "bdd-bench";
    (* "chameneos-bench"; "cohttp-bench"; "coq-bench"; "core-micro-bench"; *)
    (* "core-sequence-bench"; *) (* "core-tests-bench";  "frama-c-bench";*)
    (* "js_of_ocaml-bench"; *) (* "jsonm-bench"; *) "kb-bench";
    "lexifi-g2pp-bench"; (* "nbcodec-bench"; *) (* "patdiff-bench"; *)
    "sauvola-bench"; (* "sequence-bench"; *) (* "thread-bench"; "valet-bench"; *)
    (* "yojson-bench" *) ]


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

let mk_results_dir packet time_str commit_number prefix =
  let results_dir = prefix in
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
     Opam.timed_install_no_config root_dir res_dir comparison_name !with_dep_flag packet);
  if !no_config_flag
  then
    (Opam.opam_switch_comp flambda_name;
     if !with_dep_flag then Opam.opam_install_packets [packet]);
  let configuration_nbr = List.length Configuration.configurations in
  List.iteri (fun i config ->
    Printf.printf "Configuration number %i/%i\n%!" (i + 1) configuration_nbr;
    Printf.printf "\n==== config =====\n\n%s\n\n%!" (Configuration.to_string config);
    if not !no_config_flag then
      (let flambda = create_flambda_in_root root_dir config in
       Opam.opam_switch_comp flambda;
       if !with_dep_flag then Opam.opam_install_packets [packet];
       Opam.timed_install_config root_dir res_dir flambda !with_dep_flag packet config;
       Opam.opam_remove_compiler flambda comparison_name)
    else
     Opam.create_configuration root_dir flambda_name config;
     Opam.timed_install_config root_dir res_dir flambda_name !with_dep_flag packet config
  ) Configuration.configurations

let run_benchs_test root_dir time_str commit_number benchs =
  Opam.opam_switch_comp Command.comparison_name;
  List.iter (fun bench ->
    let res_dir = mk_results_dir bench time_str commit_number "benchs" in
    Opam.timed_install_bench_no_config 
      root_dir res_dir comparison_name !with_dep_flag bench;
  ) benchs;
  Measurements.get_run_time_bench root_dir comparison_name time_str "" benchs;
  Opam.opam_switch_comp Command.flambda_name;
  let configuration_nbr = List.length Configuration.configurations in
  List.iteri (fun i config ->
    Printf.printf "Configuration number %i/%i\n%!" (i + 1) configuration_nbr;
    Printf.printf "\n==== config =====\n\n%s\n\n%!" (Configuration.to_string config);
    List.iter (fun bench ->
      let res_dir = mk_results_dir bench time_str commit_number "benchs" in
      Opam.create_configuration root_dir flambda_name config;
      Opam.timed_install_bench_config 
        root_dir res_dir flambda_name !with_dep_flag bench config
    ) benchs;
    let config_str = Configuration.conf_descr config in
    Measurements.get_run_time_bench 
      root_dir flambda_name time_str config_str benchs
  ) Configuration.configurations

let () =
  Arg.parse
    arglist (fun s -> root_dir := s) usage;
  if !root_dir = "" then Printf.printf "%s\n" usage
  else 
    let packets = [ "yojson"; "menhir"; "alt-ergo"; 
                    "js_of_ocaml"; "menhir"; (* "coq.8.4.6~camlp4" *)  ] in
    let time_str = Command.time_str () in
    let commit_number = get_commit_number () in
    if not !no_install_flag then
      (let repo = create_repo () in
       Command.mk_dir !root_dir;
       Opam.opam_initialization !root_dir repo;
       Opam.opam_add_repo !root_dir "benches" benchs_repo_url 10;
       Opam.opam_add_repo !root_dir "base" base_repo_url 20;
       Opam.opam_add_repo !root_dir "overlay" overlay_repo_url 30);
    Unix.putenv "OPAMROOT" !root_dir;
    Unix.putenv "OPAMJOBS" "8";
    Opam.opam_pin_add "type_conv" "git://github.com/janestreet/type_conv.git#112.01.02";
    if !benchs_run_flag
    then run_benchs_test !root_dir time_str commit_number benchs
    else
      List.iter (fun packet ->
        let res_dir = mk_results_dir packet time_str commit_number "results" in
        run_packet_test !root_dir packet res_dir
      ) packets
