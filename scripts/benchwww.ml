open Cow
open Macroperf

(* Only consider switches with a name ending with this suffix *)
let bench_switch_suffix = "+bench"

let short_switch_name sw =
  Filename.chop_suffix sw bench_switch_suffix

let date_of_dir d =
  if String.length d > 15 then String.sub d 0 15 else d

let ( @* ) g f x = g (f x)

let rec underscore_to_space s =
  try
    Bytes.set s (Bytes.index s '_') ' ';
    underscore_to_space s
  with Not_found -> s


let ignored_topics = Topic.([
  Topic (Gc.Heap_words, Gc);
  Topic (Gc.Heap_chunks, Gc);
  Topic (Gc.Live_words, Gc);
  Topic (Gc.Live_blocks, Gc);
  Topic (Gc.Free_words, Gc);
  Topic (Gc.Free_blocks, Gc);
  Topic (Gc.Largest_free, Gc);
  Topic (Gc.Fragments, Gc);
])

let score topic ~result ~comparison =
  let open Summary.Aggr in
  if result.mean = comparison.mean then 1. else
  match topic with
  | Topic.Topic (gc, Topic.Gc) when gc = Topic.Gc.Promoted_words ->
    (* Comparing ratios: use a difference *)
    1. +. result.mean -. comparison.mean
  | _ -> result.mean /. comparison.mean

let print_score score =
  let percent = score *. 100. -. 100. in
  Printf.sprintf "%+.*f%%"
    (max 0 (2 - truncate (log10 (abs_float percent))))
    percent

let average_score topic scores = match topic with
  | Topic.Topic (gc, Topic.Gc) when gc = Topic.Gc.Promoted_words -> (* linear *)
    List.fold_left ( +. ) 0. scores /. float (List.length scores)
  | _ -> (* geometric *)
    exp @@
    List.fold_left (fun acc s -> acc +. log s) 0. scores /.
    float (List.length scores)

let scorebar_style topic score =
  let gradient =
    if score < 1. then
      let pct = 100. *. score in
      [
        "transparent", 0.;
        "transparent", pct;
        "#55ff88", pct;
        "#55ff88", 100.;
      ]
    else
      let pct = match topic with
        | Topic.Topic (gc, Topic.Gc) when gc = Topic.Gc.Promoted_words ->
          100. *. (score -. 1.)
        | _ -> 100. *. (1. -. 1. /. score)
      in
      [
        "#ff5555", 0.;
        "#ff5555", pct;
        "transparent", pct;
        "transparent", 100.;
      ]
  in
  Printf.sprintf "background:linear-gradient(to right,%s);border:1px solid %s"
    (String.concat "," (List.map (fun (c,p) -> Printf.sprintf "%s %.0f%%" c p) gradient))
    (if score <= 1. then "#33bb66" else "#bb4444")

(* adds _ separators every three digits for readability *)
let print_float f =
  match classify_float f with
  | FP_zero -> "0"
  | FP_infinite | FP_subnormal | FP_nan -> Printf.sprintf "%.3f" f
  | FP_normal ->
    let rec split f =
      if abs_float f >= 1000. then
        mod_float (abs_float f) 1000. ::
        split (f /. 1000.)
      else [f]
    in
    match split f with
    | [] -> assert false
    | [f] ->
      if truncate ((mod_float f 1.) *. 1000.) = 0
      then Printf.sprintf "%.f" f
      else Printf.sprintf "%.3f" f
    | last::r ->
      let first, middle = match List.rev r with
        | first::r -> first, r
        | _ -> assert false
      in
      String.concat "_"
        (Printf.sprintf "%d" (truncate first) ::
         List.map (Printf.sprintf "%03d" @* truncate) middle @
         [Printf.sprintf "%03.f" last])

let topic_unit = function
  | Topic.Topic (_, Topic.Time) -> " (ns)"
  | Topic.Topic (_, Topic.Size) -> " (bytes)"
  | Topic.Topic (gc, Topic.Gc) when gc = Topic.Gc.Promoted_words ->
    " (relative to minor words)"
  | _ -> ""

