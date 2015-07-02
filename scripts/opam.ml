let create_comp_file comp_dir comp_name comp_url comp_version =
  let comp_filename = comp_name ^ ".comp" in
  let comp_file = Filename.concat comp_dir comp_filename in
  if !Command.debug then Printf.printf "create_comp_file %s\n%!" comp_file;
  let oc = open_out comp_file in
  Printf.fprintf oc "opam-version: %S\n" "1.2";
  Printf.fprintf oc "version: %S\n" comp_version;
  Printf.fprintf oc "src: %S\n" comp_url;
  Printf.fprintf oc "build: [\n";
  Printf.fprintf oc
    "  [%S %S prefix %S]\n" "./configure" "-prefix" "-with-debug-runtime";
  Printf.fprintf oc "  [make %S]\n" "world";
  Printf.fprintf oc "  [make %S]\n" "world.opt";
  Printf.fprintf oc "  [make %S]\n" "install";
  Printf.fprintf oc "]\n";
  Printf.fprintf oc
    "packages: [ %S %S %S ]\n" "base-unix" "base-bigarray" "base-threads";
  Printf.fprintf oc
    "env: [[CAML_LD_LIBRARY_PATH = %S]]" "%{lib}%/stublibs";
  close_out oc

let create_comp_file_with_config comp_dir comp_name comp_url comp_version config =
  let comp_filename = comp_name ^ ".comp" in
  let comp_file = Filename.concat comp_dir comp_filename in
  if !Command.debug then Printf.printf "create_comp_file %s\n%!" comp_file;
  let oc = open_out comp_file in
  Printf.fprintf oc "opam-version: %S\n" "1.2";
  Printf.fprintf oc "version: %S\n" comp_version;
  Printf.fprintf oc "src: %S\n" comp_url;
  Printf.fprintf oc "build: [\n";
  Printf.fprintf oc
    "  [%S %S prefix %S]\n" "./configure" "-prefix" "-with-debug-runtime";
  Printf.fprintf oc "  [\"mkdir\" \"-p\" %S]\n" "%{lib}%/ocaml";
  Printf.fprintf oc
    "  [\"sh\" \"-c\" \"echo \\\"%s\\\" > %s\"]\n"
    (Configuration.to_string config) "%{lib}%/ocaml/compiler_configuration";
  Printf.fprintf oc "  [make %S]\n" "world";
  Printf.fprintf oc "  [make %S]\n" "world.opt";
  Printf.fprintf oc "  [make %S]\n" "install";
  Printf.fprintf oc "]\n";
  Printf.fprintf oc
    "packages: [ %S %S %S ]\n" "base-unix" "base-bigarray" "base-threads";
  Printf.fprintf oc
    "env: [[CAML_LD_LIBRARY_PATH = %S]]" "%{lib}%/stublibs";
  close_out oc

let create_descr_file comp_dir comp_name comp_descr =
  let descr_filename = comp_name ^ ".descr" in
  if !Command.debug then Printf.printf "create_descr_file %s\n%!" descr_filename;
  let descr_file = Filename.concat comp_dir descr_filename in
  let oc = open_out descr_file in
  Printf.fprintf oc "%s" comp_descr;
  close_out oc
  
let create_compiler_files comp_dir comp_name comp_url comp_descr comp_version =
  create_comp_file comp_dir comp_name comp_url comp_version;
  create_descr_file comp_dir comp_name comp_descr

let create_compiler_files_with_config comp_dir comp_name comp_url comp_descr comp_version config =
  create_comp_file_with_config comp_dir comp_name comp_url comp_version config;
  create_descr_file comp_dir comp_name comp_descr

let create_compiler_dir comp_name comp_version root_dir =
  if !Command.debug then Printf.printf "create_compiler_dir %s\n%!" comp_name;
  let compilers_dir = Filename.concat root_dir "compilers" in
  let version_dir = Filename.concat compilers_dir comp_version in
  let comp_dir = Filename.concat version_dir comp_name in
  Command.mk_dir comp_dir;
  comp_dir

let create_comp comp_name comp_url comp_descr comp_version root_dir =
  if !Command.debug then Printf.printf "create_comp %s in %s\n%!" comp_name root_dir;
  Printf.printf "Creating %s compiler files...\n%!" comp_name;
  let comp_dir = create_compiler_dir comp_name comp_version root_dir in
  create_compiler_files comp_dir comp_name comp_url comp_descr comp_version

