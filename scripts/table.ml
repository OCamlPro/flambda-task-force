open Configuration

module StringMap = Map.Make(String)

module StringSet = Set.Make(String)

type topic = {
  time_real: float;
  minor_words: float;
  promoted_words: float;
  major_words: float;
  minor_collections: float;
  major_collections: float;
  heap_words: float;
  heap_chunks: float;
  top_heap_words: float;
  live_words: float;
  live_blocks: float;
  free_words: float;
  free_blocks: float;
  largest_free: float;
  fragments: float;
  compactions: float;
}

type run_time = Cycles of float | Topics of (string * topic) list

type result = {
  compilation_time: float;
  size: float;
  strip_size: float;
  time: run_time;
}

type results = {
  commit_number: string;
  res: result StringMap.t;
  comparison_res: result;
}

let empty_result () =
  { compilation_time = 0.; size = 0.; strip_size = 0.; time = Cycles 0.; }

let dumb_results () =
  { commit_number = ""; res = StringMap.empty; comparison_res = empty_result() }

let dumb_topic () =
  { time_real = 0.; minor_words = 0.; promoted_words = 0.; major_words = 0.;
    minor_collections = 0.; major_collections = 0.; heap_words = 0.;
    heap_chunks = 0.; top_heap_words = 0.; live_words = 0.; live_blocks = 0.;
    free_words = 0.; free_blocks = 0.; largest_free = 0.; fragments = 0.; 
    compactions = 0. }   

let get_cycles = function
  | Cycles f -> f
  | _ -> assert false

let get_res_topic bench = function
  | Topics l -> 
    if List.mem_assoc bench l
    then List.assoc bench l
    else dumb_topic ()
  | _ -> dumb_topic ()

let update_topic topic f v = match f with
  | "Time_real" -> { topic with time_real = float v }
  | "Minor_words" -> { topic with minor_words = float v }
  | "Promoted_words" -> { topic with promoted_words = float v }
  | "Major_words" -> { topic with major_words = float v }
  | "Minor_collections" -> { topic with minor_collections = float v }
  | "Major_collections" -> { topic with major_collections = float v }
  | "Heap_words" -> { topic with heap_words = float v }
  | "Heap_chunks" -> { topic with heap_chunks = float v }
  | "Top_heap_words" -> { topic with top_heap_words = float v }
  | "Live_words" -> { topic with live_words = float v }
  | "Live_blocks" -> { topic with live_blocks = float v }
  | "Free_words" -> { topic with free_words = float v }
  | "Free_blocks" -> { topic with free_blocks = float v }
  | "Largest_free" -> { topic with largest_free = float v }
  | "Fragments" -> { topic with fragments = float v }
  | "Compactions" -> { topic with compactions = float v }
  | _ -> (Printf.printf "Error : %s\n%!" f; assert false)

let mean_topic topics =
  let total = float (List.length topics) in
  let sum = List.fold_left (fun acc topic ->
    { time_real = acc.time_real +. topic.time_real; 
      minor_words = acc.minor_words +. topic.minor_words; 
      promoted_words = acc.promoted_words +. topic.promoted_words; 
      major_words = acc.major_words +. topic.major_words;
      minor_collections = acc.minor_collections +. topic.minor_collections; 
      major_collections = acc.major_collections +. topic.major_collections; 
      heap_words = acc.heap_words +. topic.heap_words;
      heap_chunks = acc.heap_chunks +. topic.heap_chunks; 
      top_heap_words = acc.top_heap_words +. topic.top_heap_words; 
      live_words = acc.live_words +. topic.live_words; 
      live_blocks = acc.live_blocks +. topic.live_blocks;
      free_words = acc.free_words +. topic.free_words; 
      free_blocks = acc.free_blocks +. topic.free_blocks; 
      largest_free = acc.largest_free +. topic.largest_free; 
      fragments = acc.fragments +. topic.fragments; 
      compactions = acc.compactions +. topic.compactions }
  ) (dumb_topic ()) topics in
  if sum = (dumb_topic ()) then sum
  else
  { time_real = sum.time_real /. total;
    minor_words = sum.minor_words /. total;
    promoted_words = sum.promoted_words /. total;
    major_words = sum.major_words /. total;
    minor_collections = sum.minor_collections /. total;
    major_collections = sum.major_collections /. total;
    heap_words = sum.heap_words /. total;
    heap_chunks = sum.heap_chunks /. total;
    top_heap_words = sum.top_heap_words /. total;
    live_words = sum.live_words /. total;
    live_blocks = sum.live_blocks /. total;
    free_words = sum.free_words /. total;
    free_blocks = sum.free_blocks /. total;
    largest_free = sum.largest_free /. total;
    fragments = sum.fragments /. total;
    compactions = sum.compactions /. total }


