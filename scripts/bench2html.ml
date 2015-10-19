open Cow
open Macroperf

let title = Sys.argv.(1)
let comparison_switch = if Array.length Sys.argv < 3 then "comparison+bench" else Sys.argv.(2)
let result_switch = if Array.length Sys.argv < 4 then "flambda+bench" else Sys.argv.(3)

let short_switch_name sw =
  try String.sub sw 0 (String.index sw '@') with Not_found -> sw

let ( @* ) g f x = g (f x)

let ignored_topics = [
  "heap_words"; "heap_chunks";
  "live_words"; "live_blocks";
  "free_words"; "free_blocks";
  "largest_free"; "fragments";
]

let score ~result ~comparison =
  let open Summary.Aggr in
  if result.mean = comparison.mean then 1.
  else result.mean /. comparison.mean

let print_score score =
  let percent = score *. 100. -. 100. in
  Printf.sprintf "%+.*f%%"
    (max 0 (2 - truncate (log10 (abs_float percent))))
    percent

let scorebar ~result ~comparison =
  let r, c = Summary.Aggr.(result.mean, comparison.mean) in
  let score = if r < c then 1. -. r /. c else c /. r -. 1. in
  let leftpercent = 50. +. 50. *. (min 0. score) in
  let rightpercent = 50. +. 50. *. (max 0. score) in
  let gradient = [
    "transparent", 0.;
    "transparent", leftpercent;
    "#ff0000", leftpercent;
    "#ff0000", 50.;
    "#00ff00", 50.;
    "#00ff00", rightpercent;
    "transparent", rightpercent;
    "transparent", 100.;
  ] in
  Printf.sprintf "background:linear-gradient(to right,%s);"
    (String.concat "," (List.map (fun (c,p) -> Printf.sprintf "%s %.0f%%" c p) gradient))

(* adds _ separators every three digits for readability *)
let print_float f =
  if classify_float f <> FP_normal then Printf.sprintf "%.3f" f else
  let rec split f =
    if abs_float f >= 1000. then
      mod_float (abs_float f) 1000. ::
      split (f /. 1000.)
    else [f]
  in
  match split f with
  | [] -> assert false
  | [f] -> Printf.sprintf "%.3f" f
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
  | Topic.Topic (_, Topic.Time) -> Some "ns"
  | Topic.Topic (_, Topic.Size) -> Some "bytes"
  | _ -> None

let get_bench_error switch bench =
  let res = Result.load_conv_exn Util.FS.(macro_dir / bench / switch ^ ".result") in
  match
    List.fold_left (fun acc -> function
        | `Ok {Execution.process_status = Unix.WEXITED 0} -> acc
        | `Ok ({Execution.process_status = _} as ex) -> Some ex
        | _ -> None)
      None res.Result.execs
  with
  | Some ex -> Execution.(ex.stdout, ex.stderr)
  | None -> raise Not_found

let collect () =
  let bench_dirs = Util.FS.(List.filter is_dir_exn (ls ~prefix:true macro_dir)) in
  (* Refresh summary files, which may be needed sometimes *)
  SSet.iter Summary.summarize_dir (SSet.of_list bench_dirs);
  let data1 =
    List.fold_left (fun acc dir -> DB.of_dir ~acc dir) DB.empty bench_dirs
  in
  let data2 =
    DB.fold_data
      (fun bench context_id topic -> DB2.add topic bench context_id)
      data1 DB2.empty
  in
  let logkey ~switch ~bench = "log-" ^ switch ^"-"^ bench in
  let logs, table_contents =
    TMap.fold (fun topic m (logs,html) ->
        if List.mem (Topic.to_string topic) ignored_topics then logs,html else
        let bench_all, logs, bench_html =
          SMap.fold (fun bench m (acc,logs,html) ->
              let open Summary.Aggr in
              let comparison = try Some (SMap.find comparison_switch m) with Not_found -> None in
              let result = try Some (SMap.find result_switch m) with Not_found -> None in
              let acc, scorebar =
                match comparison, result with
                | Some ({success = true; _} as comparison),
                  Some ({success = true; _} as result) ->
                  let score = score ~result ~comparison in
                  (match classify_float (log score) with
                   | FP_nan | FP_infinite -> acc
                   | _ -> score :: acc),
                  <:html<<td class="scorebar" style="$str:scorebar ~result ~comparison$">
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
                   else try SMap.add k (get_bench_error swname bench) logs with _ -> logs),
                  <:html<<td class="error"><a href="$str:"#"^k$">ERR(run)</a></td>&>>
                | None ->
                  logs,
                  <:html<<td class="error">ERR(build)</td>&>>
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
        let avgscore =
          exp @@
          List.fold_left (fun acc s -> acc +. log s) 0. bench_all /.
          float (List.length bench_all)
        in
        let unit =
          match topic_unit topic with
          | Some u -> Printf.sprintf " (%s)" u
          | None -> ""
        in
        logs,
        <:html<$html$
               <tr class="bench-topic">
                 <th>$str:Topic.to_string topic$$str:unit$</th>
                 <td>$str:print_score avgscore$</td>
                 <td></td>
                 <td></td>
               </tr>
               $bench_html$>>)
      data2 (SMap.empty, <:html<&>>)
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
  <:html< <table>
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
          $html_logs$&>>

let css = "
    table {
      margin: auto;
      //border-collapse: collapse;
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
      //border: 1px solid #e5e5e5;
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

    # For error logs
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

let () =
  let table = collect () in
  let html =
    <:html<
      <html>
        <head>
          <title>Operf-macro, $str:title$</title>
          <style type="text/css">$str:css$</style>
        </head>
        <body>
          <h1>Operf-macro comparison</h1>
          <h3>$str:title$</h3>
          <p>For all the measures below, smaller is better</p>
          $table$
        </body>
      </html>
    >>
  in
  output_string stdout (Html.to_string html)