let create_comp_with_config comp_name comp_url comp_descr comp_version root_dir config =
  if !Command.debug then Printf.printf "create_comp %s in %s\n%!" comp_name root_dir;
  Printf.printf "Creating %s compiler files...\n%!" comp_name;
  let comp_dir = create_compiler_dir comp_name comp_version root_dir in
  create_compiler_files_with_config comp_dir comp_name comp_url comp_descr comp_version config

let opam_add_repo_args prog root_dir name repo =
  [| prog; "repository"; "add"; name; repo; "--root"; root_dir |]

let opam_add_repo root_dir name repo =
  Printf.printf "Adding %s repo...\n%!" name;
  let prog = "opam" in
  ignore (Command.run_command prog (opam_add_repo_args prog root_dir name repo))

let opam_init_args dir prog repo =
  let opam_init_root = Printf.sprintf "--root=%s" dir in
  [| prog; "init"; "--no-setup";  opam_init_root; "--comp=" ^ Command.comparison_name; "flambda"; repo |]

let opam_initialization dir repo =
  Printf.printf "Initializing opam...\n%!";
  let prog = "opam" in
  ignore (Command.run_command prog (opam_init_args dir prog repo))

let opam_switch_args comp_name prog =
  [| prog; "switch"; comp_name; "-v" |]

let opam_switch_comp comp_name =
  let prog = "opam" in
  ignore (Command.run_command prog (opam_switch_args comp_name prog))

let opam_install_args packets prog =
  Array.append [| prog; "install"; "-y" |] (Array.of_list packets)

let opam_install_packets packets =
  let prog = "opam" in
  ignore (Command.run_command prog (opam_install_args packets prog))

let opam_time_install_args packet prog =
  [| prog; "install"; packet; "-y"; "-v"|]

let opam_time_install packet =
  let prog = "opam" in
  let args = opam_time_install_args packet prog in
  Command.run_command ~parse_stdout:true prog args

let opam_remove_args packets prog =
  Array.append [| prog; "remove"; "-y" |] (Array.of_list packets)

let opam_remove_packets packets =
  let prog = "opam" in
  ignore (Command.run_command prog (opam_remove_args packets prog)) 

let opam_remove_comp_args compiler_name prog =
  [| prog; "switch"; "remove"; compiler_name; "-y" |]

let opam_remove_compiler compiler_name comparison =
  opam_switch_comp comparison;
  let prog = "opam" in
  ignore (Command.run_command prog (opam_remove_comp_args compiler_name prog))

let opam_install_depext () =
  let prog = "opam" in
  Command.run_command prog [| prog; "install"; "depext" ; "-y" |]

let opam_depext_arg packets prog =
  Array.append [| prog; "depext"; "-l" |] (Array.of_list packets)

let opam_depext packets =
  let prog = "opam" in
  Command.run_command prog (opam_depext_arg packets prog)
  
let create_configuration root_dir compiler_name config =
  let compiler_path = Filename.concat root_dir compiler_name in
  let lib_path = Filename.concat compiler_path "lib" in
  let path = Filename.concat lib_path "ocaml" in
  let conf_file = Filename.concat path "compiler_configuration" in
  Configuration.dump_conf_file config conf_file

let create_empty_configuration_file root_dir compiler_name =
  let compiler_path = Filename.concat root_dir compiler_name in
  let lib_path = Filename.concat compiler_path "lib" in
  let path = Filename.concat lib_path "ocaml" in
  let conf_file = Filename.concat path "compiler_configuration" in
  Printf.printf "Creating %S...\n%!" conf_file;
  let oc = open_out conf_file in
  Printf.fprintf oc "*: timings=1";
  close_out oc

let timed_install root_dir res_dir compiler_name packet config_str =
  opam_remove_packets [packet];
  let success, output = opam_time_install packet in
  if success 
  then Measurements.get_time_informations
         root_dir res_dir compiler_name packet config_str output
  else Measurements.dump_error res_dir compiler_name packet config_str output

let timed_install_comparison root_dir res_dir compiler_name packet =
  create_empty_configuration_file root_dir compiler_name;
  timed_install root_dir res_dir compiler_name packet ""
    
let timed_install_config root_dir res_dir compiler_name packet config =
  let config_str = Configuration.conf_descr config in
  timed_install root_dir res_dir compiler_name packet config_str
