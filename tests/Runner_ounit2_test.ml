let passing =
  QCheck.Test.make ~count:1000
    ~name:"list_rev_is_involutive"
    QCheck.(list small_int)
    (fun l -> List.rev (List.rev l) = l);;

let failing =
  QCheck.(Test.make ~count:10 ~name:"failing_test"
            (list small_int)
            (fun l -> l = List.sort compare l));;

let () =
  let open OUnit2 in
  run_test_tt_main (
      "tests" >::: QCheck_runner.to_ounit2_test_list [passing; failing])
