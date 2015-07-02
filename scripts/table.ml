open Configuration

module StringMap = Map.Make(String)

module StringSet = Set.Make(String)

type result = {
  compilation_time: float;
  size: float;
  strip_size: float;
  cycles: float;
}

type results = {
  commit_number: string;
  res: result StringMap.t;
  comparison_res: result;
}

(* type commit_result = { *)
(*   commit_number: string; *)
(*   date: string; *)
(*   comparison_res: result; *)
(*   res: result; *)
(* } *)

(* type line = { *)
(*   config: Configuration.configuration; *)
(*   commit_res: commit_result; *)
(* } *)

(* type table = { *)
(*   packet: string; *)
(*   lines: line list; *)
(* } *)

let empty_result () =
  { compilation_time = 0.; size = 0.; strip_size = 0.; cycles = 0.; }

let dumb_results () =
  { commit_number = ""; res = StringMap.empty; comparison_res = empty_result() }

let parse_comparison_file file =
  let content = Command.input_all_file file in
  let res = empty_result () in
  let list = List.rev (Str.split (Str.regexp_string "\n") content) in
  let compile_time = List.nth list 3 in
  let size = List.nth list 2 in
  let strip_size = List.nth list 1 in
  let cycles = List.hd list in
  try
    let res = Scanf.sscanf compile_time "compile_time: %f" 
                (fun value -> { res with compilation_time = value }) in
    let res = Scanf.sscanf size "size: %[a-zA-Z0-9/+-._] = %i"
                (fun _ value -> { res with size = float value }) in
    let res = Scanf.sscanf strip_size "strip_size: %[a-zA-Z0-9/+-._] = %i"
                (fun _ value -> { res with strip_size = float value }) in
    let res = Scanf.sscanf cycles "cycles: %i"
     (fun value -> { res with cycles = float value }) in res
  with Scanf.Scan_failure _ | End_of_file -> res

let parse_result_file file =
  let content = Command.input_all_file file in
  let res = empty_result () in
  let list = List.rev (Str.split (Str.regexp_string "\n") content) in
  let compile_time = List.nth list 3 in
  let size = List.nth list 2 in
  let strip_size = List.nth list 1 in
  let cycles = List.hd list in
  try
    let res = Scanf.sscanf compile_time "compile_time: %f" 
                (fun value -> { res with compilation_time = value }) in
    let res = Scanf.sscanf size "size: %[a-zA-Z0-9/+-._] = %i"
                (fun _ value -> { res with size = float value }) in
    let res = Scanf.sscanf strip_size "strip_size: %[a-zA-Z0-9/+-._] = %i"
                (fun _ value -> { res with strip_size = float value }) in
    let res = Scanf.sscanf cycles "cycles: %i"
     (fun value -> { res with cycles = float value }) in res
  with Scanf.Scan_failure _ | End_of_file -> res

let config_from_filename filename =
  let config_part = List.nth (Str.split (Str.regexp_string "_inline-") filename) 1 in
  try 
    Scanf.sscanf config_part
      "%[0-9]_rounds-%[0-9]_unroll-%[0-9]_call-cost-%[0-9]_alloc-cost-%[0-9]_prim-cost-%[0-9]_branch-cost-%[0-9]_branch-factor-%[0-9.]_nofunctorheuristic-%B.result"
    (fun inline rounds unroll call_cost alloc_cost prim_cost branch_cost branch_factor nofunct -> 
      { inline = int_of_string inline; 
        rounds = int_of_string rounds; 
        unroll = int_of_string unroll; 
        inline_call_cost = int_of_string call_cost; 
        inline_alloc_cost = int_of_string alloc_cost; 
        inline_prim_cost = int_of_string prim_cost;
        inline_branch_cost = int_of_string branch_cost; 
        branch_inline_factor = float_of_string branch_factor;
        no_functor_heuristic = nofunct })
  with Scanf.Scan_failure _ -> 
    Scanf.sscanf config_part
      "%[0-9]_rounds-%[0-9]_unroll-%[0-9]_call-cost-%[0-9]_alloc-cost-%[0-9]_prim-cost-%[0-9]_branch-cost-%[0-9]_nofunctorheuristic-%B.result"
    (fun inline rounds unroll call_cost alloc_cost prim_cost branch_cost nofunct -> 
      { inline = int_of_string inline; 
        rounds = int_of_string rounds; 
        unroll = int_of_string unroll; 
        inline_call_cost = int_of_string call_cost; 
        inline_alloc_cost = int_of_string alloc_cost; 
        inline_prim_cost = int_of_string prim_cost;
        inline_branch_cost = int_of_string branch_cost; 
        branch_inline_factor = min_float;
        no_functor_heuristic = nofunct })

let read_commit_file path =
  Printf.printf "reading commit_number in %s\n" path;
  Command.input_all_file path