let get_bench_error error macrodir switch bench =
  match error with
  | Some (stdout, stderr) -> stdout, stderr
  | None -> (* Older data, without err message: get from the result file if any *)
  let res = Result.load_conv_exn Util.FS.(macrodir / bench / switch ^ ".result") in
  match
    List.fold_left (fun acc -> function
        | `Ok {Execution.process_status = Unix.WEXITED 0} -> acc
        | `Ok ({Execution.process_status = _} as ex) -> Some ex
        | _ -> None)
      None res.Result.execs
  with
  | Some ex -> Execution.(ex.stdout, ex.stderr)
  | None -> raise Not_found

let collect_dir dir =
  let bench_dirs =
    Util.FS.(List.filter is_dir_exn (ls ~prefix:true dir))
  in
  (* Refresh summary files, which may be needed sometimes *)
  SSet.iter Summary.summarize_dir (SSet.of_list bench_dirs);
  List.fold_left (fun acc dir -> DB.of_dir ~acc dir) DB.empty bench_dirs

let by_topic data =
  DB.fold_data
    (fun bench context_id topic -> DB2.add topic bench context_id)
    data DB2.empty

let collect (comparison_dir,comparison_switch) (result_dir,result_switch) =
  let result_data_by_bench = collect_dir result_dir in
  let result_data_by_topic = by_topic result_data_by_bench in
  let comparison_data_by_bench, comparison_data_by_topic =
    if comparison_dir = result_dir then
      result_data_by_bench, result_data_by_topic
    else
      let by_bench = collect_dir comparison_dir in
      by_bench, by_topic by_bench
  in
  let ignored_topics =
    let code_sz = Topic.(Topic (Size.Code, Size)) in
    if TMap.mem code_sz result_data_by_topic &&
       TMap.mem code_sz comparison_data_by_topic
    then Topic.(Topic (Size.Full, Size)) :: ignored_topics
    else code_sz :: Topic.(Topic (Size.Data, Size)) :: ignored_topics
  in
  let logkey ~dir ~switch ~bench =
    Printf.sprintf "log-%s-%s-%s" (Filename.basename dir) switch bench
  in
  let logs, avgscores, table_contents =
    TMap.fold (fun topic m (logs,avgscores,html) ->
        if List.mem topic ignored_topics then logs,avgscores,html else
        let bench_all, logs, bench_html =
          SMap.fold (fun bench m (acc,logs,html) ->
              let open Summary.Aggr in
              let comparison =
                try Some (
                    TMap.find topic comparison_data_by_topic
                    |> SMap.find bench
                    |> SMap.find comparison_switch)
                with Not_found -> None
              in
              let result = try Some (SMap.find result_switch m) with Not_found -> None in
              let acc, scorebar =
                match comparison, result with
                | Some ({success = true; _} as comparison),
                  Some ({success = true; _} as result) ->
                  let score = score topic ~result ~comparison in
                  (match classify_float (log score) with
                   | FP_nan | FP_infinite -> acc
                   | _ -> score :: acc),
                  <:html<<td class="scorebar" style="$str:scorebar_style topic score$">
                           $str:print_score score$
                         </td>&>>
                | _ ->
                  acc, <:html<<td>ERR</td>&>>
              in
              let td logs swdir swname = function
                | Some ({success = true; _} as r) ->
                  let tooltip = Printf.sprintf "%d runs, stddev %s" r.runs (print_float r.stddev) in
                  logs,
                  <:html<<td title="$str:tooltip$">$str:print_float r.mean$</td>&>>
                | Some ({success = false}) ->
                  let k = logkey ~dir:swdir ~switch:swname ~bench in
                  (if SMap.mem k logs then logs
                   else
                     let error =
                       try
                         let idmap = SMap.find bench result_data_by_bench in
                         (SMap.find swname idmap).Summary.error
                       with Not_found -> None
                     in
                     try
                       let stdout, stderr = get_bench_error error swdir swname bench in
                       let name =
                         Printf.sprintf "%s on %s (%s)" bench swname (Filename.basename swdir)
                       in
                       SMap.add k (name,stdout,stderr) logs
                     with _ -> logs),
                  <:html<<td class="error"><a href="$str:"#"^k$">failed</a></td>&>>
                | None ->
                  logs,
                  <:html<<td>-</td>&>>
              in
              let logs, td_result =
                td logs result_dir result_switch result
              in
              let logs, td_compar =
                td logs comparison_dir comparison_switch comparison
              in
              acc,
              logs,
              <:html<$html$
                     <tr><td class="bench-topic">$str:bench$</td>
                     $scorebar$
                     $td_result$
                     $td_compar$
                     </tr>&>>)
            m ([],logs,<:html<&>>)
        in
        let avgscore = average_score topic bench_all in
        logs,
        TMap.add topic avgscore avgscores,
        <:html<$html$
               <tr class="bench-topic">
                 <th>$str:Topic.to_string topic$$str:topic_unit topic$</th>
                 <td>$str:print_score avgscore$</td>
                 <td></td>
                 <td></td>
               </tr>
               $bench_html$>>)
      result_data_by_topic (SMap.empty, TMap.empty, <:html<&>>)
  in
  let name_result, name_comp =
    if result_switch = comparison_switch then
      Filename.basename result_dir ^" "^ result_switch,
      Filename.basename comparison_dir ^" "^ comparison_switch
    else
      result_switch, comparison_switch
  in
  let table = <:html<
    <table>
       <thead><tr>
         <th>Benchmark</th>
         <th>Relative score</th>
         <th>$str:short_switch_name name_result$</th>
         <th>$str:short_switch_name name_comp$</th>
       </tr></thead>
       <tbody>
         $table_contents$
       </tbody>
    </table>
  >> in
  let summary_table =
    let topics =
      TSet.of_list (List.map fst (TMap.bindings result_data_by_topic))
    in
    let topics =
      List.fold_left (fun acc t -> TSet.remove t acc) topics ignored_topics
    in
    let titles =
      TSet.fold (fun t html ->
          <:html<$html$
                 <th class="scorebar-small">
                   $str:underscore_to_space (Topic.to_string t)$
                 </th>&>>)
        topics <:html<<th>Benchmark</th>&>>
    in
    let averages =
      TSet.fold (fun t html ->
          let score = TMap.find t avgscores in
          <:html<$html$
                 <td class="scorebar-small"
                     style="$str:scorebar_style t score$">
                   $str:print_score score$
                 </td>&>>)
        topics <:html<<th>Average</th>&>>
    in
    let contents =
      SMap.fold (fun bench ctx_map html ->
          let comparison_map =
            try (SMap.find comparison_switch
                   (SMap.find bench comparison_data_by_bench)).Summary.data
            with Not_found -> TMap.empty
          in
          let result_map =
            try (SMap.find result_switch ctx_map).Summary.data
            with Not_found -> TMap.empty
          in
          let topics =
            TSet.fold (fun t html ->
                try
                  let open Summary.Aggr in
                  let comparison = TMap.find t comparison_map in
                  let result = TMap.find t result_map in
                  if not (comparison.success && result.success) then raise Not_found;
                  let score = score t ~result ~comparison in
                  <:html<$html$
                         <td class="scorebar-small" style="$str:scorebar_style t score$">
                           $str:print_score score$
                         </td>&>>
                with Not_found ->
                  let k = logkey ~dir:result_dir ~switch:result_switch ~bench in
                  if SMap.mem k logs then
                    <:html<$html$<td class="scorebar-small error">
                             <a href="$str:"#"^k$">failed</a>
                           </td>&>>
                  else
                    <:html<$html$<td>-</td>&>>)
              topics <:html<&>>
          in
          let link = "graph?bench=" ^ bench in
          let bname =
            if String.length bench <= 40 then
              <:html<<td style="text-align:left;">
                       <a href=$str:link$ style="text-decoration:none">
                         $str:bench$
                       </a>
                     </td>&>>
            else
              <:html<<td style="text-align:left;" title="$str:bench$">
                       <a href=$str:link$ style="text-decoration:none">
                         $str:String.sub bench 0 40$
                       </a>
                     </td>&>>
          in
          <:html<$html$<tr>$bname$$topics$</tr>&>>)
        result_data_by_bench <:html<&>>
    in
    <:html< <table>
              <thead>
                <tr>$titles$</tr>
                <tr class="bench-topic">$averages$</tr>
              </thead>
              <tbody>$contents$</tbody>
            </table>
    >>
  in
  let html_logs =
    SMap.fold (fun id (name, stdout, stderr) html ->
        <:html< $html$
                <div class="logs" id="$str:id$">
                  <a class="close" href="#close">Close</a>
                  <h3>Error running bench $str:name$</h3>
                  <h4>Stdout</h4><pre>$str:stdout$</pre>
                  <h4>Stderr</h4><pre>$str:stderr$</pre>
                </div>&>>)
      logs <:html<&>>
  in
  <:html< <h2>Summary table</h2>
          $summary_table$
          <h2>Full results</h2>
          $table$
          $html_logs$
  >>

