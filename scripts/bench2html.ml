open Cow
open Macroperf

let comparison_switch = "comparison+bench"
let result_switch = "flambda+bench"

let score ~result ~comparison =
  let r, c = Summary.Aggr.(result.mean, comparison.mean) in
  if r < c then 1. -. c /. r
  else r /. c -. 1.

let scorebar ~result ~comparison =
  let r, c = Summary.Aggr.(result.mean, comparison.mean) in
  let score = if r < c then r /. c -. 1. else 1. -. c /. r in
  let leftpercent = 50. +. 50. *. (min 0. score) in
  let rightpercent = 50. +. 50. *. (max 0. score) in
  let gradient = [
    "#ffffff", 0.;
    "#ffffff", leftpercent;
    "#00ff00", leftpercent;
    "#00ff00", 50.;
    "#ff0000", 50.;
    "#ff0000", rightpercent;
    "#ffffff", rightpercent;
    "#ffffff", 100.;
  ] in
  Printf.sprintf "min-width:300px;background:linear-gradient(to right,%s);border:1px solid #eee;"
    (String.concat "," (List.map (fun (c,p) -> Printf.sprintf "%s %.0f%%" c p) gradient))

let collect () =
  let bench_dirs = Util.FS.(List.filter is_dir_exn (ls ~prefix:true macro_dir)) in
  (* SSet.iter Summary.summarize_dir selectors; *)
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
        let bench_all, bench_html =
          SMap.fold (fun bench m (acc,html) ->
              try
                let comparison = SMap.find comparison_switch m in
                let result = SMap.find result_switch m in
                let score = score ~result ~comparison in
                if classify_float score <> FP_normal then acc, html else
                let td r =
                  let open Summary.Aggr in
                  let tooltip = Printf.sprintf "%d runs, stddev %.0f" r.runs r.stddev in
                  <:html< <td style="text-align:right;" title="$str:tooltip$">
                            $str:Printf.sprintf "%.0f" r.mean$
                          </td>&>>
                in
                score::acc,
                <:html<$html$
                         <tr>
                            <td>$str:bench$</td>
                            <td style="$str:scorebar ~result ~comparison ^ "text-align:right;"$">
                              $str:Printf.sprintf "%+0.2f" score$
                            </td>
                            $td result$
                            $td comparison$
                         </tr>&>>
              with Not_found -> acc, html)
            m ([],<:html<&>>)
        in
        let avgscore = List.fold_left (+.) 0. bench_all /.
                       float (List.length bench_all) in
        <:html<$html$
               <tr style="background: #cce;">
                 <th style="text-align:left;">$str:Topic.to_string topic$</th>
                 <td style="text-align:right;">$str:Printf.sprintf "%+0.2f" avgscore$</td>
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
  let title = "Operf-macro comparison, flambda "^Sys.argv.(1) in
  let html =
    <:html< <html><head><title>$str:title$</title></head>
                  <body>
                    <h1>$str:title$</h1>
                    $table$
                  </body>
            </html>&>>
  in
  output_string stdout (Html.to_string html)
