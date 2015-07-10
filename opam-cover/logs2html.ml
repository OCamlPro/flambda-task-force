module J = Yojson.Basic
module JU = J.Util

type pkg = string * string

type action = Build | Install | Remove

type status =
  | Ok
  | Failed of string * int * string list * string list
  (* cmd, code, stdout, stderr *)
  | Aborted of (pkg * action) list

type result = {
  status: status;
  duration: float;
  run: string;
}

let (%) j f = List.assoc f (JU.to_assoc j)

let is_prefix pre s =
  let pl = String.length pre in
  String.length s >= pl && String.sub s 0 pl = pre

let extension s =
  try
    let i = String.rindex s '.' in
    String.sub s (i+1) (String.length s - i - 1)
  with Not_found -> ""

let parse_pkg j =
  let a = JU.to_assoc j in
  JU.to_string (List.assoc "name" a), JU.to_string (List.assoc "version" a)

let parse_action: J.json -> pkg * action = function
  | `Assoc ["build",p] -> parse_pkg p, Build
  | `Assoc ["install",p] -> parse_pkg p, Install
  | `Assoc ["remove",p] -> parse_pkg p, Remove

let parse_status: J.json -> status = function
  | `String "OK" -> Ok
  | `Assoc ["aborted", `List a] ->
    Aborted (List.map parse_action a)
  | `Assoc ["process-error", e] ->
    Failed (JU.to_string (e%"info"%"command"),
            (match e%"code" with
             | `String s -> int_of_string s
             | `Int i -> i
             | _ -> failwith "bad return code"),
            List.map JU.to_string (JU.to_list (e%"stdout")),
            List.map JU.to_string (JU.to_list (e%"stderr")))

let parse_result run r =
  parse_action (r%"action"),
  { status = parse_status (r%"result");
    run;
    duration = try JU.to_float (r%"duration") with Not_found -> 0.
  }

let results run f =
  let f = JU.to_assoc (J.from_file f) in
  try
    let r = JU.to_list (List.assoc "results" f) in
    List.map (parse_result run) r
  with Not_found -> []

module M = Map.Make(struct
    type t = pkg * action
    let compare = compare
  end)

let files pfx ext =
  let files = Array.to_list (Sys.readdir Filename.current_dir_name) in
  let files =
    List.filter (fun f -> is_prefix pfx f && extension f = ext) files
  in
  List.sort compare files

let all_results pfx =
  List.fold_left (fun acc f ->
      let run = Filename.chop_extension f in
      let r = results run f in
      Printf.eprintf "read %s: %d results\n" f (List.length r);
      List.fold_left (fun acc (a,r) -> M.add a r acc) acc r)
    M.empty (files pfx "json")

module S = Set.Make(String)
module SM = Map.Make (String)

let fold_lines f acc file =
  let ic = open_in file in
  let rec scan acc =
    match input_line ic with
    | exception End_of_file -> close_in ic; acc
    | s -> scan (f acc s)
  in
  scan acc

let sizes pfx =
  List.fold_left
    (fold_lines (fun acc s ->
         try Scanf.sscanf s "[ %d] %s" (fun sz f -> SM.add f sz acc)
         with Scanf.Scan_failure _ -> acc))
    SM.empty (files ("files-"^pfx) "list")

let byte_files pfx =
  List.fold_left (fold_lines (fun acc s -> S.add s acc))
    S.empty (files ("byteexec-"^pfx) "list")

type 'a lib_size = { total: 'a; cmxs: 'a; cmx: 'a; cmxa: 'a; a: 'a; }

let lib_empty = { total = 0; cmxs = 0; cmx = 0; cmxa = 0; a = 0 }

let ls_map2 f a b =
  { total = f a.total b.total;
    cmxs = f a.cmxs b.cmxs;
    cmx = f a.cmx b.cmx;
    cmxa = f a.cmxa b.cmxa;
    a = f a.a b.a; }

let add_to_lib_size sz f size =
  let sz = {sz with total = sz.total + size} in
  match extension f with
  | "cmxs" -> {sz with cmxs = sz.cmxs + size}
  | "cmx"  -> {sz with cmx  = sz.cmx  + size}
  | "cmxa" -> {sz with cmxa = sz.cmxa + size}
  | "a"    -> {sz with a    = sz.a    + size}
  | _      -> sz

let lib_size_to_string f sz =
  let f () = f in
  Printf.sprintf
    "<a title=\"cmx: %a, cmxa: %a, cmxs: %a, a: %a\">%a</a>"
    f sz.cmx f sz.cmxa f sz.cmxs f sz.a f sz.total

let lib_sizes s =
  SM.fold (fun f size acc ->
      try
        let lib, f = Scanf.sscanf f "lib/%s@/%s" (fun lib f -> lib, f) in
        let sz = try SM.find lib acc with Not_found -> lib_empty in
        SM.add lib (add_to_lib_size sz f size) acc
      with Scanf.Scan_failure _ -> acc)
    s SM.empty

let html_head title =
  Printf.sprintf
    "<!DOCTYPE html>\n<html>\n<head>\n\
    \  <title>%s</title>\n\
    \  <script src=\"http://www.kryogenix.org/code/browser/sorttable/sorttable.js\"></script>\n\
    \  <style type=\"text/css\"><!--\n\
    \     div {padding:3ex;}\n\
    \     pre {padding:1ex;border:1px solid grey;background-color:#eee;}\n\
    \     table {border-collapse:collapse;margin:auto;}\n\
    \     thead {position:-webkit-sticky;position:-moz-sticky;position:sticky;\
                 top:0;}\n\
    \     tfoot {position:-webkit-sticky;position:-moz-sticky;position:sticky;\
                 bottom:0;}\n\
    \     thead th {background-color:#dde;}
    \     td {text-align: right;}\n\
    \     tr:nth-child(odd) {background-color:#eef;}\n\
    \     th, td {padding:2ex; border:1px solid #e0e0e0;}\n\
    \     .logs {display:none;}\n\
    \     .logs:target {display:block;position:fixed;top:5%%;left:5%%;\
                        right:5%%;bottom:5%%;border:1px solid black;\
                        background-color:white;overflow:scroll;z-index:10;}\n\
    \     .close {display:block;position:fixed;top:7%%;right:7%%;}\n\
    \  --></style>\n\
     </head>"
    title

let escape s =
  let s = Re.replace_string (Re.compile (Re.char '&')) ~by:"&amp;" s in
  let s = Re.replace_string (Re.compile (Re.char '<')) ~by:"&lt;" s in
  s

let html_status logs name version sw = function
  | Some {status = Ok; _} -> logs, "OK"
  | Some {status = Aborted deps; _} ->
    let causes = List.map (fun ((n,v),_) -> Printf.sprintf "%s.%s" n v) deps in
    logs,
    Printf.sprintf "<a title=\"Failed dependencies: %s\">Aborted</a>"
      (String.concat ", " causes)
  | Some {status = Failed (cmd,i,stdout,stderr); _} ->
    let id = Printf.sprintf "log-%s-%s-%s" sw name version in
    Printf.sprintf
      "<div class=\"logs\" id=\"%s\">\n\
       <a class=\"close\" href=\"#close\">Close</a>\n\
       <h3>Error on %s.%s (%s)</h3>\n\
       <p>Command: <pre>%s</pre></p>
       <h4>Stdout</h4><pre>%s</pre>\n\
       <h4>Stderr</h4><pre>%s</pre>\n\
       </div>\n"
      id name version sw
      (escape cmd)
      (escape (String.concat "\n" stdout))
      (escape (String.concat "\n" stderr))
    :: logs,
    Printf.sprintf "<a href=\"#%s\">Failure (%d)</a>" id i
  | None -> logs, "-"

let () =
  let comparison = all_results "comparison" in
  let flambda = all_results "flambda" in
  let lib_sizes_comparison =
    List.fold_left (fun acc file ->
        let run = Filename.chop_extension file in
        SM.add run (lib_sizes (sizes run)) acc
      ) SM.empty (files "comparison" "json")
  in
  let lib_sizes_flambda =
    List.fold_left (fun acc file ->
        let run = Filename.chop_extension file in
        SM.add run (lib_sizes (sizes run)) acc
      ) SM.empty (files "flambda" "json")
  in
  let m = M.merge (fun _ c f -> Some (c,f)) comparison flambda in
  Printf.printf "%s\n<body><div><table class=\"sortable\">\
                 <thead><tr><th>Package</th><th>reference</th><th>flambda</th>\
                 <th>ref time (s)</th><th>flambda time(s)</th><th>ratio</th>\
                 <th>ref lib size (KB)</th><th>flambda lib size (KB)</th>\
                 <th>size ratio</th></tr></thead><tbody>\n"
    (html_head ("FLambda comparison " ^ Filename.basename (Sys.getcwd ())));
  let full_line =
    Printf.printf "<tr><th>%s</th><td>%s</td><td>%s</td>\
                   <td>%.3f</td><td>%.3f</td><td>%.2fx</td>\
                   <td>%s</td><td>%s</td><td>%s</td></tr>\n"
  in
  let short_line =
    Printf.printf "<tr><th>%s.%s</th><td>%s</td><td>%s</td>\
                   <td>%s</td><td>%s</td>\
                   <td></td><td></td><td></td><td></td></tr>\n"
  in
  let print_sz i = Printf.sprintf "%d.%02d" (i/1000) (i mod 1000 / 10) in
  let dft d o f = match o with None -> d | Some x -> f x in
  let (total_c, total_f, time_c, time_f, sz_c, sz_f), logs =
    M.fold (fun ((name,version),a) (c,f) (totals,logs) ->
        match a with
        | Install | Remove -> totals,logs
        | Build ->
          match c,f with
          | Some ({status = Ok} as c), Some ({status = Ok} as f) ->
            let sz_comp =
              try SM.find name (SM.find c.run lib_sizes_comparison)
              with Not_found -> lib_empty
            in
            let sz_flam =
              try SM.find name (SM.find f.run lib_sizes_flambda)
              with Not_found -> lib_empty
            in
            full_line (name^"."^version) "OK" "OK"
            (c.duration) (f.duration)
            (f.duration /. c.duration)
            (lib_size_to_string print_sz sz_comp)
            (lib_size_to_string print_sz sz_flam)
            (lib_size_to_string (Printf.sprintf "%.2f")
               (ls_map2 (fun a b -> float_of_int a /. float_of_int b)
                  sz_flam sz_comp));
            let stc,stf,tc,tf,szc,szf = totals in
            (stc + 1, stf + 1, tc +. c.duration, tf +. f.duration,
             ls_map2 (+) szc sz_comp,
             ls_map2 (+) szf sz_flam),
            logs
          | _ ->
            let logs, status_c = html_status logs name version "comparison" c in
            let logs, status_f = html_status logs name version "flambda" f in
            short_line name version status_c status_f
              (dft "" c @@ fun r ->
               match r.status with Aborted _ -> "" | _ ->
                 Printf.sprintf "%.3f" r.duration)
              (dft "" f @@ fun r ->
               match r.status with Aborted _ -> "" | _ ->
                 Printf.sprintf "%.3f" r.duration);
            let stc,stf,tc,tf,szc,szf = totals in
            let ts = function Some {status = Ok; _} -> 1 | _ -> 0 in
            (stc + ts c, stf + ts f, tc, tf, szc, szf),
            logs
      )
      m ((0,0,0.,0.,lib_empty,lib_empty),[])
  in
  Printf.printf "</tbody><tfoot>\n";
  full_line "TOTAL"
    (Printf.sprintf "%d Ok" total_c) (Printf.sprintf "%d Ok" total_f)
    time_c time_f (time_f /. time_c)
    (lib_size_to_string print_sz sz_c)
    (lib_size_to_string print_sz sz_f)
    (lib_size_to_string (Printf.sprintf "%.2f")
       (ls_map2 (fun a b -> float_of_int a /. float_of_int b) sz_f sz_c));
  Printf.printf "</tfoot></table>\n</div>\n";
  List.iter print_endline logs;
  Printf.printf "<div><table class=\"sortable\"><thead>\
                 <tr><th>Binary</th><th>kind</th><th>ref size (KB)</th>\
                 <th>flambda size (KB)</th><th>ratio</th></tr></thead>\
                 <tbody>\n";
  let tot_c, tot_f =
    let byte = byte_files "comparison" in
    SM.fold (fun f (szc, szf) (tot_c, tot_f) ->
        if is_prefix "bin/" f then (
          let isbyte = S.mem f byte in
          Printf.printf
            "<tr><th>%s</th>\
             <td>%s</td><td>%s</td><td>%s</td><td>%.2f</td></tr>\n"
            (String.sub f 4 (String.length f - 4))
            (if isbyte then "byte" else "")
            (print_sz szc) (print_sz szf)
            (float_of_int szf /. float_of_int szc);
          if isbyte then tot_c, tot_f
          else tot_c + szc, tot_f + szf)
        else
          tot_c, tot_f
      )
      (SM.merge (fun _ a b -> match a,b with
           | Some a, Some b -> Some (a,b)
           | _ -> None)
          (sizes "comparison") (sizes "flambda"))
      (0,0);
  in
  Printf.printf "</tbody><tfoot><tr><th>TOTAL (native only)</th>\
                 <td>%s</td><td></td><td>%s</td><td>%.2f</td></tr>\n\
                 </tfoot></table></div>"
    (print_sz tot_c) (print_sz tot_f) (float_of_int tot_f /. float_of_int tot_c);
  Printf.printf "</body></html>\n"