let bench_graph basedir bench =
  let dirs = Util.FS.(List.filter is_dir_exn (ls ~prefix:false basedir)) in
  let data = (* date -> switch -> summary map *)
    List.fold_left (fun date_map date_dir ->
        let bench_dir =
          let (/) = Filename.concat in
          basedir / date_dir / bench
        in
        if Sys.file_exists bench_dir then
          let switch_summary_map =
            Util.FS.fold_files (fun switch_map f ->
                if Filename.check_suffix f (bench_switch_suffix^".summary") then
                  let switch = Filename.(chop_extension (basename f)) in
                  try SMap.add switch (Summary.load_conv_exn f) switch_map
                  with _ -> switch_map
                else switch_map)
              SMap.empty bench_dir
          in
          if SMap.is_empty switch_summary_map then date_map
          else SMap.add (date_of_dir date_dir) switch_summary_map date_map
        else date_map)
      SMap.empty dirs
  in
  let all_switches, all_topics =
    SMap.fold (fun _date swmap acc ->
        SMap.fold (fun sw summary (allsw,allt) ->
            SSet.add sw allsw,
            TMap.fold (fun t _ allt -> TSet.add t allt)
              summary.Summary.data allt)
          swmap acc)
      data (SSet.empty, TSet.empty)
  in
  let all_topics =
    List.fold_left (fun acc t -> TSet.remove t acc) all_topics ignored_topics
  in
  let topic_data_file topic =
    let fn =
      Filename.temp_file ("operf-bench-"^Topic.to_string topic^"-") ".data"
    in
    let oc = open_out fn in
    SMap.iter (fun date switch_summary_map ->
        output_string oc date;
        output_char oc ' ';
        SSet.iter (fun sw ->
            try
              let summary = SMap.find sw switch_summary_map in
              let aggr = TMap.find topic summary.Summary.data in
              if not aggr.Summary.Aggr.success then raise Not_found;
              Printf.fprintf oc "%f " aggr.Summary.Aggr.mean
            with Not_found -> output_string oc ". ";)
          all_switches;
        output_char oc '\n')
      data;
    close_out oc;
    fn
  in
  let data_files =
    TSet.fold
      (fun topic acc -> TMap.add topic (topic_data_file topic) acc)
      all_topics TMap.empty
  in
  let svg_file =
    Filename.temp_file "operf-bench-" ".svg"
  in
  let gp_file =
    let fn = Filename.temp_file "operf-bench-" ".gp" in
    let oc = open_out fn in
    let num_topics = TSet.cardinal all_topics in
    Printf.fprintf oc
      "set terminal svg size 1200,%d enhanced mouse standalone;\n"
      (num_topics * 600);
    Printf.fprintf oc "set output \"%s\";\n" svg_file;
    output_string oc
      "set style line 1 lt 1 lw 1.1 pt 7 ps 0.3 lc rgb '#0072bd';\n\
       set style line 2 lt 1 lw 1.1 pt 7 ps 0.3 lc rgb '#edb120';\n\
       set style line 3 lt 1 lw 1.1 pt 7 ps 0.3 lc rgb '#d95319';\n\
       set style line 4 lt 1 lw 1.1 pt 7 ps 0.3 lc rgb '#7e2f8e';\n\
       set style line 5 lt 1 lw 1.1 pt 7 ps 0.3 lc rgb '#c21020';\n\
       set style line 6 lt 1 lw 1.1 pt 7 ps 0.3 lc rgb '#77ac30';\n";
    output_string oc "set xdata time; set timefmt \"%Y-%m-%d-%H%M\";\n";
    output_string oc "set format x \"%Y-%m-%d\";\n";
    output_string oc "set key top left;\n";
    Printf.fprintf oc "set xrange [ %S : %S ];\n"
      (fst (SMap.min_binding data)) (fst (SMap.max_binding data));
    output_string oc "set lmargin 15;\n";
    Printf.fprintf oc "set multiplot \
                       title \"Operf-macro, history of bench %s\" \
                       layout %d,1;\n"
      bench num_topics;
    let plot_topic topic data_file =
      Printf.fprintf oc "set title \"%s %s\";\n"
        (underscore_to_space (Topic.to_string topic)) (topic_unit topic);
      SSet.fold (fun sw i ->
          Printf.fprintf oc
            "%s \"%s\" using 1:%d with linespoints ls %d title \"%s\""
            (if i=0 then "plot" else ",\\\n    ")
            data_file
            (i+2) (i+1)
            (short_switch_name sw);
          i+1)
        all_switches 0
      |> ignore;
      output_string oc ";\n\n"
    in
    TMap.iter plot_topic data_files;
    output_string oc "unset multiplot;\n";
    close_out oc;
    fn
  in
  let gnuplot_ret =
    (* not Lwt-aware... *)
    Sys.command (Printf.sprintf "gnuplot %S" gp_file)
  in
  let cleanup () =
    let rm fn = if Sys.file_exists fn then Sys.remove fn in
    rm gp_file;
    TMap.iter (fun _ fn -> rm fn) data_files;
    rm svg_file
  in
  if gnuplot_ret <> 0 then (cleanup (); failwith "Gnuplot error");
  let svg = Util.File.string_of_file svg_file in
  cleanup ();
  svg

