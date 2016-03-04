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

let () =
  let pkgname, files = match Array.to_list Sys.argv with
    | _::pkgname::(_::_ as files) -> pkgname, files
    | _ ->
      prerr_endline "Usage: opamjsontimes <pkgname> <date/run.json...>";
      exit 2
  in
  let run_name f = Filename.(chop_extension (basename f)) in
  let run_date f = Filename.dirname f in
  let results =
    List.fold_left (fun datemap file ->
        let date = run_date file in
        let run = run_name file in
        let r = parse_results file in
        try
          let _, result =
            List.find (function
                | ((name,_), Build), {status=Ok; _} when name = pkgname -> true
                | _ -> false)
              r
          in
          let runmap = try SM.find date datemap with Not_found -> SM.empty in
          SM.add date (SM.add run result.duration runmap) datemap
        with Not_found -> datemap)
      SM.empty files
  in
  let runs =
    SM.fold (fun _ -> SM.fold (fun run _ acc -> S.add run acc)) results S.empty
  in
  Printf.printf "# Date";
  S.iter (Printf.printf " %s") runs;
  print_newline ();
  SM.iter (fun date runmap ->
      print_string (String.sub date 0 15);
      S.iter (fun run ->
          try Printf.printf " %f" (SM.find run runmap)
          with Not_found -> print_string " -")
        runs;
      print_newline ())
    results
