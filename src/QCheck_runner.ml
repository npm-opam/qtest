(*
QCheck: Random testing for OCaml
Copyright (C) 2016  Vincent Hugot, Simon Cruanes

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Library General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Library General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)

open OUnit

let ps,pl = print_string,print_endline
let va = Printf.sprintf
let pf = Printf.printf

let separator1 = "\027[K" ^ (String.make 79 '\\')
let separator2 = String.make 79 '/'

let string_of_path path =
  let path = List.filter (function Label _ -> true | _ -> false) path in
  String.concat ">" (List.rev_map string_of_node path)

let result_path = function
    | RSuccess path
    | RError (path, _)
    | RFailure (path, _)
    | RSkip (path, _)
    | RTodo (path, _) -> path

let result_msg = function
    | RSuccess _ -> "Success"
    | RError (_, msg)
    | RFailure (_, msg)
    | RSkip (_, msg)
    | RTodo (_, msg) -> msg

let result_flavour = function
    | RError _ -> "Error"
    | RFailure _ -> "Failure"
    | RSuccess _ -> "Success"
    | RSkip _ -> "Skip"
    | RTodo _ -> "Todo"

let not_success = function RSuccess _ -> false | _ -> true

let print_result_list =
  List.iter (fun result -> pf "%s\n%s: %s\n\n%s\n%s\n"
    separator1 (result_flavour result)
    (string_of_path (result_path result))
    (result_msg result) separator2)

let seed = ref ~-1
let st = ref None

let set_seed_ s =
  seed := s;
  Printf.printf "\rrandom seed: %d\n%!" s;
  let state = Random.State.make [| s |] in
  st := Some state;
  state

let set_seed s = ignore (set_seed_ s)

let setup_random_state_ () =
  let s = if !seed = ~-1 then (
      Random.self_init ();  (* make new, truly random seed *)
      Random.int (1 lsl 29);
  ) else !seed in
  set_seed_ s

(* initialize random generator from seed (if any) *)
let random_state () = match !st with
  | Some st -> st
  | None -> setup_random_state_ ()

let verbose, set_verbose =
  let r = ref false in
  (fun () -> !r), (fun b -> r := b)

(* Function which runs the given function and returns the running time
   of the function, and the original result in a tuple *)
let time_fun f x y =
  let begin_time = Unix.gettimeofday () in
  let res = f x y in (* evaluate this first *)
  Unix.gettimeofday () -. begin_time, res

type cli_args = {
  cli_verbose : bool;
  cli_print_list : bool;
  cli_rand : Random.State.t;
  cli_slow_test : int; (* how many slow tests to display? *)
}

let parse_cli ~full_options argv =
  let print_list = ref false in
  let set_verbose () = set_verbose true in
  let set_list () = print_list := true in
  let slow = ref 0 in
  let options = Arg.align (
    [ "-v", Arg.Unit set_verbose, " "
    ; "--verbose", Arg.Unit set_verbose, " enable verbose tests"
    ] @
    (if full_options then
      [ "-l", Arg.Unit set_list, " "
      ; "--list", Arg.Unit set_list, " print list of tests (2 lines each)"
      ; "--slow", Arg.Set_int slow, " print the <n> slowest tests"
      ] else []
    ) @
    [ "-s", Arg.Set_int seed, " "
    ; "--seed", Arg.Set_int seed, " set random seed (to repeat tests)"
    ]
  ) in
  Arg.parse_argv argv options (fun _ ->()) "run qtest suite";
  let cli_rand = setup_random_state_ () in
  { cli_verbose=verbose(); cli_rand;
    cli_print_list= !print_list; cli_slow_test= !slow; }