let css = "
    table {
      margin: auto;
    }
    thead {
      position:-webkit-sticky;
      position:-moz-sticky;
      position:sticky;
      top:0;
    }
    .bench-topic {
      text-align: left;
    }
    a {
      text-decoration: none;
    }
    th {
      text-align: left;
    }
    td {
      padding: 2px;
      text-align: right;
    }
    .scorebar {
      min-width: 300px;
    }
    .scorebar-small {
      font-size: small;
      width: 100px;
    }
    tr:nth-child(even) {
      background-color: #e5e5e5;
    }
    tr.bench-topic {
      background: #cce;
    }
    .error.scorebar, .error.scorebar-small {
      border: 1px solid orange;
    }
    .error, .error a {
      color: orangered;
    }

    div {
      padding: 3ex;
    }
    pre {
      padding: 1ex;
      border: 1px solid grey;
      background-color: #eee;
    }
    .logs {
      display: none;
    }
    .logs:target {
      display: block;
      position: fixed;
      top: 5%;
      left: 5%;
      right: 5%;
      bottom: 5%;
      border: 1px solid black;
      background-color: white;
      overflow: scroll;
      z-index: 10;
    }
    .close {
      display: block;
      position: fixed;
      top: 7%;
      right: 7%;
    }
    a:target {
      background-color: #e0e000;
    }
    .index td {
      margin: 3px;
      padding: 5px;
    }
    .index tr {
      background-color: #eee;
      border: 1px solid #aaac;
      border-collapse: collapse;
    }
    span.radio {
      font-size: 80%;
      padding: 2px;
      border-top: 2px solid #fff;
      border-left: 2px solid #fff;
      border-right: 2px solid #666;
      border-bottom: 2px solid #666;
    }
    ul.benches {
       list-style-type: none;
    }
    .benches li {
       display: inline-block;
       border: 1px solid #aaaa88;
       margin: 3px;
       padding: 1px;
       background-color: #eeeeee;
    }
