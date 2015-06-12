module StringMap = Map.Make(String)

type time_stats = {
  clambda: float;
  flambda: float;
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
}

let get_bin_size root_dir compiler_name packet =
  let compiler_path = Filename.concat root_dir compiler_name in
  let bin_path = Filename.concat compiler_path "bin" in
  let path = Filename.concat bin_path packet in
  try 
    { file = path; size = (Unix.stat path).Unix.st_size }
  with _ -> {file = path; size = -1}

let dump_stats oc indent stats =
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "clambda" stats.clambda;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "flambda" stats.flambda;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "generate" stats.generate;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "cmm" stats.cmm;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "assemble" stats.assemble;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "parsing" stats.parsing;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "typing" stats.typing;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "transl" stats.transl;
  Printf.fprintf oc "%s%s: %.2f\n%!" indent "compile_phrases" stats.compile_phrases
    
let dump_results oc map size_st =
  StringMap.iter (fun file stats ->
      Printf.fprintf oc "{ %S ->\n%!" file;
      dump_stats oc "  " stats;
      Printf.fprintf oc "}\n%!"
    ) map;
  Printf.fprintf oc "size: %s = %i" size_st.file size_st.size

let create_empty_time_stats () = 
  { clambda = 0.; generate = 0.; cmm = 0.; assemble = 0.; flambda = 0.; 
    parsing = 0.; typing = 0.; transl = 0.; compile_phrases = 0. }
  
let update_time_stats stats field value = match field with
  | "clambda" -> { stats with clambda = value }
  | "flambda" -> { stats with flambda = value }
  | "generate" -> { stats with generate = value }
  | "cmm" -> { stats with cmm = value }
  | "assemble" -> { stats with assemble = value }
  | "parsing" -> { stats with parsing = value }
  | "typing" -> { stats with typing = value }
  | "transl" -> { stats with transl = value }
  | "compile_phrases" -> { stats with compile_phrases = value }
  | _ -> failwith ("wrong scanf field : " ^ field)

let parse_time_info output =
  List.fold_left (fun acc s ->
      try
        Scanf.sscanf s  "- %[a-zA-Z_](%[a-zA-Z0-9./_]): %fs" 
          (fun field file value -> 
             if StringMap.mem file acc
             then 
               let stats = StringMap.find file acc in
               StringMap.add file (update_time_stats stats field value) acc
             else
               let empty = create_empty_time_stats () in
               StringMap.add file (update_time_stats empty field value) acc)
      with Scanf.Scan_failure _ -> acc
    ) StringMap.empty (Str.split (Str.regexp_string "\n") output)

let get_time_informations root_dir compiler_name packet conf_str output =
  let res = 
    (match output with 
     | None -> StringMap.empty
     | Some s ->
       let regexp_str = Printf.sprintf "RUN [%s: make]" packet in
       let regexp = Str.regexp_string regexp_str in
       let list = Str.split regexp s in
       if (List.length list) < 2
       then 
         (Printf.eprintf "Can't find %S in output\n%!" regexp_str; StringMap.empty)
       else 
         let output = (List.nth list 1) in
         parse_time_info output
    ) in  
  let file_res_name = Printf.sprintf "%s_%s_%s.result" compiler_name packet conf_str in
  let bin_size = get_bin_size root_dir compiler_name packet in
  let oc = open_out file_res_name in
  Printf.printf "Dumping results in %S...\n%!" file_res_name;
  dump_results oc res bin_size