let run ?(argv=Sys.argv) test =
  let cli_args = parse_cli ~full_options:true argv in
  let _counter = ref (0,0,0) in (* Success, Failure, Other *)
  let total_tests = test_case_count test in
  (* list of (test, execution time) *)
  let exec_times = ref [] in
  let update = function
    | RSuccess _ -> let (s,f,o) = !_counter in _counter := (succ s,f,o)
    | RFailure _ -> let (s,f,o) = !_counter in _counter := (s,succ f,o)
    | _ -> let (s,f,o) = !_counter in _counter := (s,f, succ o)
  in
  (* time each test *)
  let start = ref 0. and stop = ref 0. in
  (* display test as it starts and ends *)
  let display_test ?(ended=false) p  =
    let (s,f,o) = !_counter in
    let cartouche = va " [%d%s%s / %d] " s
      (if f=0 then "" else va "+%d" f)
      (if o=0 then "" else va " %d!" o) total_tests
    and path = string_of_path p in
    let end_marker =
      if cli_args.cli_print_list then (
        (* print a single line *)
        if ended then va " (after %.2fs)\n" (!stop -. !start) else "\n"
      ) else (
        ps "\r";
        if ended then " *" else ""
      )
    in
    let line = cartouche ^ path ^ end_marker in
    let remaining = 79 - String.length line in
    let cover = if remaining > 0 && not cli_args.cli_print_list
      then String.make remaining ' ' else "" in
    pf "%s%s%!" line cover;
  in
  let hdl_event = function
    | EStart p ->
      start := Unix.gettimeofday();
      display_test p
    | EEnd p  ->
      stop := Unix.gettimeofday();
      display_test p ~ended:true;
      let exec_time = !stop -. !start in
      exec_times := (p, exec_time) :: !exec_times
    | EResult result -> update result
  in
  ps "Running tests...";
  let running_time, results = time_fun perform_test hdl_event test in
  let (_s, f, o) = !_counter in
  let failures = List.filter not_success results in
  (*  assert (List.length failures = f);*)
  ps "\r";
  print_result_list failures;
  assert (List.length results = total_tests);
  pf "Ran: %d tests in: %.2f seconds.%s\n"
    total_tests running_time (String.make 40 ' ');
  (* XXX: suboptimal, but should work fine *)
  if cli_args.cli_slow_test > 0 then (
    pf "Display the %d slowest tests:\n" cli_args.cli_slow_test;
    let l = !exec_times in
    let l = List.sort (fun (_,t1)(_,t2) -> compare t2 t1) l in
    List.iteri
      (fun i (p,t) ->
         if i<cli_args.cli_slow_test
         then pf "  %s in %.2fs\n" (OUnit.string_of_path p) t)
      l
  );
  if failures = [] then pl "SUCCESS";
  if o <> 0 then pl "WARNING! SOME TESTS ARE NEITHER SUCCESSES NOR FAILURES!";
  (* create a meaningful return code for the process running the tests *)
  match f, o with
    | 0, 0 -> 0
    | _ -> 1

(* TAP-compatible test runner, in case we want to use a test harness *)

let run_tap test =
  let test_number = ref 0 in
  let handle_event = function
    | EStart _ | EEnd _ -> incr test_number
    | EResult (RSuccess p) ->
      pf "ok %d - %s\n%!" !test_number (string_of_path p)
    | EResult (RFailure (p,m)) ->
      pf "not ok %d - %s # %s\n%!" !test_number (string_of_path p) m
    | EResult (RError (p,m)) ->
      pf "not ok %d - %s # ERROR:%s\n%!" !test_number (string_of_path p) m
    | EResult (RSkip (p,m)) ->
      pf "not ok %d - %s # skip %s\n%!" !test_number (string_of_path p) m
    | EResult (RTodo (p,m)) ->
      pf "not ok %d - %s # todo %s\n%!" !test_number (string_of_path p) m
  in
  let total_tests = test_case_count test in
  pf "TAP version 13\n1..%d\n" total_tests;
  perform_test handle_event test

let next_name_ =
  let i = ref 0 in
  fun () ->
    let name = "<anon prop> " ^ (string_of_int !i) in
    incr i;
    name

type ('b,'c) printer = {
  info: 'a. ('a,'b,'c,unit) format4 -> 'a;
  fail: 'a. ('a,'b,'c,unit) format4 -> 'a;
  err: 'a. ('a,'b,'c,unit) format4 -> 'a;
}

(* main callback for individual tests
   @param verbose if true, print statistics and details
   @param print_res if true, print the result on [out] *)
