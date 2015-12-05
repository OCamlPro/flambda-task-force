open Cow
open Macroperf

let short_switch_name sw =
  try String.sub sw 0 (String.index sw '@') with Not_found -> sw

let ( @* ) g f x = g (f x)

let ignored_topics = Topic.([
  Topic (Gc.Heap_words, Gc);
  Topic (Gc.Heap_chunks, Gc);
  Topic (Gc.Live_words, Gc);
  Topic (Gc.Live_blocks, Gc);
  Topic (Gc.Free_words, Gc);
  Topic (Gc.Free_blocks, Gc);
  Topic (Gc.Largest_free, Gc);
  Topic (Gc.Fragments, Gc);
  Topic (Size.Full, Size);
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
  let leftpercent, rightpercent = match topic with
    | Topic.Topic (gc, Topic.Gc) when gc = Topic.Gc.Promoted_words ->
      if score < 1. then 50., 100. -. 50. *. score
      else 100. -. 50. *. score -. 1., 50.
    | _ ->
      if score < 1. then 50., 100. -. 50. *. score
      else 50. /. score, 50.
  in
  let gradient = [
    "transparent", 0.;
    "transparent", leftpercent;
    "#ff5555", leftpercent;
    "#ff5555", 50.;
    "#55ff88", 50.;
    "#55ff88", rightpercent;
    "transparent", rightpercent;
    "transparent", 100.;
  ] in
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

let get_bench_error macrodir switch bench =
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

let collect macrodir comparison_switch result_switch =
  let bench_dirs = Util.FS.(List.filter is_dir_exn (ls ~prefix:true macrodir)) in
  (* Refresh summary files, which may be needed sometimes *)
  SSet.iter Summary.summarize_dir (SSet.of_list bench_dirs);
  let data_by_bench =
    List.fold_left (fun acc dir -> DB.of_dir ~acc dir) DB.empty bench_dirs
  in
  let data_by_topic =
    DB.fold_data
      (fun bench context_id topic -> DB2.add topic bench context_id)
      data_by_bench DB2.empty
  in
  let logkey ~switch ~bench = "log-" ^ switch ^"-"^ bench in
  let logs, avgscores, table_contents =
    TMap.fold (fun topic m (logs,avgscores,html) ->
        if List.mem topic ignored_topics then logs,avgscores,html else
        let bench_all, logs, bench_html =
          SMap.fold (fun bench m (acc,logs,html) ->
              let open Summary.Aggr in
              let comparison = try Some (SMap.find comparison_switch m) with Not_found -> None in
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
              let td logs swname = function
                | Some ({success = true; _} as r) ->
                  let tooltip = Printf.sprintf "%d runs, stddev %s" r.runs (print_float r.stddev) in
                  logs,
                  <:html<<td title="$str:tooltip$">$str:print_float r.mean$</td>&>>
                | Some ({success = false; _}) ->
                  let k = logkey ~switch:swname ~bench in
                  (if SMap.mem k logs then logs
                   else try SMap.add k (get_bench_error macrodir swname bench) logs with _ -> logs),
                  <:html<<td class="error"><a href="$str:"#"^k$">ERR(run)</a></td>&>>
                | None ->
                  logs,
                  <:html<<td>-</td>&>>
              in
              let logs, td_result = td logs result_switch result in
              let logs, td_compar = td logs comparison_switch comparison in
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
      data_by_topic (SMap.empty, TMap.empty, <:html<&>>)
  in
  let table = <:html<
    <table>
       <thead><tr>
         <th>Benchmark</th>
         <th>Relative score</th>
         <th>$str:short_switch_name result_switch$</th>
         <th>$str:short_switch_name comparison_switch$</th>
       </tr></thead>
       <tbody>
         $table_contents$
       </tbody>
    </table>
  >> in
  let summary_table =
    let topics =
      TSet.of_list (List.map fst (TMap.bindings data_by_topic))
    in
    let topics =
      List.fold_left (fun acc t -> TSet.remove t acc) topics ignored_topics
    in
    let titles =
      TSet.fold (fun t html ->
          let rec sp s =
            try Bytes.set s (Bytes.index s '_') ' '; sp s
            with Not_found -> s
          in
          <:html<$html$
                 <th class="scorebar-small">
                   $str:sp (Topic.to_string t)$
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
            try (SMap.find comparison_switch ctx_map).Summary.data
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
                  let k = logkey ~switch:result_switch ~bench in
                  if SMap.mem k logs then
                    <:html<$html$<td class="error"><a href="$str:"#"^k$">fail</a></td>&>>
                  else
                    <:html<$html$<td>-</td>&>>)
              topics <:html<&>>
          in
          <:html<$html$
                 <tr>
                   <th>$str:bench$</th>
                   $topics$
                 </tr>
          >>)
        data_by_bench <:html<&>>
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
    SMap.fold (fun id (stdout, stderr) html ->
        <:html< $html$
                <div class="logs" id="$str:id$">
                  <a class="close" href="#">Close</a>
                  <h3>Error running bench $str:id$</h3>
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
    .error {
      background-color: #dd6666;
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
"

let hashcol hash =
  if String.length hash >= 6 then
    int_of_string ("0x"^String.sub hash 0 6)
    lor 0x808080
    |> Printf.sprintf "#%06x"
  else "white"

let gen_full_page macrodir comparison_switch result_switch =
  let table = collect macrodir comparison_switch result_switch in
  let sw_name sw = Filename.chop_suffix sw "+bench" in
  let sw_hash sw =
    try
      Util.File.string_of_file
        Filename.(concat macrodir (sw_name sw) ^ ".hash")
      |> String.trim
    with _ -> "?"
  in
  let sw_params sw =
    try
      Util.File.string_of_file
        Filename.(concat macrodir (sw_name sw) ^ ".params")
      |> String.trim
    with _ -> ""
  in
  let cmp_hash = sw_hash comparison_switch in
  let cmp_params = sw_params comparison_switch in
  let res_hash = sw_hash result_switch in
  let res_params = sw_params result_switch in
  let title =
    Printf.sprintf "Comparing %s@%s with %s@%s (%s)"
      result_switch res_hash comparison_switch cmp_hash
      (Filename.basename macrodir)
  in
  let cmp_hashstyle =
    Printf.sprintf
      "background-color:%s;font-size:130%;font-family:monospace"
      (hashcol cmp_hash)
  in
  let res_hashstyle =
    Printf.sprintf
      "background-color:%s;font-size:130%;font-family:monospace"
      (hashcol res_hash)
  in
  <:html<
    <html>
      <head>
        <title>Operf-macro, $str:title$</title>
        <style type="text/css">$str:css$</style>
      </head>
      <body>
        <h1>Operf-macro comparison</h1>
        <table>
          <tr><th>Comparing</th>
              <td>$str:sw_name result_switch$</td>
              <td style="$str:res_hashstyle$">$str:res_hash$</td>
              <td style="text-align:left;font-family:monospace">$str:res_params$</td></tr>
          <tr><th>Against</th>
              <td>$str:sw_name comparison_switch$</td>
              <td style="$str:cmp_hashstyle$">$str:cmp_hash$</td>
              <td style="text-align:left;font-family:monospace">$str:cmp_params$</td></tr>
        </table>
        <p>For all the measures below, smaller is better</p>
        <p>Promoted words are measured as a ratio or minor words,
           and compared linearly with the reference</p>
        $table$
      </body>
    </html>
  >>

let index basedir =
  let dirs = Util.FS.(List.filter is_dir_exn (ls ~prefix:true basedir)) in
  let dirs =
    List.filter (fun d -> Sys.file_exists (Filename.concat d "summary.csv"))
      dirs
  in
  let dirs = List.sort compare dirs in
  let dirs_switches =
    List.fold_left (fun acc d ->
        let switches =
          Util.FS.fold_files (fun switches f ->
              if Filename.check_suffix f ".result" then
                SSet.add Filename.(basename (chop_extension f)) switches
              else switches)
            SSet.empty
            d
        in
        (d, switches) :: acc)
      [] dirs
  in
  let all_switches =
    List.fold_left (fun acc (d, switches) -> SSet.union acc switches)
      SSet.empty dirs_switches
  in
  let switch_details =
    List.map (fun (d, switches) ->
        let hashes =
          List.fold_left (fun acc swname ->
              let hash =
                try
                  String.trim @@
                  Util.File.string_of_file
                    Filename.(concat d @@ chop_suffix swname "+bench" ^ ".hash")
                with _ -> "XXX"
              in
              SMap.add swname (if hash = "" then "XXX" else hash) acc
            )
            SMap.empty (SSet.elements switches)
        in
        d, hashes)
      dirs_switches
  in
  let thead =
    let sws =
      SSet.fold (fun s acc ->
          <:html<<th>$str:s$</th>&>> :: acc
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
    List.map (fun (dir,swmap) ->
        let switches =
          SSet.fold (fun sw acc ->
              try
                let hash = SMap.find sw swmap in
                let value = Filename.basename dir ^"/"^ sw in
                let hash_style =
                  Printf.sprintf
                    "background-color:%s;font-size:130%%;font-family:monospace;"
                    (hashcol hash)
                in
                <:html<
                  <td>
                    <span style="$str:hash_style$">$str:hash$</span>
                    <small>
                      [<input type="radio" name="test" value="$str:value$"/>Test |
                       <input type="radio" name="reference" value="$str:value$"/>Ref]
                    </small>
                  </td>&>>
                ::acc
              with Not_found ->
                <:html<<td></td>&>> :: acc
            )
            all_switches []
        in
        let name = Filename.basename dir in
        let name =
          if String.length name > 15 then String.sub name 0 15 else name
        in
        let switches = Html.concat (List.rev switches) in
        let build_link = Filename.basename dir ^"/build.html" in
        <:html<<tr>
          <th><a href="$str:build_link$">$str:name$</a></th>
          $switches$
        </tr>&>>)
      switch_details
    |> Html.concat
  in
  <:html<
    <html>
      <head>
        <title>Operf-macro flambda runs</title>
        <style type="text/css">$str:css$</style>
      </head>
      <body>
        <h1>Operf-macro flambda runs</h1>
        <form action="compare">
          <div style="position:fixed; top: 20px; right: 20px;">
             <input type="submit" value="Compare"/>
          </div>
          <table>
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
       if dirref <> dirtes then
         Server.respond_error ~body:"Comparison accross runs unsupported yet" ()
       else
         let page =
           gen_full_page (Filename.concat basedir dirref) swref swtes
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
  | f when Util.FS.is_file (Filename.concat basedir f) = Some true ->
    Server.respond_file ~fname:(Server.resolve_local_file ~docroot:basedir ~uri) ()
  | _ ->
    Server.respond_string
      ~status:`OK
      ~body:(Html.to_string (index basedir)) ()

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
