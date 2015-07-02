module StringMap = Map.Make(String)

type time_stats = {
  clambda: float;
  flambda_mid: float;
  flambda_back: float;
  generate: float;
  cmm: float;
  assemble: float;
  parsing: float;
  typing: float;
  transl: float;
  compile_phrases: float;
}

type file_info = {
  file_name: string;
  stats: time_stats;
}

type stats_size = {
  file: string;
  size: int;
  strip_size: int;
}

let total_compilation_time stats =
  stats.clambda +. stats.flambda_mid +. stats.flambda_back +. stats.generate +. stats.cmm +.
  stats.assemble +. stats.parsing +. stats.typing +. stats.transl +.
  stats.compile_phrases

let dump_stats oc indent stats =
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "clambda" stats.clambda;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "flambda-mid" stats.flambda_mid;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "flambda-back" stats.flambda_back;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "generate" stats.generate;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "cmm" stats.cmm;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "assemble" stats.assemble;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "parsing" stats.parsing;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "typing" stats.typing;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "transl" stats.transl;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "compile_phrases" stats.compile_phrases;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "compilation_total_time" (total_compilation_time stats);
  total_compilation_time stats
    
let dump_results oc map size_st run_time =
  let compile_time = StringMap.fold (fun file stats acc ->
      Printf.fprintf oc "{ %S ->\n%!" file;
      let comp_time = dump_stats oc "  " stats in
      Printf.fprintf oc "}\n%!";
      acc +. comp_time
    ) map 0. in
  Printf.fprintf oc "compile_time: %f\n%!" compile_time;
  Printf.fprintf oc "size: %s = %i\n%!" size_st.file size_st.size;
  Printf.fprintf oc "strip_size: %s = %i\n%!" size_st.file size_st.strip_size;
  Printf.fprintf oc "cycles: %i\n%!" run_time

let dump_error res_dir compiler_name packet conf_str output =
  let res = match output with | None -> "" | Some s -> s in
  let file_res_name = Printf.sprintf "%s_%s_%s.error" compiler_name packet conf_str in
  let file_res = Filename.concat res_dir file_res_name in
  let oc = open_out file_res in
  Printf.printf "Dumping error in %S...\n%!" file_res;
  Printf.fprintf oc "%s%!" res;
  close_out oc

let create_empty_time_stats () = 
  { clambda = 0.; generate = 0.; cmm = 0.; assemble = 0.; flambda_mid = 0.; 
    flambda_back = 0.; parsing = 0.; typing = 0.; transl = 0.; 
    compile_phrases = 0. }
  
let update_time_stats stats field value = match field with
  | "clambda" -> { stats with clambda = value }
  | "flambda-mid" -> { stats with flambda_mid = value }
  | "flambda-back" -> { stats with flambda_back = value }
  | "generate" -> { stats with generate = value }
  | "cmm" -> { stats with cmm = value }
  | "assemble" -> { stats with assemble = value }
  | "parsing" -> { stats with parsing = value }
  | "typing" -> { stats with typing = value }
  | "transl" -> { stats with transl = value }
  | "compile_phrases" -> { stats with compile_phrases = value }
  | _ -> failwith ("wrong scanf field : " ^ field)

let parse_cycles_info output =
 List.fold_left (fun acc s ->
      try
        Scanf.sscanf s  "cycles: %i" (fun value -> value)
      with Scanf.Scan_failure _ -> acc | End_of_file -> acc
    ) 0 (Str.split (Str.regexp_string "\n") output)

let get_test root_dir compiler_name packet = 
  let build_dir = Filename.dirname Sys.executable_name in
  let src_dir = Filename.concat build_dir ".." in
  let comp_path = Filename.concat root_dir compiler_name in
  let bin_path = Filename.concat comp_path "bin" in
  match packet with
    | "alt-ergo" ->  
      let file = "00020___why_bf6246_euler003-T-WP_parameter_smallest_divisor.why" in
      Filename.concat src_dir file
    | "menhir" -> let file = "fancy-parser.mly" in Filename.concat src_dir file
    | "js_of_ocaml" -> let file = "ocamlc" in Filename.concat bin_path file
    | "coq.8.4.6~camlp4" -> let file = "Int.v" in Filename.concat src_dir file
    | _ -> assert false
  
let get_bin_name packet = match packet with
  | "coq.8.4.6~camlp4" -> "coqc"
  | _ -> packet

let strip path =
  let strip_path = path ^ ".strip" in
  ignore (Command.run_command "strip" [| "strip"; "-o"; strip_path; path |]);
  try (Unix.stat strip_path).Unix.st_size
  with _ -> -1

let get_bin_size root_dir compiler_name packet =
  let compiler_path = Filename.concat root_dir compiler_name in
  let bin_path = Filename.concat compiler_path "bin" in
  let path = Filename.concat bin_path (get_bin_name packet) in
  let strip_size = strip path in
  try 
    { file = path; size = (Unix.stat path).Unix.st_size; strip_size }
  with _ -> {file = path; size = -1; strip_size }

let get_run_time root_dir compiler_name packet =
  let test_path = get_test root_dir compiler_name packet in
  let comp_path = Filename.concat root_dir compiler_name in
  let bin_path = Filename.concat comp_path "bin" in
  let packet_path = Filename.concat bin_path (get_bin_name packet) in
  let operf_path = "/home/michael/.opam/4.02.1/bin/operf" in
  let output = 
    Command.run_stderr_command ~parse_stdout:true
                        operf_path
                        [| operf_path; packet_path; test_path |] in
  match output with
  | Some output -> parse_cycles_info output
  | None -> assert false

let parse_time_info output =
  List.fold_left (fun acc s ->
      try
        Scanf.sscanf s  "%[- ]%[a-zA-Z_](%[a-zA-Z0-9./_]): %fs"
          (fun _ field file value ->
             if StringMap.mem file acc
             then 
               let stats = StringMap.find file acc in
               StringMap.add file (update_time_stats stats field value) acc
             else
               let empty = create_empty_time_stats () in
               StringMap.add file (update_time_stats empty field value) acc)
      with Scanf.Scan_failure _ -> acc | End_of_file -> acc
    ) StringMap.empty (Str.split (Str.regexp_string "\n") output)

let get_time_informations root_dir res_dir compiler_name packet conf_str output =
  let res = 
    (match output with 
     | None -> StringMap.empty
     | Some s ->
       let regexp_str = Printf.sprintf "Building %s" packet in
       let regexp = Str.regexp_string regexp_str in
       let list = Str.split regexp s in
       if (List.length list) < 2
       then
         (Printf.eprintf "%s" s;
          Printf.eprintf "Can't find %S in output\n%!" regexp_str;
          StringMap.empty)
       else 
         let output = (List.nth list 1) in
         parse_time_info output
	 ) in
  let file_res_name = Printf.sprintf "%s_%s_%s.result" compiler_name packet conf_str in
  let file_res = Filename.concat res_dir file_res_name in
  let bin_size = get_bin_size root_dir compiler_name packet in
  let run_time = get_run_time root_dir compiler_name packet in
  let oc = open_out file_res in
  Printf.printf "Dumping results in %S...\n%!" file_res;
  dump_results oc res bin_size run_time;
  close_out oc
