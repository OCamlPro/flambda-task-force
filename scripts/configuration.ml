type configuration = {
  inline: int; (* 0 .. 10 *)
  rounds: int; (* 0 .. 2 *)
  unroll: int; (* 0 .. 2 *)
  inline_call_cost: int; (* 1 .. 5 *)
  inline_alloc_cost: int; (* 1 .. 15 *)
  inline_prim_cost: int; (* 1 .. 5 *)
  inline_branch_cost: int; (* 1 .. 10 *)
  no_functor_heuristic: bool;
}

let default_configuration = {
  inline = 10;
  rounds = 1;
  unroll = 0;
  inline_call_cost = 5;
  inline_alloc_cost = 10;
  inline_prim_cost = 3;
  inline_branch_cost = 10;
  no_functor_heuristic = false;
}

let to_string conf =
  let acc = Printf.sprintf "*: timings = %i\n" 1 in
  let acc = Printf.sprintf "%s*: inline = %i\n" acc conf.inline in
  let acc = Printf.sprintf "%s*: rounds = %i\n" acc conf.rounds in
  let acc = Printf.sprintf "%s*: unroll = %i\n" acc conf.unroll in
  let acc = Printf.sprintf "%s*: inline-call-cost = %i\n" acc conf.inline_call_cost in
  let acc = Printf.sprintf "%s*: inline-alloc-cost = %i\n" acc conf.inline_alloc_cost in
  let acc = Printf.sprintf "%s*: inline-prim-cost = %i\n" acc conf.inline_prim_cost in
  let acc = Printf.sprintf "%s*: inline-branch-cost = %i\n" acc conf.inline_branch_cost in
  Printf.sprintf "%s*: functor-heuristics = %i" acc
    (if not conf.no_functor_heuristic then 1 else 0)

let dump_conf_file conf path =
  Printf.printf "Creating %S...\n%!" path;
  let oc = open_out path in
  Printf.fprintf oc "%s%!" (to_string conf);
  close_out oc

let conf_descr conf =
  Printf.sprintf "%s-%i_%s-%i_%s-%i_%s-%i_%s-%i_%s-%i_%s-%i_%s-%b"
    "inline" conf.inline 
    "rounds" conf.rounds 
    "unroll" conf.unroll 
    "call-cost" conf.inline_call_cost 
    "alloc-cost" conf.inline_alloc_cost 
    "prim-cost" conf.inline_prim_cost 
    "branch-cost" conf.inline_branch_cost 
    "nofunctorheuristic" conf.no_functor_heuristic

let config1 = {
  inline = 10;
  rounds = 0;
  unroll = 0;
  inline_call_cost = 1;
  inline_alloc_cost = 1;
  inline_prim_cost = 1;
  inline_branch_cost = 1;
  no_functor_heuristic = false;
}

let config2 = {
  inline = 10;
  rounds = 2;
  unroll = 1;
  inline_call_cost = 5;
  inline_alloc_cost = 15;
  inline_prim_cost = 5;
  inline_branch_cost = 10;
  no_functor_heuristic = false;
}

let config3 = {
  inline = 10;
  rounds = 2;
  unroll = 1;
  inline_call_cost = 2;
  inline_alloc_cost = 7;
  inline_prim_cost = 3;
  inline_branch_cost = 5;
  no_functor_heuristic = false;
}

let config4 = {
  inline = 10;
  rounds = 1;
  unroll = 0;
  inline_call_cost = 5;
  inline_alloc_cost = 1;
  inline_prim_cost = 1;
  inline_branch_cost = 1;
  no_functor_heuristic = false;
}

let config5 = {
  inline = 10;
  rounds = 1;
  unroll = 0;
  inline_call_cost = 1;
  inline_alloc_cost = 15;
  inline_prim_cost = 1;
  inline_branch_cost = 1;
  no_functor_heuristic = false;
}

let config6 = {
  inline = 10;
  rounds = 1;
  unroll = 0;
  inline_call_cost = 1;
  inline_alloc_cost = 1;
  inline_prim_cost = 5;
  inline_branch_cost = 1;
  no_functor_heuristic = false;
}

let config7 = {
  inline = 10;
  rounds = 1;
  unroll = 0;
  inline_call_cost = 1;
  inline_alloc_cost = 1;
  inline_prim_cost = 1;
  inline_branch_cost = 10;
  no_functor_heuristic = false;
}

let config8 = {
  inline = 10;
  rounds = 1;
  unroll = 0;
  inline_call_cost = 3;
  inline_alloc_cost = 3;
  inline_prim_cost = 3;
  inline_branch_cost = 10;
  no_functor_heuristic = true;
}

let config9 = {
  inline = 10;
  rounds = 2;
  unroll = 1;
  inline_call_cost = 2;
  inline_alloc_cost = 7;
  inline_prim_cost = 3;
  inline_branch_cost = 5;
  no_functor_heuristic = true;
}

let config10 = {
  inline = 10;
  rounds = 1;
  unroll = 0;
  inline_call_cost = 0;
  inline_alloc_cost = 0;
  inline_prim_cost = 0;
  inline_branch_cost = 0;
  no_functor_heuristic = true;
}

(* let configurations =  *)
(*   [ default_configuration; config1; config2; config3; config4; config5; config6; config7; config8; config9; config10 ] *)

(* let configurations =  *)
(*   configurations @ List.map (fun config -> { config with inline = 20 }) configurations *)

let inline = [ 5; 10; 20; 50 ]

let rounds = [ 1; 2; 3 ]

let unroll = [ 0; 1 ]

let cost = [ (0, 0, 0, 0); (3, 3, 3, 3); (15, 3, 3, 3); (3, 15, 3, 3); (3, 3, 15, 3); (3, 3, 3, 15) ]

let no_funct = [ true; false ]

let product l1 l2 =
  List.flatten (List.map (fun x -> List.map (fun y -> (x, y)) l2) l1)

let configurations = 
  List.map (fun ((((inline, rounds), unroll), (inline_call_cost, inline_alloc_cost, inline_prim_cost, inline_branch_cost)), no_functor_heuristic) ->
    { inline; rounds; unroll; inline_call_cost; inline_alloc_cost;
      inline_prim_cost; inline_branch_cost; no_functor_heuristic; }
) (product (product (product (product inline rounds) unroll) cost) no_funct)