"

let hashcol hash =
  if String.length hash >= 6 then
    try
      int_of_string ("0x"^String.sub hash 0 6)
      lor 0x808080
      |> Printf.sprintf "#%06x"
    with Failure _ -> "white"
  else "white"

let hashstyle hash =
  Printf.sprintf
    "background-color:%s;font-size:130%%;font-family:monospace"
    (hashcol hash)

let gen_full_page comp result =
  let table = collect comp result in
  let sw_name (_,sw) = short_switch_name sw in
  let sw_printname ((dir,_) as sw) =
    if comp <> result && snd comp = snd result then
      let d = Filename.basename dir in
      date_of_dir d ^"/"^ sw_name sw
    else sw_name sw
  in
  let sw_hash (swdir, _ as sw) =
    try
      Util.File.string_of_file
        Filename.(concat swdir (sw_name sw) ^ ".hash")
      |> String.trim
    with _ -> "?"
  in
  let sw_params (swdir, _ as sw) =
    try
      Util.File.string_of_file
        Filename.(concat swdir (sw_name sw) ^ ".params")
      |> String.trim
    with _ -> ""
  in
  let cmp_hash = sw_hash comp in
  let cmp_params = sw_params comp in
  let res_hash = sw_hash result in
  let res_params = sw_params result in
  let title =
    Printf.sprintf "Comparing %s@%s with %s@%s (at %s)"
      (sw_name result) res_hash (sw_name comp) cmp_hash
      (if fst comp = fst result then Filename.basename (fst comp)
       else Printf.sprintf "%s and %s"
           (Filename.basename (fst result))
           (Filename.basename (fst comp)))
  in
  <:html<
    <html>
      <head>
        <title>Operf-macro, $str:title$</title>
        <style type="text/css">$str:css$
        </style>
      </head>
      <body>
        <h1>Operf-macro comparison</h1>
        <table>
          <tr><th>Comparing</th>
              <td>$str:sw_printname result$</td>
              <td style="$str:hashstyle res_hash$">$str:res_hash$</td>
              <td style="text-align:left;font-family:monospace">$str:res_params$</td></tr>
          <tr><th>Against</th>
              <td>$str:sw_printname comp$</td>
              <td style="$str:hashstyle cmp_hash$">$str:cmp_hash$</td>
              <td style="text-align:left;font-family:monospace">$str:cmp_params$</td></tr>
        </table>
        <p>For all the measures below, smaller is better</p>
        <p>Promoted words are measured as a ratio of minor words,
           and compared linearly with the reference</p>
        $table$
      </body>
    </html>
  >>