let is_comparison_file packet file =
  let comparison_file =
    Printf.sprintf "4.03.0+comparison+gen_%s_.result" packet in
  file = comparison_file

let is_result_file packet file =
  if Filename.check_suffix file ".result" &&
    not (is_comparison_file packet file)
  then true
  else false

let read_results_date packet path =
  Printf.printf "reading date results in %s\n" path;
  if Sys.file_exists path
  then
    let commit_file = Filename.concat path "commit_number" in
    let commit_number = read_commit_file commit_file in
    Printf.printf "commit_number : %s\n%!" commit_number;
    let comparison_file = Printf.sprintf "4.03.0+comparison+gen_%s_.result" packet in
    let comparison_path = Filename.concat path comparison_file in
    let comparison_res = parse_comparison_file comparison_path in
    let files = Sys.readdir path in
    let res = List.fold_left (fun acc file -> 
      let config = config_from_filename file in
      let conf_str = conf_descr config in
      let res = parse_result_file (Filename.concat path file) in
      StringMap.add conf_str res acc
    ) StringMap.empty (List.filter (is_result_file packet) (Array.to_list files)) in
    { commit_number; res; comparison_res }
  else failwith (Printf.sprintf "can't find date dir in %s" path)

let read_results_packet packet path =
  Printf.printf "reading packet results in %s\n" path;
  if Sys.file_exists path && (Filename.basename path) <> "table.html"
  then 
    let dates = Sys.readdir path in
    Array.fold_left (fun acc date -> 
      let res = read_results_date packet (Filename.concat path date) in
      StringMap.add date res acc) StringMap.empty dates
  else StringMap.empty

let read_results_dir () =
  let results_dir = "results" in
  if Sys.file_exists results_dir
  then 
    let packets = Sys.readdir results_dir in
    Array.fold_left (fun acc packet -> 
      let res = read_results_packet packet (Filename.concat results_dir packet) in
      if (StringMap.cardinal res = 0) then acc
      else
        if StringMap.mem packet acc
        then
          let old = StringMap.find packet acc in
          StringMap.add packet (res::old) acc
        else StringMap.add packet [res] acc
    ) StringMap.empty packets
  else failwith "can't find results dir"

let aggregate_by_config2 date_res =
  List.fold_left (fun acc date_result ->
    StringMap.fold (fun date cfg_res acc ->
      let map = StringMap.fold (fun cfg res acc -> 
        if StringMap.mem cfg acc
        then
          let old = StringMap.find cfg acc in
          StringMap.add cfg ((date, res)::old) acc
        else StringMap.add cfg [(date,res)] acc
      ) cfg_res.res acc in
      if StringMap.mem "comparison" acc
        then
          let old = StringMap.find "comparison" map in
          StringMap.add "comparison" ((date, cfg_res.comparison_res)::old) map
        else StringMap.add "comparison" [(date, cfg_res.comparison_res)] map
    ) date_result acc
  ) StringMap.empty date_res

let aggregate_by_config date_res =
  let date_set = List.fold_left (fun acc date_result ->
    StringMap.fold (fun date _cfg_res acc ->
      StringSet.add date acc
    ) date_result acc
  ) StringSet.empty date_res in
  let agg = List.fold_left (fun acc date_result ->
    StringMap.fold (fun date cfg_res acc ->
      let map = StringMap.fold (fun cfg res acc -> 
        if StringMap.mem cfg acc
        then
          let old = StringMap.find cfg acc in
          StringMap.add cfg ((date, res)::old) acc
        else StringMap.add cfg [(date,res)] acc
      ) cfg_res.res acc in
      if StringMap.mem "comparison" acc
        then
          let old = StringMap.find "comparison" map in
          StringMap.add "comparison" ((date, cfg_res.comparison_res)::old) map
        else StringMap.add "comparison" [(date, cfg_res.comparison_res)] map
    ) date_result acc
  ) StringMap.empty date_res in
  StringMap.fold (fun cfg res acc -> 
    if (List.length res) = (StringSet.cardinal date_set)
    then StringMap.add cfg res acc
    else 
      let l = 
        StringSet.fold (fun date acc -> 
            try
              let date_res = List.assoc date res in
              (date, date_res)::acc
            with _ -> (date, empty_result ())::acc
          ) date_set [] in
      StringMap.add cfg l acc
  ) agg StringMap.empty

let border = "border:1px solid black;"
let border_top = "border-top:1px solid black;"
let border_bottom = "border-bottom:1px solid black;"
let border_right = "border-right:1px solid black;"
let border_right2px = "border-right:2px solid black;"
let border_left = "border-left:1px solid black;"
let border_spacing = "border-spacing:0;"
let text_align = "text-align:center;"
let background_ok = "background-color:#9FF781;"
let background_no = "background-color:#FA5858;"
let nowrap = "white-space: nowrap;"

