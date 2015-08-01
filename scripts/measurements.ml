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
  stats.generate +. stats.parsing +. stats.typing +. stats.transl

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
  
let dump_bench_results oc map size_st =
  let compile_time = StringMap.fold (fun file stats acc ->
      Printf.fprintf oc "{ %S ->\n%!" file;
      let comp_time = dump_stats oc "  " stats in
      Printf.fprintf oc "}\n%!";
      acc +. comp_time
    ) map 0. in
  Printf.fprintf oc "compile_time: %f\n%!" compile_time;
  Printf.fprintf oc "size: %s = %i\n%!" size_st.file size_st.size;
  Printf.fprintf oc "strip_size: %s = %i\n%!" size_st.file size_st.strip_size
  
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
  Printf.printf "====== output ===== \n\n%s\n===========\n" output;
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
      let tmp_file, fd = Command.make_tmp_file "alt-ergo" ".why" in
      Unix.close fd;
      let file = "00020___why_bf6246_euler003-T-WP_parameter_smallest_divisor.why" in
      let path = Filename.concat src_dir file in
      Command.copy_file path tmp_file;
      tmp_file
    | "menhir" -> 
      let tmp_file, fd = Command.make_tmp_file "menhir" ".mly" in
      Unix.close fd;
      let file = "fancy-parser.mly" in 
      let path = Filename.concat src_dir file in
      Command.copy_file path tmp_file;
      tmp_file
    | "js_of_ocaml" -> let file = "ocamlc" in Filename.concat bin_path file
    | "coq.8.4.6~camlp4" -> 
      let tmp_file, fd = Command.make_tmp_file "Coq" ".v" in
      Unix.close fd;
      let file = "Int.v" in 
      let path = Filename.concat src_dir file in
      Command.copy_file path tmp_file;
      tmp_file
    | "yojson" ->
      let tmp_file, fd = Command.make_tmp_file "yojson" ".json" in
      Unix.close fd;
      let file = "sample.json" in 
      let path = Filename.concat src_dir file in
      Command.copy_file path tmp_file;
      tmp_file
    | _ -> assert false
  
let get_bin_name packet = match packet with
  | "coq.8.4.6~camlp4" -> "coqc"
  | "yojson" -> "ydump"
  | "alt-ergo-bench" -> "alt-ergo"
  | "almabench-bench" -> "almabench"
  | "core-sequence-bench" -> "sequence-bench"
  | "js_of_ocaml-bench" -> "js_of_ocaml"
  | "jsonm-bench" -> "jsonm"
  | "lexifi-g2pp-bench" -> "lexifi-g2pp"
  | "nbcodec-bench" -> "setrip"
  | "sauvola-bench" -> "sauvola-contrast"
  | "yojson-bench" -> "ydump"
  | _ -> packet