let duration ts =
  let sec = int_of_float ts in
  let min, sec = sec / 60, sec mod 60 in
  let hr, min = min / 60, min mod 60 in
  if hr > 0 then Printf.sprintf "%d hours, %d minutes" hr min
  else if min > 0 then Printf.sprintf "%d minutes" min
  else if sec > 0 then Printf.sprintf "%d seconds" sec
  else "right now"

let index basedir =
  let dirs = Util.FS.(List.filter is_dir_exn (ls ~prefix:true basedir)) in
  let dirs = List.sort compare dirs in
  let dirs_switches, all_benches =
    List.fold_left (fun (acc,all_benches) d ->
        let switches, all_benches =
          Util.FS.fold_files (fun (switches, all_benches) f ->
              if Filename.check_suffix f (bench_switch_suffix^".summary") then
                SSet.add Filename.(basename (chop_extension f)) switches,
                SSet.add Filename.(basename (dirname f)) all_benches
              else switches, all_benches)
            (SSet.empty, SSet.empty)
            d
        in
        if SSet.is_empty switches &&
           not (Sys.file_exists (Filename.concat d "stamp"))
        then acc, all_benches
        else (d, switches) :: acc, all_benches)
      ([], SSet.empty) dirs
  in
  let all_switches =
    List.fold_left (fun acc (d, switches) -> SSet.union acc switches)
      SSet.empty dirs_switches
  in
  let plots =
    List.fold_left (fun acc bench ->
        let target = "/graph?bench="^bench in
        <:html<<li><a href="$str:target$">$str:bench$</a></li>&>>
        :: acc
      )
      [] (SSet.elements all_benches)
    |> List.rev
  in
  let switch_details =
    List.map (fun (d, switches) ->
        let hashes =
          List.fold_left (fun hashes swname ->
              let hash =
                try
                  String.trim @@
                  Util.File.string_of_file
                    Filename.(concat d @@ short_switch_name swname ^ ".hash")
                with _ -> ""
              in
              if hash <> "" then SMap.add swname hash hashes else hashes)
            SMap.empty (SSet.elements all_switches)
        in
        d, switches, hashes)
      dirs_switches
  in
  let thead =
    let sws =
      SSet.fold (fun s acc ->
          <:html<<th>$str:short_switch_name s$</th>&>> :: acc
        )
        all_switches []
      |> List.rev
      |> Html.concat
    in
    <:html<<thead><tr>
             <th>Run</th>
             $sws$
           </tr></thead>&>>
  in
  let lines =
    List.map (fun (dir,switches,hashes) ->
        let status =
          if SSet.is_empty switches then
            if Sys.file_exists (Filename.concat dir "timings") then
              `No_results
            else try
              `Running_since
                (Unix.stat (Filename.concat dir "build.html")).Unix.st_mtime
            with Unix.Unix_error _ -> try
              `Building
                (Unix.stat (Filename.concat dir "stamp")).Unix.st_mtime
            with Unix.Unix_error _ -> `Building 0.
          else
            `Complete
        in
        let switches =
          match status with
          | `Building since ->
            [ <:html<<td style="text-align:center" colspan="$int:SSet.cardinal all_switches$">
                       Building since $str:duration (Unix.time () -. since)$
              </td>&>> ]
          | _ ->
            SSet.fold (fun sw acc ->
                if status = `Complete &&
                   not (SSet.mem sw switches) then <:html<<td></td>&>> :: acc
                else
                  let hash =
                    try SMap.find sw hashes with Not_found -> "________"
                  in
                  let value = Filename.basename dir ^"/"^ sw in
                  let inputs =
                    if status = `Complete then
                      <:html<
                      <span class="radio">
                      <input type="radio" name="test" value="$str:value$"/>Test |
                      <input type="radio" name="reference" value="$str:value$"/>Ref
                    </span>&>>
                    else <:html<&>>
                  in
                  <:html<
                  <td style="text-align:left">
                     <span style="$str:hashstyle hash$">$str:hash$</span>$inputs$
                  </td>&>>
                  ::acc
              )
              all_switches []
        in
        let name = Filename.basename dir in
        let name =
          if String.length name > 15 then String.sub name 0 15 else name
        in
        let switches = Html.concat (List.rev switches) in
        let status_line = match status with
          | `Complete | `Building _ | `No_results -> <:html<&>>
          | `Running_since since ->
            <:html<<tr><th></th>
                   <td style="text-align:center" colspan="$int:SSet.cardinal all_switches$">
                       Running since $str:duration (Unix.time () -. since)$
                   </td></tr>&>>
        in
        let timings =
          try Util.File.string_of_file (Filename.concat dir "timings")
          with _ -> ""
        in
        let build_link =
          if Sys.file_exists (Filename.concat dir "build.html") then
            let lnk = Filename.basename dir ^"/build.html" in
            <:html<<a href="$str:lnk$" title="$str:timings$">$str:name$</a>&>>
          else
            <:html<<a title="$str:timings$">$str:name$</a>&>>
        in
        <:html<<tr>
          <th>$build_link$</th>
          $switches$
        </tr>
        $status_line$&>>)
      switch_details
      |> Html.concat
  in
  <:html<
    <html>
      <head>
        <title>Operf-macro benchmark results visualization</title>
        <style type="text/css">$str:css$</style>
      </head>
      <body>
        <h1>Operf-macro benchmark results visualization</h1>
        <h3>Plot a given benchmark</h3>
          <ul class="benches">$list:plots$</ul>
        <h3>Compare two runs</h3>
        <form action="compare">
          <div style="position:fixed; bottom: 20px; right: 20px;">
             <input type="submit" value="Compare"/>
          </div>
          <table class="index">
            $thead$
            <tbody>$lines$</tbody>
          </table>
        </form>
      </body>
    </html>
  >>