let read_operf path =
  Printf.printf "reading %s...\n" path;
  let content = Command.input_all_file path in
  let list = List.tl (Str.split (Str.regexp_string "(data\n") content) in
  let res = 
    List.map (fun stats ->
      let topic = dumb_topic () in
      let stats = List.hd (Str.split (Str.regexp_string "(checked") stats) in
      let stats = Str.global_replace (Str.regexp_string "\n") " " stats in
      let parts = List.tl (Str.split (Str.regexp_string "((") stats) in
      let time_real_str = List.hd parts in
      let time_real = Scanf.sscanf time_real_str "(Time Real) (Int %i))" (fun v -> v) in
      let topic = { topic with time_real = (float time_real) } in
      List.fold_left (fun topic part ->
        try
          Scanf.sscanf part "Gc %[a-zA-Z_]) (Int %i))"
            (fun field value -> update_topic topic field value)
        with _ as exn -> (Printf.printf "Error : %s\n%!" part; raise exn)
      ) topic (List.tl parts)
    ) list in
    res

let get_topic compiler_name conf_str bench path =
  let files = Measurements.get_benchs_list bench in
  let res = 
    List.map (fun file ->
      let filename = Printf.sprintf "%s_%s_%s.operf" compiler_name file conf_str in
      let filename = Filename.concat path filename in
      if Sys.file_exists filename
      then 
        let topic = read_operf filename  in
        file, (mean_topic topic)
      else (Printf.printf "Can't find %s\n%!" filename; file, dumb_topic ())
    ) files in
  Topics res

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
     (fun value -> { res with time = Cycles (float value) }) in res
  with Scanf.Scan_failure _ | End_of_file -> res

let parse_bench_result_file file =
  let content = Command.input_all_file file in
  let res = empty_result () in
  let list = List.rev (Str.split (Str.regexp_string "\n") content) in
  let compile_time = List.nth list 2 in
  let size = List.nth list 1 in
  let strip_size = List.hd list in
  try
    let res = Scanf.sscanf compile_time "compile_time: %f" 
                (fun value -> { res with compilation_time = value }) in
    let res = Scanf.sscanf size "size: %[a-zA-Z0-9/+-._] = %i"
                (fun _ value -> { res with size = float value }) in
    let res = Scanf.sscanf strip_size "strip_size: %[a-zA-Z0-9/+-._] = %i"
                (fun _ value -> { res with strip_size = float value }) in res  
  with Scanf.Scan_failure _ | End_of_file -> res

let config_from_filename filename =
  let config_part = List.nth (Str.split (Str.regexp_string "_inline-") filename) 1 in
  try 
    Scanf.sscanf config_part
      "%[0-9]_rounds-%[0-9]_unroll-%[0-9]_call-cost-%[0-9]_alloc-cost-%[0-9]_prim-cost-%[0-9]_branch-cost-%[0-9]_branch-factor-%[0-9.]_nofunctorheuristic-%B_removeunusedargs-%B.result"
    (fun inline rounds unroll call_cost alloc_cost prim_cost branch_cost branch_factor nofunct unused -> 
      { inline = int_of_string inline; 
        rounds = int_of_string rounds; 
        unroll = int_of_string unroll; 
        inline_call_cost = int_of_string call_cost; 
        inline_alloc_cost = int_of_string alloc_cost; 
        inline_prim_cost = int_of_string prim_cost;
        inline_branch_cost = int_of_string branch_cost; 
        branch_inline_factor = Some (float_of_string branch_factor);
        no_functor_heuristic = nofunct;
        remove_unused_arguments = Some unused })
  with Scanf.Scan_failure _ -> 
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
        branch_inline_factor = Some (float_of_string branch_factor);
        no_functor_heuristic = nofunct;
        remove_unused_arguments = None })
  with Scanf.Scan_failure _ -> 
  try
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
        branch_inline_factor = None;
        no_functor_heuristic = nofunct;
        remove_unused_arguments = None })
  with Scanf.Scan_failure _ as exc -> (Printf.printf "==\n%s\n==\n" filename; raise exc)

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
    let comparison_res = parse_result_file comparison_path in
    let files = Sys.readdir path in
    let res = List.fold_left (fun acc file -> 
      let config = config_from_filename file in
      let conf_str = conf_descr config in
      let res = parse_result_file (Filename.concat path file) in
      StringMap.add conf_str res acc
    ) StringMap.empty (List.filter (is_result_file packet) (Array.to_list files)) in
    { commit_number; res; comparison_res }
  else failwith (Printf.sprintf "can't find date dir in %s" path)

