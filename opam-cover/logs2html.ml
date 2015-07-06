module J = Yojson.Basic
module JU = J.Util

type pkg = string * string

type action = Build | Install | Remove

type status = Ok | Failed of string * int | Aborted

type result = {
  status: status;
  duration: float;
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
  | `String "aborted" -> Aborted
  | `Assoc ["process-error", e] ->
    Failed (JU.to_string (e%"info"%"command"),
            match e%"code" with
            | `String s -> int_of_string s
            | `Int i -> i
            | _ -> failwith "bad return code")

let parse_result r =
  parse_action (r%"action"),
  { status = parse_status (r%"result");
    duration = try JU.to_float (r%"duration") with Not_found -> 0.;
  }

let string_of_status = function
  | Ok -> "OK"
  | Failed (_,i) -> Printf.sprintf "Failure (%d)" i
  | Aborted -> "Aborted"

let results f =
  let f = JU.to_assoc (J.from_file f) in
  try
    let r = JU.to_list (List.assoc "results" f) in
    List.map parse_result r
  with Not_found -> []

module M = Map.Make(struct
    type t = pkg * action
    let compare = compare
  end)

let all_results pfx =
  let files = Array.to_list (Sys.readdir Filename.current_dir_name) in
  let files =
    List.filter (fun f -> is_prefix pfx f && extension f = "json") files
  in
  List.fold_left (fun acc f ->
      let r = results f in
      Printf.eprintf "read %s: %d results\n" f (List.length r);
      List.fold_left (fun acc (a,r) -> M.add a r acc) acc r)
    M.empty (List.sort compare files)

module SM = Map.Make (String)

let sizes pfx =
  let files = Array.to_list (Sys.readdir Filename.current_dir_name) in
  let files =
    let pfx = "files-"^pfx in
    List.filter (fun f -> is_prefix pfx f && extension f = "list") files
  in
  List.fold_left (fun acc f ->
      let ic = open_in f in
      let rec scan acc =
        match input_line ic with
        | exception End_of_file -> acc
        | s ->
          scan @@
          try Scanf.sscanf s "[ %d] %s" (fun sz f -> SM.add f sz acc)
          with Scanf.Scan_failure _ -> acc
      in
      let acc = scan acc in
      close_in ic;
      acc)
    SM.empty (List.sort compare files)

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
    "<a title=\"cmx: %a, cmxa: %a, cmxs: %a, a: %a)\">%a</a>"
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
    \     table { border-collapse: collapse; margin: auto; }\n\
    \     thead {position:-webkit-sticky;position:-moz-sticky;position:sticky;\
                 top:0;}\n\
    \     tfoot {position:-webkit-sticky;position:-moz-sticky;position:sticky;\
                 bottom:0;}\n\
    \     thead th {background-color: #dde;}
    \     td {text-align: right;}\n\
    \     tr:nth-child(odd) {background-color:#eef;}\n\
    \     th, td {padding:2ex; border: 1px solid #e0e0e0;}\n\
    \  </style>\n\
     </head>"
    title

let () =
  let comparison = all_results "comparison" in
  let flambda = all_results "flambda" in
  let sizes_comparison = sizes "comparison" in
  let sizes_flambda = sizes "flambda" in
  let libsz_comparison = lib_sizes sizes_comparison in
  let libsz_flambda = lib_sizes sizes_flambda in
  let m = M.merge (fun _ c f -> Some (c,f)) comparison flambda in
  Printf.printf "%s\n<body><table class=\"sortable\">\
                 <thead><tr><th>Package</th><th>reference</th><th>flambda</th>\
                 <th>ref time (s)</th><th>flambda time(s)</th><th>ratio</th>\
                 <th>ref lib size (KB)</th><th>flambda lib size (KB)</th>\
                 <th>size ratio</th></tr></thead><tbody>\n"
    (html_head ("FLambda comparison " ^ Filename.basename (Sys.getcwd ())));
  let full_line =
    Printf.printf "<tr><th>%s.%s</th><td>%s</td><td>%s</td>\
                   <td>%.3f</td><td>%.3f</td><td>%.2fx</td>\
                   <td>%s</td><td>%s</td><td>%s</td></tr>\n"
  in
  let short_line =
    Printf.printf "<tr><th>%s.%s</td><td>%s</td><td>%s</td>\
                   <td>%s</td><td>%s</td>\
                   <td></td><td></td><td></td><td></td></tr>\n"
  in
  let total_c, total_f, time_c, time_f, sz_c, sz_f =
    M.fold (fun ((pkg,_),a) (c,f) (stc,stf,tc,tf,szc,szf as acc) ->
        match a, c, f with
        | Build, Some c, Some f ->
          if c.status <> Ok && f.status <> Ok then acc
          else if c.status <> Ok then stc, stf + 1, tc, tf, szc, szf
          else if f.status <> Ok then stc + 1, stf, tc, tf, szc, szf
          else
            let find m = try SM.find pkg m with Not_found -> lib_empty in
            (stc + 1, stf + 1, tc +. c.duration, tf +. f.duration,
             ls_map2 (+) szc (find libsz_comparison),
             ls_map2 (+) szf (find libsz_flambda))
        | _ -> acc)
      m (0,0,0.,0.,lib_empty,lib_empty)
  in
  let print_sz i = Printf.sprintf "%d.%02d" (i/1000) (i mod 1000 / 10) in
  let dft d o f = match o with None -> d | Some x -> f x in
  M.iter (fun ((name,version),a) (c,f) -> match a with
      | Install | Remove -> ()
      | Build ->
        match c,f with
        | Some ({status = Ok} as c), Some ({status = Ok} as f) ->
          let sz_comp =
            try SM.find name libsz_comparison with Not_found -> lib_empty
          in
          let sz_flam =
            try SM.find name libsz_flambda with Not_found -> lib_empty
          in
          full_line name version
            (string_of_status (c.status)) (string_of_status (f.status))
            (c.duration) (f.duration)
            (f.duration /. c.duration)
            (lib_size_to_string print_sz sz_comp)
            (lib_size_to_string print_sz sz_flam)
            (lib_size_to_string (Printf.sprintf "%.2fx")
               (ls_map2 (fun a b -> float_of_int a /. float_of_int b)
                  sz_flam sz_comp))
        | _ ->
          short_line name version
            (dft "-" c @@ fun r -> string_of_status (r.status))
            (dft "-" f @@ fun r -> string_of_status (r.status))
            (dft "" c @@ fun r ->
             if r.status = Aborted then "" else
               Printf.sprintf "%.3f" r.duration)
            (dft "" f @@ fun r ->
             if r.status = Aborted then "" else
               Printf.sprintf "%.3f" r.duration)
    )
    m;
  Printf.printf "</tbody><tfoot>\n";
  full_line ".TOTAL" ""
    (Printf.sprintf "%d Ok" total_c) (Printf.sprintf "%d Ok" total_f)
    time_c time_f (time_f /. time_c)
    (lib_size_to_string print_sz sz_c)
    (lib_size_to_string print_sz sz_f)
    (lib_size_to_string (Printf.sprintf "%.2f")
       (ls_map2 (fun a b -> float_of_int a /. float_of_int b) sz_f sz_c));
  Printf.printf "</tfoot></table>\n<br/><br/><br/>\n";
  Printf.printf "<table class=\"sortable\"><thead>\
                 <tr><th>Binary</th><th>ref size (KB)</th>\
                 <th>flambda size (KB)</th><th>ratio</th></tr></thead>\
                 <tbody>\n";
  let tot_c, tot_f =
    SM.fold (fun f (szc, szf) (tot_c, tot_f) ->
        if is_prefix "bin/" f then (
          Printf.printf
            "<tr><th>%s</th><td>%s</td><td>%s</td><td>%.2f</td></tr>\n"
            (String.sub f 4 (String.length f - 4))
            (print_sz szc) (print_sz szf)
            (float_of_int szf /. float_of_int szc);
          tot_c + szc, tot_f + szf)
        else
          tot_c, tot_f
      )
      (SM.merge (fun _ a b -> match a,b with
         | Some a, Some b -> Some (a,b)
         | _ -> None)
        sizes_comparison sizes_flambda)
      (0,0);
  in
  Printf.printf "</tbody><tfoot><tr><th>TOTAL</th>\
                 <td>%s</td><td>%s</td><td>%.2f</td></tr>\n\
                 </tfoot></table>"
    (print_sz tot_c) (print_sz tot_f) (float_of_int tot_f /. float_of_int tot_c);
  Printf.printf "</body></html>\n"