open Lwt
open Cohttp
open Cohttp_lwt_unix

let split c s =
  try
    let i = String.rindex s c in
    String.sub s 0 i, String.sub s (i+1) (String.length s - i - 1)
  with Not_found -> s, ""

let serve basedir uri path args = match path with
  | "/compare" ->
    (try
       let dirref, swref = split '/' (List.assoc "reference" args) in
       let dirtes, swtes = split '/' (List.assoc "test" args) in
       let page =
         gen_full_page
           (Filename.concat basedir dirref, swref)
           (Filename.concat basedir dirtes, swtes)
       in
       Server.respond_string
         ~status:`OK
         ~body:(Html.to_string page) ()
     with Not_found ->
       let body =
         List.fold_left (fun acc (arg,value) ->
             Printf.sprintf "%s\n%S = %S" acc arg value)
           "Invalid comparison parameters:"
           args
       in
       Server.respond_error ~body ())
  | "/graph" ->
    (try
       let bench = List.assoc "bench" args in
       let svg = bench_graph basedir bench in
       let headers =
         Cohttp.Header.init_with "content-type" "image/svg+xml"
       in
       Server.respond_string ~headers
         ~status:`OK
         ~body:svg ()
     with Not_found ->
       let body =
         List.fold_left (fun acc (arg,value) ->
             Printf.sprintf "%s\n%S = %S" acc arg value)
           "Invalid graph parameters:"
           args
       in
       Server.respond_error ~body ())
  | f when Util.FS.is_file (Filename.concat basedir f) = Some true ->
    let headers =
      if Filename.check_suffix f ".html" then
        Cohttp.Header.init_with "content-type" "text/html"
      else
        Cohttp.Header.init_with "content-type" "text/plain"
    in
    Server.respond_file ~headers
      ~fname:(Server.resolve_local_file ~docroot:basedir ~uri) ()
  | "/" ->
    Server.respond_string
      ~status:`OK
      ~body:(Html.to_string (index basedir)) ()
  | _ ->
    Server.respond_error ~status:`Not_found ~body:"Page not found" ()

