type configuration = {
  inline: int; (* 0 .. 10 *)
  rounds: int; (* 0 .. 3 *)
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

let dump_conf_file conf path =
  Printf.printf "Creating %S...\n%!" path;
  let oc = open_out path in
  Printf.fprintf oc "*: timings = %i\n" 1;
  Printf.fprintf oc "*: inline = %i\n" conf.inline;
  Printf.fprintf oc "*: rounds = %i\n" conf.rounds;
  Printf.fprintf oc "*: unroll = %i\n" conf.unroll;
  Printf.fprintf oc "*: inline-call-cost = %i\n" conf.inline_call_cost;
  Printf.fprintf oc "*: inline-alloc-cost = %i\n" conf.inline_alloc_cost;
  Printf.fprintf oc "*: inline-prim-cost = %i\n" conf.inline_prim_cost;
  Printf.fprintf oc "*: inline-branch-cost = %i\n" conf.inline_branch_cost;
  Printf.fprintf oc "*: functor-heuristic = %i" 
    (if not conf.no_functor_heuristic then 1 else 0);
  close_out oc

let conf_descr conf =
  Printf.sprintf "%s%i%s%i%s%i%s%i%s%i%s%i%s%i%s%b" 
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
  rounds = 3;
  unroll = 2;
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

let configurations = 
  [ default_configuration; config1; config2; config3; config4; config5; config6; config7 ]
