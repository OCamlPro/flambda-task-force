open Cow
open Macroperf

let title = Sys.argv.(1)
let comparison_switch = if Array.length Sys.argv < 3 then "comparison+bench" else Sys.argv.(2)
let result_switch = if Array.length Sys.argv < 4 then "flambda+bench" else Sys.argv.(3)

let ignored_topics = [
  "heap_words"; "heap_chunks";
  "live_words"; "live_blocks";
  "free_words"; "free_blocks";
  "largest_free"; "fragments";
]

let score ~result ~comparison =
  let r, c = Summary.Aggr.(result.mean, comparison.mean) in
  if r < c then c /. r -. 1.
  else 1. -. r /. c

let scorebar ~result ~comparison =
  let r, c = Summary.Aggr.(result.mean, comparison.mean) in
  let score = if r < c then 1. -. r /. c else c /. r -. 1. in
  let leftpercent = 50. +. 50. *. (min 0. score) in
  let rightpercent = 50. +. 50. *. (max 0. score) in
  let gradient = [
    "#ffffff", 0.;
    "#ffffff", leftpercent;
    "#ff0000", leftpercent;
    "#ff0000", 50.;
    "#00ff00", 50.;
    "#00ff00", rightpercent;
    "#ffffff", rightpercent;
    "#ffffff", 100.;
  ] in
  Printf.sprintf "min-width:300px;background:linear-gradient(to right,%s);border:1px solid #eee;"
    (String.concat "," (List.map (fun (c,p) -> Printf.sprintf "%s %.0f%%" c p) gradient))

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
  let table_contents =
    TMap.fold (fun topic m html ->
        if List.mem (Topic.to_string topic) ignored_topics then html else
        let bench_all, bench_html =
          SMap.fold (fun bench m (acc,html) ->
              let td r =
                let open Summary.Aggr in
                let tooltip = Printf.sprintf "%d runs, stddev %.0f" r.runs r.stddev in
                <:html< <td style="text-align:right;" title="$str:tooltip$">
                          $str:Printf.sprintf "%.0f" r.mean$
                        </td>&>>
              in
              let comparison = try Some (SMap.find comparison_switch m) with Not_found -> None in
              let result = try Some (SMap.find result_switch m) with Not_found -> None in
              match comparison, result with
              | (None | Some {Summary.Aggr.success = false;_}),
                (None | Some {Summary.Aggr.success = false;_}) ->
                acc,
                <:html<$html$<tr><td>$str:bench$</td>
                       <td style="background-color:#ffff00; text-align:center">ERR</td>
                       <td style="text-align:right">-</td>
                       <td style="text-align:right">-</td>
                       </tr>&>>
              | Some ({Summary.Aggr.success = true;_} as comparison),
                (None | Some {Summary.Aggr.success = false;_}) ->
                acc,
                <:html<$html$<tr><td>$str:bench$</td>
                       <td style="background-color:#ff0000; text-align:center">ERR</td>
                       $td comparison$
                       <td style="text-align:right">-</td>
                       </tr>&>>
              | (None | Some {Summary.Aggr.success = false;_}),
                Some ({Summary.Aggr.success = true;_} as result) ->
                acc,
                <:html<$html$<tr><td>$str:bench$</td>
                       <td style="background-color:#00ff00; text-align:center">ERR</td>
                       <td style="text-align:right">-</td>
                       $td result$
                       </tr>&>>
              | Some comparison, Some result ->
                let score = score ~result ~comparison in
                let score = if classify_float score = FP_nan then 0. else score in
                (if classify_float score = FP_infinite then acc else score::acc),
                <:html<$html$
                         <tr>
                            <td>$str:bench$</td>
                            <td style="$str:scorebar ~result ~comparison ^ "text-align:right;"$">
                              $str:Printf.sprintf "%+0.3f" score$
                            </td>
                            $td result$
                            $td comparison$
                         </tr>&>>)
            m ([],<:html<&>>)
        in
        let avgscore = List.fold_left (+.) 0. bench_all /.
                       float (List.length bench_all) in
        <:html<$html$
               <tr style="background: #cce;">
                 <th style="text-align:left;">$str:Topic.to_string topic$</th>
                 <td style="text-align:right;">$str:Printf.sprintf "%+0.3f" avgscore$</td>
                 <td></td>
                 <td></td>
               </tr>
               $bench_html$>>)
      data2 <:html<&>>
  in
  <:html< <table style="margin:auto;border-collapse:collapse;">
            <thead><tr>
              <th>Benchmark</th>
              <th>Relative score</th>
              <th>Absolute score</th>
              <th>Reference score</th>
            </tr></thead>
            <tbody>
              $table_contents$
            </tbody>
          </table>&>>

let () =
  let table = collect () in
  let html =
    <:html< <html><head><title>Operf-macro, $str:title$</title></head>
                  <body>
                    <h1>Operf-macro comparison</h1>
                    <h3>$str:title$</h3>
                    $table$
                  </body>
            </html>&>>
  in
  output_string stdout (Html.to_string html)