let method_filter meth (res,body) = match meth with
  | `HEAD -> return (res,`Empty)
  | _ -> return (res,body)

let handler basedir (ch,conn) req body =
  let uri = Cohttp.Request.uri req in
  let path = Uri.path uri in
  (* Log the request to the console *)
  Printf.printf "%s %s %s\n%!"
    (Cohttp.(Code.string_of_method (Request.meth req)))
    path
    (Sexplib.Sexp.to_string_hum (Conduit_lwt_unix.sexp_of_flow ch));
  match Request.meth req with
  | (`GET | `HEAD) as meth ->
    (try
       serve basedir uri path (List.map (fun (a,bl) -> a, String.concat "" bl) (Uri.query uri))
       >>= method_filter meth
     with e ->
       Printf.eprintf "ERR: %s %s\n%!"
         (Printexc.to_string e) (Printexc.get_backtrace ());
       Server.respond_error ~status:`Internal_server_error
         ~body:(Printexc.to_string e) ())
  | meth ->
    Server.respond_error ~status:`Method_not_allowed
      ~body:"Method not allowed" ()

let start_server basedir host port () =
  Printf.printf "Listening for HTTP request on: %s %d\n" host port;
  let config = Server.make ~callback:(handler basedir) () in
  Conduit_lwt_unix.init ~src:host ()
  >>= fun ctx ->
  let ctx = Cohttp_lwt_unix_net.init ~ctx () in
  Server.create ~ctx ~mode:(`TCP (`Port port)) config

let () =
  let usage () =
    prerr_endline "Arguments: [port number] (default 8081)";
    exit 2
  in
  let port =
    match Array.length Sys.argv with
    | 1 -> 8081
    | 2 -> (try int_of_string Sys.argv.(1) with Failure _ -> usage ())
    | _ -> usage ()
  in
  Lwt_main.run (start_server (Sys.getcwd ()) "0.0.0.0" port ())
