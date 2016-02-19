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
}

let (%) j f = List.assoc f (JU.to_assoc j)

let parse_pkg j =
  let a = JU.to_assoc j in
  JU.to_string (List.assoc "name" a), JU.to_string (List.assoc "version" a)

let parse_action: J.json -> pkg * action = function
  | `Assoc ["build",p] -> parse_pkg p, Build
  | `Assoc ["install",p] -> parse_pkg p, Install
  | `Assoc ["remove",p] -> parse_pkg p, Remove

let rec rev_drop_after n acc = function
  | [] -> acc
  | _ when n <= 0 -> acc
  | x::r -> rev_drop_after (n-1) (x::acc) r

let parse_status: J.json -> status = function
  | `String "OK" -> Ok
  | `Assoc ["aborted", `List a] ->
    Aborted (List.map parse_action a)
  | `Assoc ["process-error", e] ->
    let lmap f l = List.rev_map f (rev_drop_after 10_000 [] l) in
    Failed (JU.to_string (e%"info"%"command"),
            (match e%"code" with
             | `String s -> int_of_string s
             | `Int i -> i
             | _ -> failwith "bad return code"),
            lmap JU.to_string (JU.to_list (e%"stdout")),
            lmap JU.to_string (JU.to_list (e%"stderr")))
  | `Assoc ["exception", `String e] ->
    Failed ("opam", 0, [], ["Opam raised exception:";e])

let parse_result r =
  parse_action (r%"action"),
  { status = parse_status (r%"result");
    duration = try JU.to_float (r%"duration") with Not_found -> 0.
  }

let parse_results f =
  let f = JU.to_assoc (J.from_file f) in
  try
    let r = JU.to_list (List.assoc "results" f) in
    List.map parse_result r
  with Not_found -> []

module M = Map.Make(struct
    type t = pkg * action
    let compare = compare
  end)

module S = Set.Make(String)
module SM = Map.Make (String)

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
    \     a:target {background-color:#e0e000;}\n\
    \  --></style>\n\
     </head>"
    title

let escape s =
  let s = Re.replace_string (Re.compile (Re.char '&')) ~by:"&amp;" s in
  let s = Re.replace_string (Re.compile (Re.char '<')) ~by:"&lt;" s in
  s

let html_status logs name version sw status =
  let id = Printf.sprintf "id=\"%s:%s.%s\"" sw name version in
  match status with
  | Some {status = Ok; _} -> logs, Printf.sprintf "<a %s>OK</a>" id
  | Some {status = Aborted deps; _} ->
    let causes = List.map (fun ((n,v),_) -> Printf.sprintf "%s.%s" n v) deps in
    logs,
    Printf.sprintf "<a %s title=\"Failed dependencies: %s\">Aborted</a>"
      id (String.concat ", " causes)
  | Some {status = Failed (cmd,i,stdout,stderr); _} ->
    let logid = Printf.sprintf "log-%s-%s-%s" sw name version in
    Printf.sprintf
      "<div class=\"logs\" id=\"%s\">\n\
      \  <a class=\"close\" href=\"#close\">Close</a>\n\
      \  <h3>Error on %s.%s (%s)</h3>\n\
      \  <p>Command: <pre>%s</pre></p>\n\
      \  <h4>Stdout</h4><pre>%s</pre>\n\
      \  <h4>Stderr</h4><pre>%s</pre>\n\
       </div>\n"
      logid name version sw
      (escape cmd)
      (escape (String.concat "\n" stdout))
      (escape (String.concat "\n" stderr))
    :: logs,
    Printf.sprintf "<a %s href=\"#%s\">Failure (%d)</a>" id logid i
  | None -> logs, Printf.sprintf "<a %s>-</a>" id

let () =
  let files = List.tl (Array.to_list Sys.argv) in
  let run_name f = Filename.(chop_extension (basename f)) in
  let runs = List.map run_name files in
  let results =
    List.fold_left (fun results file ->
        let run = run_name file in
        List.fold_left (fun results (action,result) ->
            let sm = try M.find action results with Not_found -> SM.empty in
            M.add action (SM.add run result sm) results)
          results (parse_results file))
      M.empty files
  in
  print_string (html_head "Bench build results");
  print_string "<body>\n<div>\n<table class=\"sortable\">\n\
                <thead>\n\
               \  <tr><th>Package</th>";
  List.iter (Printf.printf "<th>%s</th>") runs;
  List.iter (Printf.printf "<th>%s time (s)</th>") runs;
  print_string "</tr>\n</thead>\n<tbody>\n";
  let logs =
    M.fold (fun ((name,version),action) result_map logs ->
        match action with
        | Install | Remove -> logs
        | Build ->
          Printf.printf "  <tr><th id=\"%s.%s\">%s.%s</th>"
            name version name version;
          let logs =
            List.fold_left (fun logs run ->
                let logs, status =
                  html_status logs name version run
                    (try Some (SM.find run result_map) with Not_found -> None)
                in
                Printf.printf "<td>%s</td>" status;
                logs)
              logs runs
          in
          List.iter (fun run ->
              try
                Printf.printf "<td>%.3f</td>" (SM.find run result_map).duration
              with Not_found -> print_string "<td>-</td>")
            runs;
          print_string "</tr>\n";
          logs)
      results []
  in
  print_string "</tbody>\n</table></div>";
  List.iter print_string logs;
  Printf.printf "</body></html>\n"