let generate_style_compile cfg compile_time =
  Printf.sprintf "style=\"%s%s%s%s\"" 
    text_align 
    border_top 
    border_right
    (if cfg <> "comparison" && compile_time > 2.0 then background_no else background_ok)

let generate_style_size cfg size =
  Printf.sprintf "style=\"%s%s%s%s\"" 
    text_align 
    border_top 
    border_right
    (if cfg <> "comparison" && size > 1.11 then background_no else background_ok)

let generate_style_ssize cfg ssize =
  Printf.sprintf "style=\"%s%s%s%s\"" 
    text_align 
    border_top 
    border_right
    (if cfg <> "comparison" && ssize > 1.11 then background_no else background_ok)

let generate_style_runtime cfg run_time =
  Printf.sprintf "style=\"%s%s%s%s\"" 
    text_align 
    border_top 
    border_right2px
    (if cfg <> "comparison" && run_time > 1.01 then background_no else background_ok)

let _ =
  let map = read_results_dir () in
  let table = Filename.concat "results" "table.html" in
  Command.remove table;
  let oc = open_out table in
  StringMap.iter (fun packet date_results ->
    if (List.length date_results <> 0)
    then begin
      let date_res = List.hd date_results in
      let date_result = List.rev (StringMap.bindings date_res) in
      Printf.fprintf oc "<h1>%s</h1>\n" packet;
      Printf.fprintf oc
        "<table style=\"%s%s\"><tbody>\n" border border_spacing;

      Printf.fprintf oc "  <tr style=\"%s\">\n" text_align;
      Printf.fprintf oc "    <th></th>\n";
      List.iter (fun (date, _cfg_res) ->
         Printf.fprintf oc "    <th style=\"%s\" colspan=\"4\">%s</th>\n" border_left date
      ) date_result;
      Printf.fprintf oc "  </tr>\n";

      Printf.fprintf oc "  <tr style=\"%s\">\n" text_align;
      Printf.fprintf oc "    <th></th>\n";
      List.iter (fun (_date, cfg_res) ->
        Printf.fprintf oc "    <th style=\"%s\" colspan=\"4\">%s</th>\n" border_left cfg_res.commit_number
      ) date_result;
      Printf.fprintf oc "  </tr>\n";

      Printf.fprintf oc "  <tr style=\"%s\">\n" text_align;
      Printf.fprintf oc "    <th></th>\n";
      List.iter (fun (_date, _cfg_res) ->
        Printf.fprintf oc "<th style=\"%s\" colspan=\"1\">%s</th>" border_left "compile time";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "bin size";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "strip size";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "runtime"
      ) date_result;
      Printf.fprintf oc "  </tr>\n";

      let cfg_res = aggregate_by_config date_results in
      let comparisons = StringMap.find "comparison" cfg_res in
      let style_cfg = Printf.sprintf "style=\"%s%s%s\"" border_top border_right nowrap in
      let style_cfg2px = Printf.sprintf "style=\"%s%s%s\"" border_top border_right2px nowrap in
      StringMap.iter (fun cfg res ->
        Printf.fprintf oc "  <tr>\n";
        Printf.fprintf oc "    <td %s>%s</td>\n" style_cfg cfg;
        List.iteri (fun i (date, result) ->
          if (fst (List.nth comparisons i)) = date && result <> (empty_result ())
          then begin
            let compil_time =
              if cfg = "comparison" then result.compilation_time
              else
               (result.compilation_time /. (snd (List.nth comparisons i)).compilation_time) in
            let size =
              if cfg = "comparison" then result.size
              else (result.size /. (snd (List.nth comparisons i)).size) in
            let s_size =
              if cfg = "comparison" then result.strip_size
              else (result.strip_size /. (snd (List.nth comparisons i)).strip_size) in
            let cycles =
              if cfg = "comparison" then result.cycles
              else (result.cycles /. (snd (List.nth comparisons i)).cycles) in
            Printf.fprintf oc "<td %s colspan=\"1\">%.2f</td>" 
              (generate_style_compile cfg compil_time) compil_time;
            Printf.fprintf oc "<td %s colspan=\"1\">%.2f</td>" 
              (generate_style_size cfg size) size;
            Printf.fprintf oc "<td %s colspan=\"1\">%.2f</td>" 
              (generate_style_ssize cfg s_size) s_size;
            Printf.fprintf oc "<td %s colspan=\"1\">%.2f</td>" 
              (generate_style_runtime cfg cycles) cycles
            end
          else begin
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg2px
            end
        ) res;
        Printf.fprintf oc "  </tr>\n";
      ) cfg_res;

      Printf.fprintf oc "</tbody></table>\n";
    end
  ) map;
  close_out oc
