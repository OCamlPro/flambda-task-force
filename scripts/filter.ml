type result = {
  name: string;
  compilation_time: float;
  size: float;
  strip_size: float;
  cycles: float;
}

let string_of_result res =
  Printf.sprintf "%s\n%s: %f\n%s: %f\n%s: %f\n%s: %f%!" res.name 
    "compile_time" res.compilation_time
    "size" res.size
    "strip_size" res.strip_size
    "cycles" res.cycles

let empty_result name = 
  { name; compilation_time = 0.; size = 0.; strip_size = 0.; cycles = 0.; }

let check_extension file =
  Filename.check_suffix file ".result"

let get_packet_name file =
  let content = Command.input_all_file file in
  let list = List.rev (Str.split (Str.regexp_string "\n") content) in
  let size = List.nth list 2 in
  try
    Scanf.sscanf size "size: %[a-zA-Z0-9/+-._] = %i"
                (fun packet _ -> Filename.basename packet)
  with Scanf.Scan_failure _ | End_of_file -> assert false

let parse_result_file file =
  let content = Command.input_all_file file in
  let res = empty_result file in
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
     (fun value -> { res with cycles = float value }) in res
  with Scanf.Scan_failure _ | End_of_file -> res

let parse file =
  let rec aux acc file =
    if Sys.file_exists file
    then
      let stat = Unix.stat file in
      match stat.Unix.st_kind with
      | Unix.S_REG -> 
        if check_extension file
        then ((parse_result_file file) :: acc)
        else acc
      | Unix.S_LNK -> acc
      | Unix.S_DIR ->
         let files = Sys.readdir file in
         Array.fold_left (fun acc f -> aux acc (Filename.concat file f)) acc files
      | _ ->
         (Printf.eprintf "ignored file: %s@." file; acc)
    else acc
  in aux [] file

let find_comparison_result results dir =
  let fst_file = (List.hd results).name in
  let packet = get_packet_name fst_file in
  let comparison_name = Printf.sprintf "4.03.0+comparison+gen_%s_.result" packet in
  Printf.printf "Looking for comparison result %s\n%!" comparison_name;
  List.filter (fun res -> 
      res.name = (Filename.concat dir comparison_name)
  ) results

let normalize comparison res =
  { res with compilation_time = (res.compilation_time /. comparison.compilation_time);
             size = (res.size /. comparison.size);
             strip_size = res.strip_size /. comparison.strip_size;
             cycles = res.cycles /. comparison.cycles; }

let usage = 
  Printf.sprintf "Usage: %s dir\n%!" Sys.executable_name

let () =
  if (Array.length Sys.argv) <> 2
  then Printf.printf "%s\n" usage
  else 
    let dir = Sys.argv.(1) in
    let res = parse dir in
    Printf.printf "%i results found out of %i configurations\n%!" (List.length res) (List.length Configuration.configurations);
    let comparison = find_comparison_result res dir in
    Printf.printf "%i comparison result found\n%!" (List.length comparison);
    if (List.length comparison) <> 1
    then Printf.printf "can't choose comparison result\n%!"
    else 
    let comparison = List.hd comparison in
    Printf.printf "%s\n%!" (string_of_result comparison);
    let norm = List.map (normalize comparison) res in
    let res_ok = List.filter (fun result -> 
      result.strip_size < 1.1) norm in
    let sorted = List.sort (fun r1 r2 -> Pervasives.compare r1.cycles r2.cycles) res_ok in
    List.iter (fun result ->
    Printf.printf "%s\n%!" (string_of_result result)
    ) (List.rev sorted)
