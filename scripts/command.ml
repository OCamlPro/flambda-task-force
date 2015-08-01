let debug = ref false

let flambda_archives = "flambda_archives"

let comparison_url = "https://github.com/chambart/ocaml-1/archive/comparison_branch.tar.gz"
let comparison_local = Filename.concat flambda_archives "comparison_branch.tar.gz"
let comparison_name = "4.03.0+comparison+gen"
let comparison_descr = "The comparison branch based on trunk"

let flambda_url = "https://github.com/chambart/ocaml-1/archive/flambda_trunk.tar.gz"
let flambda_local = Filename.concat flambda_archives "flambda_trunk.tar.gz"
let flambda_name = "4.03.0+flambda+gen"
let flambda_descr = "The main flambda developpement branch"

let base_repo_url = "https://flambda.ocamlpro.com/opam-flambda-repository/"
(* let overlay_repo_url = "git://github.com/OCamlPro/opam-flambda-repository-overlay" *)
let overlay_repo_url = "opam-flambda-repository-overlay"
let benchs_repo_url = "git://github.com/OCamlPro/opam-bench-repo"

let time_str () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%i-%i-%i_%i-%i" 
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday tm.Unix.tm_hour tm.Unix.tm_min

let rec remove file =
  if Sys.file_exists file
  then
    let stat = Unix.stat file in
    match stat.Unix.st_kind with
    | Unix.S_REG
    | Unix.S_LNK ->
       Unix.unlink file
    | Unix.S_DIR ->
       let handle = Unix.opendir file in
       begin try
           while true do
             let filename = Unix.readdir handle in
             match filename with
             | "." | ".." -> ()
             | _ ->
                remove (Filename.concat file filename)
           done
         with End_of_file -> ()
       end;
       Unix.closedir handle;
       begin try
           Unix.rmdir file
         with _ -> ()
       end
    | _ ->
       Printf.eprintf "ignored file: %s@." file

let mk_dir path =
  if !debug then Printf.printf "mk_dir %s\n%!" path;
  remove path;
  Unix.mkdir path 0o777

let input_all =
  let len = 1024 in
  let buf = Bytes.create len in
  let rec aux ic b =
    let n = input ic buf 0 1024 in
    Buffer.add_substring b buf 0 n;
    if n = 1024
    then aux ic b
  in
  fun ic ->
    let b = Buffer.create 100 in
    aux ic b;
    Buffer.contents b

let input_all_file name =
  let ic = open_in name in
  let s = input_all ic in
  close_in ic;
  s

let copy_file =
  let buffer_size = 8192 in
  let buffer = Bytes.create buffer_size in

  fun input_name output_name ->
    let fd_in = Unix.openfile input_name [Unix.O_RDONLY] 0 in
    let fd_out = Unix.openfile output_name [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o644 in
    let rec loop () =
      let read = Unix.read fd_in buffer 0 buffer_size in
      if read <> 0
      then
        let _w : int = Unix.write fd_out buffer 0 read in
        loop ()
    in
    let close () =
      Unix.close fd_in;
      Unix.close fd_out
    in
    (try loop ()
     with e -> close (); raise e);
    close ()


let make_tmp_file prefix suffix =
  let name = Filename.temp_file prefix suffix in
  name, Unix.openfile name [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND] 0o644

let command_to_string args =
  Array.fold_left (fun acc arg -> Printf.sprintf "%s %s" acc arg) "" args

let run_command ?parse_stdout:(flag=false) prog args =
  let cmd_str = command_to_string args in
  Printf.printf "Running%s...\n\n%!" cmd_str;
  let stdout_name, fd_stdout = make_tmp_file "" ".out" in
  let out = if flag then fd_stdout else Unix.stdout in 
  let pid = Unix.create_process prog args Unix.stdin out Unix.stderr in
  Unix.close fd_stdout;
  let rpid, status = Unix.waitpid [] pid in
  assert(rpid = pid);
  match status with
  | Unix.WEXITED 0 -> 
    if flag 
    then true, Some (input_all_file stdout_name)
    else true, None
  | Unix.WEXITED n ->
    Printf.eprintf "Command return code %i:\n%s\n%!" n cmd_str;
    if flag 
    then false, Some (input_all_file stdout_name)
    else false, None
  | Unix.WSIGNALED n ->
    Printf.eprintf "Command killed with signal %i:\n%s\n%!" n cmd_str;
    if flag 
    then false, Some (input_all_file stdout_name)
    else false, None
  | Unix.WSTOPPED _n -> 
    if flag 
    then false, Some (input_all_file stdout_name)
    else false, None

let run_stderr_command ?parse_stdout:(flag=false) prog args =
  let cmd_str = command_to_string args in
  Printf.printf "Running%s...\n\n%!" cmd_str;
  let stderr_name, fd_stderr = make_tmp_file "" ".err" in
  let err = if flag then fd_stderr else Unix.stderr in
  let pid = Unix.create_process prog args Unix.stdin Unix.stdout err in
  Unix.close fd_stderr;
  let rpid, status = Unix.waitpid [] pid in
  assert(rpid = pid);
  match status with
  | Unix.WEXITED 0 ->
    if flag
    then Some (input_all_file stderr_name)
    else None
  | Unix.WEXITED n ->
    Printf.eprintf "Command return code %i:\n%s\n%!" n cmd_str;
    assert false
  | Unix.WSIGNALED n ->
    Printf.eprintf "Command killed with signal %i:\n%s\n%!" n cmd_str;
    assert false
  | Unix.WSTOPPED _n -> assert false