let get_benchs_list bench = match bench with
  | "alt-ergo-bench" ->
    [ "alt-ergo-00020___why_bf6246_euler003-T-WP_parameter_smallest_divisor";
      "alt-ergo-00076___why_f2468a_Site_central_imp-T-carte_autorisee_3";
      "alt-ergo-00115___why_b6d80d_relabel-T-WP_parameter_relabel";
      "alt-ergo-00145___why_0a8ac0_p9_15-T-OBF__ggjj_2";
      "alt-ergo-00195___fib__package-T-WP_parameter_def";
      "alt-ergo-00222___fib__package-T-WP_parameter_def";
      "alt-ergo-00224___why_c6049d_p9_17-T-OBF__yyll_1";
      "alt-ergo-00329___why_265778_p4_25_part2-T-bbvv_351";
      "alt-ergo-00893___why_b3d830_euler001-T-div2_sub";
      "alt-ergo-01012___p__package-T-WP_parameter_def";
      "alt-ergo-01192___why_98479f_p4_3_part1-T-ccgg_2055";
      "alt-ergo-01201___flight_manager__package-T-WP_parameter_def";
      "alt-ergo-02182___why_3f7a7d_inverse_in_place-T-WP_parameter_inverse_in_place";
      "alt-ergo-02362___why_be93d3_p4_3_part3-T-ccgg_1759";
      "alt-ergo-02802___step_function_test__package-T-WP_parameter_def";
      "alt-ergo-04124___why_e36d6b_int-T-induction_step";
      "alt-ergo-04298___why_7ae35b_p4_3_part4-T-ccgg_1618";
      "alt-ergo-08033___why_bebe52_p4_3_part11-T-ccgg_219";
      "alt-ergo-add_times_nsec_sum_higher_than_1s_post_3_Alt-Ergo";
      "alt-ergo-Automaton_i_part2-B_translation-advance_automaton_25";
      "alt-ergo-fill_assert_39_Alt-Ergo" ]
  | "almabench-bench" -> [ "almabench" ]
  | "bdd-bench" -> [ "bdd" ]
  | "core-sequence-bench" -> [ "core-sequence"; "core-sequence-cps" ]
  | "js_of_ocaml-bench" -> [ "js_of_ocaml" ]
  | "jsonm-bench" -> [ "jsontrip-actionLabel"; "jsontrip-sample" ]
  | "kb-bench" -> [ "kb"; "kb-no-exc" ]
  | "lexifi-g2pp-bench" -> [ "g2pp" ]
  | "nbcodec-bench" -> [ "setrip"; "setrip-smallbuf" ]
  | "sauvola-bench" -> [ "sauvola-contrast" ]
  | "sequence-bench" -> [ "sequence"; "sequence-cps" ]
  | "yojson-bench" -> [ "ydump-actionLabel"; "ydump-sample" ]
  | _ -> (Printf.printf "%s\n%!" bench; assert false)

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

let get_run_time_packet root_dir compiler_name packet =
  let test_path = get_test root_dir compiler_name packet in
  let comp_path = Filename.concat root_dir compiler_name in
  let bin_path = Filename.concat comp_path "bin" in
  let packet_path = Filename.concat bin_path (get_bin_name packet) in
  let operf_path = "/home/michael/.opam/4.02.1/bin/operf" in
  let output = 
    Command.run_stderr_command ~parse_stdout:true
                        operf_path
                        [| operf_path; packet_path; test_path |] in
  if packet <> "js_of_ocaml" then Command.remove test_path;
  match output with
  | Some output -> parse_cycles_info output
  | None -> assert false

let get_run_time_bench root_dir compiler_name time_str conf_str benchs =
  let opamroot = Printf.sprintf "--opamroot=/home/michael/%s" root_dir in
  let operf_path = "/home/michael/.opam/4.02.1/bin/operf-macro" in
  ignore (
    Command.run_command 
      ~parse_stdout:true
      operf_path 
      [| operf_path; "run"; opamroot; "--fixed"; "-f" |]);
  List.iter (fun bench -> 
    let files = get_benchs_list bench in
    List.iter (fun file ->
      let res_name = compiler_name ^ ".result" in
      let path_out = Printf.sprintf "/home/michael/.cache/operf/macro/%s/%s" file res_name in
      let in_file = 
        Printf.sprintf "%s_%s_%s.operf" compiler_name file conf_str in
      let benchs_dir = Filename.concat "/home/michael/benchs" bench in
      let bench_dir = Filename.concat benchs_dir time_str in
      let path_in = Filename.concat bench_dir in_file in
      Command.copy_file path_out path_in
    ) files
  ) benchs

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
  let run_time = get_run_time_packet root_dir compiler_name packet in
  let oc = open_out file_res in
  Printf.printf "Dumping results in %S...\n%!" file_res;
  dump_results oc res bin_size run_time;
  close_out oc

let get_time_informations_bench root_dir res_dir compiler_name bench conf_str output =
  let res = 
    (match output with 
     | None -> StringMap.empty
     | Some s -> parse_time_info s) in
  let file_res_name = Printf.sprintf "%s_%s_%s.result" compiler_name bench conf_str in
  let file_res = Filename.concat res_dir file_res_name in
  let bin_size = get_bin_size root_dir compiler_name bench in
  let oc = open_out file_res in
  Printf.printf "Dumping results in %S...\n%!" file_res;
  dump_bench_results oc res bin_size;
  close_out oc