let read_benchs_date bench path =
  Printf.printf "reading date results in %s\n" path;
  if Sys.file_exists path
  then
    let commit_file = Filename.concat path "commit_number" in
    let commit_number = read_commit_file commit_file in
    Printf.printf "commit_number : %s\n%!" commit_number;
    let comparison_file = Printf.sprintf "4.03.0+comparison+gen_%s_.result" bench in
    let comparison_path = Filename.concat path comparison_file in
    let comparison_res = parse_bench_result_file comparison_path in
    let comparison_res = { comparison_res with time = (get_topic "4.03.0+comparison+gen" "" bench path) } in
    (* Printf.printf "==sequence : %f ==\n%!" (get_res_topic "sequence" comparison_res.time).time_real; *)
    let files = Sys.readdir path in
    let res = List.fold_left (fun acc file ->
      let config = config_from_filename file in
      let conf_str = conf_descr config in
      let res = parse_bench_result_file (Filename.concat path file) in
      let res = { res with time = (get_topic "4.03.0+flambda+gen" conf_str bench path) } in
      StringMap.add conf_str res acc
    ) StringMap.empty (List.filter (is_result_file bench) (Array.to_list files)) in
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

let read_results_bench bench path =
  Printf.printf "reading bench results in %s\n" path;
  if Sys.file_exists path && (Filename.basename path) <> "table.html"
  then 
    let dates = Sys.readdir path in
    Array.fold_left (fun acc date -> 
      let res = read_benchs_date bench (Filename.concat path date) in
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

let read_benchs_dir () =
  let results_dir = "benchs" in
  if Sys.file_exists results_dir
  then 
    let benchs = Sys.readdir results_dir in
    Array.fold_left (fun acc bench -> 
      let res = read_results_bench bench (Filename.concat results_dir bench) in
      if (StringMap.cardinal res = 0) then acc
      else
        if StringMap.mem bench acc
        then
          let old = StringMap.find bench acc in
          StringMap.add bench (res::old) acc
        else StringMap.add bench [res] acc
    ) StringMap.empty benchs
  else failwith "can't find benchs dir"

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

let generate_table_packet map =
  let table = Filename.concat "results" "table.html" in
  Command.remove table;
  let oc = open_out table in
  Printf.fprintf oc "<html><head><title>%s</title>" "Summary table";
  Printf.fprintf oc "<style type=\"text/css\">\n%s\n</style>\n  </head>\n"
    "table tr:nth-child(even){background-color:lightgrey;}";
  Printf.fprintf oc "<h1 style=\"text-align:center\">Generated on %s</h1>\n" (Command.time_str ());
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
              if cfg = "comparison" then (get_cycles result.time)
              else
                let res_cycles = get_cycles result.time in
                let compare_cycles = get_cycles ((snd (List.nth comparisons i)).time) in
                (res_cycles /. compare_cycles) in
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
  Printf.fprintf oc "</html>";
  close_out oc

let normalize_topics res compare =
  { time_real = res.time_real /. compare.time_real;
    minor_words = res.minor_words /. compare.minor_words;
    promoted_words = res.promoted_words /. compare.promoted_words;
    major_words = res.major_words /. compare.major_words;
    minor_collections = res.minor_collections /. compare.minor_collections;
    major_collections = res.major_collections /. compare.major_collections;
    heap_words = res.heap_words /. compare.heap_words;
    heap_chunks = res.heap_chunks /. compare.heap_chunks;
    top_heap_words = res.top_heap_words /. compare.top_heap_words;
    live_words = res.live_words /. compare.live_words;
    live_blocks = res.live_blocks /. compare.live_blocks;
    free_words = res.free_words /. compare.free_words;
    free_blocks = res.free_blocks /. compare.free_blocks;
    largest_free = res.largest_free /. compare.largest_free;
    fragments = res.fragments /. compare.fragments;
    compactions = res.compactions /. compare.compactions }


let generate_table_bench map =
  let table = Filename.concat "results" "bench.html" in
  Command.remove table;
  let oc = open_out table in
  Printf.fprintf oc "<html><head><title>%s</title>" "Summary table";
  Printf.fprintf oc "<style type=\"text/css\">\n%s\n</style>\n  </head>\n"
    "table tr:nth-child(even){background-color:lightgrey;}";
  Printf.fprintf oc "<h1 style=\"text-align:center\">Generated on %s</h1>\n" (Command.time_str ());
  StringMap.iter (fun packet date_results ->
    if (List.length date_results <> 0)
    then begin
      let date_res = List.hd date_results in
      let date_result = List.rev (StringMap.bindings date_res) in
      let benchs = Measurements.get_benchs_list packet in 
      Printf.fprintf oc "<h1>%s</h1>\n" packet;
      List.iter (fun bench ->
      Printf.fprintf oc "<h2>%s</h2>\n" bench;
      Printf.fprintf oc
        "<table style=\"%s%s\"><tbody>\n" border border_spacing;

      Printf.fprintf oc "  <tr style=\"%s\">\n" text_align;
      Printf.fprintf oc "    <th></th>\n";
      List.iter (fun (date, _cfg_res) ->
         Printf.fprintf oc "    <th style=\"%s\" colspan=\"19\">%s</th>\n" border_left date
      ) date_result;
      Printf.fprintf oc "  </tr>\n";

      Printf.fprintf oc "  <tr style=\"%s\">\n" text_align;
      Printf.fprintf oc "    <th></th>\n";
      List.iter (fun (_date, cfg_res) ->
        Printf.fprintf oc "    <th style=\"%s\" colspan=\"19\">%s</th>\n" border_left cfg_res.commit_number
      ) date_result;
      Printf.fprintf oc "  </tr>\n";

      Printf.fprintf oc "  <tr style=\"%s\">\n" text_align;
      Printf.fprintf oc "    <th></th>\n";
      List.iter (fun (_date, _cfg_res) ->
        Printf.fprintf oc "<th style=\"%s\" colspan=\"1\">%s</th>" border_left "compile time";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "bin size";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "strip size";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "time real";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "minor words";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "promoted words";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "major words";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "minor collections";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "major collections";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "heap words";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "heap chunks";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "top heap words";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "live words";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "live blocks";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "free words";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "free blocks";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "largest free";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "fragments";
        Printf.fprintf oc "<th colspan=\"1\">%s</th>" "compactions";
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
          let compare_topic = get_res_topic bench ((snd (List.nth comparisons i)).time) in
          let res_topic = get_res_topic bench result.time in
          if (fst (List.nth comparisons i)) = date && result <> (empty_result ()) && compare_topic <> (dumb_topic ()) && res_topic <> (dumb_topic ())
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
            let topic =
              if cfg = "comparison" then (get_res_topic bench result.time)
              else normalize_topics res_topic compare_topic in
            Printf.fprintf oc "<td %s colspan=\"1\">%.2f</td>"
              (generate_style_compile cfg compil_time) compil_time;
            Printf.fprintf oc "<td %s colspan=\"1\">%.2f</td>"
              (generate_style_size cfg size) size;
            Printf.fprintf oc "<td %s colspan=\"1\">%.2f</td>"
              (generate_style_ssize cfg s_size) s_size;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.time_real;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.minor_words;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.promoted_words;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.major_words;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.minor_collections;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.major_collections;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.heap_words;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.heap_chunks;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.top_heap_words;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.live_words;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.live_blocks;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.free_words;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.free_blocks;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.largest_free;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.fragments;
            Printf.fprintf oc "<th %s colspan=\"1\">%.2f</th>" style_cfg topic.compactions;
            end
          else begin
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg;
            Printf.fprintf oc "<td %s colspan=\"1\"></td>" style_cfg2px
            end
        ) res;
        Printf.fprintf oc "  </tr>\n";
      ) cfg_res;
      Printf.fprintf oc "</tbody></table>\n";
      ) benchs;
    end
  ) map;
  Printf.fprintf oc "</html>";
  close_out oc


let _ =
  if (Array.length Sys.argv) > 1
  then 
    let map = read_benchs_dir () in
    generate_table_bench map
  else
  let map = read_results_dir () in
  generate_table_packet map