let callback ~verbose ~print_res ~print name cell result =
  let module R = QCheck.TestResult in
  let module T = QCheck.Test in
  let arb = T.get_arbitrary cell in
  if verbose then (
    print.info "\rlaw %s: %d relevant cases (%d total)\n"
      name result.R.count result.R.count_gen;
    match arb.QCheck.collect with
    | None -> ()
    | Some _ ->
        let (lazy tbl) = result.R.collect_tbl in
        Hashtbl.iter
          (fun case num -> print.info "\r  %s: %d cases\n" case num)
          tbl
  );
  if print_res then (
    (* even if [not verbose], print errors *)
    match result.R.state with
      | R.Success -> ()
      | R.Failed l ->
        print.fail "\r  %s\n" (T.print_fail arb name l);
      | R.Error (i,e) ->
        print.err "\r  %s\n" (T.print_error arb name (i,e));
  )

let name_of_cell cell =
  let module T = QCheck.Test in
  match T.get_name cell with
  | None ->
    let n = next_name_ () in
    T.set_name cell n;
    n
  | Some m -> m

let print_std = { info = Printf.printf; fail = Printf.printf; err = Printf.printf }

(* to convert a test to a [OUnit.test], we register a callback that will
   possibly print errors and counter-examples *)
let to_ounit_test_cell ?(verbose=verbose()) ?(rand=random_state()) cell =
  let module T = QCheck.Test in
  let name = name_of_cell cell in
  let run () =
    try
      T.check_cell_exn cell
        ~rand ~call:(callback ~verbose ~print_res:verbose ~print:print_std);
      true
    with T.Test_fail _ ->
      false
  in
  name >:: (fun _ -> assert_bool name (run ()))

let to_ounit_test ?verbose ?rand (QCheck.Test.Test c) =
  to_ounit_test_cell ?verbose ?rand c

let (>:::) name l =
  name >::: (List.map (fun t -> to_ounit_test t) l)

let conf_seed = OUnit2.Conf.make_int "seed" ~-1 "set random seed"

let default_rand () =
  (* random seed, for repeatability of tests *)
  Random.State.make [| 89809344; 994326685; 290180182 |]

let to_ounit2_test ?(rand = default_rand()) (QCheck.Test.Test cell) =
  let module T = QCheck.Test in
  let name = name_of_cell cell in
  let open OUnit2 in
  name >:: (fun ctxt ->
      let rand = match conf_seed ctxt with
        | -1 ->
          Random.State.copy rand
        | s ->
          (* user provided random seed *)
          Random.State.make [| s |]
      in
      let print = {
        info = (fun fmt -> logf ctxt `Info fmt);
        fail = (fun fmt -> Printf.ksprintf assert_failure fmt);
        err = (fun fmt -> logf ctxt `Error fmt);
      } in
      T.check_cell_exn cell
        ~rand ~call:(callback ~verbose:true ~print_res:true ~print))

let to_ounit2_test_list ?rand lst =
  List.rev (List.rev_map (to_ounit2_test ?rand) lst)

let run_tests ?(verbose=verbose()) ?(out=stdout) ?(rand=random_state()) l =
  let module T = QCheck.Test in
  let module R = QCheck.TestResult in
  let n_fail = ref 0 in
  let n = ref 0 in
  List.iter
    (fun (T.Test cell) ->
      incr n;
      let res =
        T.check_cell cell ~call:(callback ~print:print_std ~print_res:true ~verbose) ~rand
      in
      match res.R.state with
      | R.Success -> ()
      | R.Failed _ | R.Error _ -> incr n_fail)
    l;
  if !n_fail = 0 then (
    Printf.fprintf out "success (ran %d tests)\n%!" !n;
    0
  ) else (
    Printf.fprintf out "failure (%d tests failed, ran %d tests)\n%!" !n_fail !n;
    1
  )

let run_tests_main ?(argv=Sys.argv) l =
  try
    let cli_args = parse_cli ~full_options:false argv in
    exit
      (run_tests l ~verbose:cli_args.cli_verbose
         ~out:stdout ~rand:cli_args.cli_rand)
  with
    | Arg.Bad msg -> print_endline msg; exit 1
    | Arg.Help msg -> print_endline msg; exit 0
