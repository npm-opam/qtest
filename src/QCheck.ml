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

(** {1 Quickcheck inspired property-based testing} *)

open Printf

module RS = Random.State

let rec foldn ~f ~init:acc i =
  if i = 0 then acc else foldn ~f ~init:(f acc i) (i-1)

let _is_some = function Some _ -> true | None -> false

let _opt_map_or ~d ~f = function
  | None -> d
  | Some x -> f x

let _opt_or a b = match a with
  | None -> b
  | Some x -> x

let _opt_map ~f = function
  | None -> None
  | Some x -> Some (f x)

let _opt_map_2 ~f a b = match a, b with
  | Some x, Some y -> Some (f x y)
  | _ -> None

let _opt_map_3 ~f a b c = match a, b, c with
  | Some x, Some y, Some z -> Some (f x y z)
  | _ -> None

let _opt_sum a b = match a, b with
  | Some _, _ -> a
  | None, _ -> b

let sum_int = List.fold_left (+) 0

exception FailedPrecondition
(* raised if precondition is false *)

let (==>) b1 b2 = if b1 then b2 else raise FailedPrecondition

module Gen = struct
  type 'a t = RS.t -> 'a
  type 'a sized = int -> Random.State.t -> 'a

  let return x _st = x

  let (>>=) gen f st =
    f (gen st) st

  let (<*>) f x st = f st (x st)
  let map f x st = f (x st)
  let map2 f x y st = f (x st) (y st)
  let map3 f x y z st = f (x st) (y st) (z st)
  let map_keep_input f gen st = let x = gen st in x, f x
  let (>|=) x f = map f x

  let oneof l st = List.nth l (Random.State.int st (List.length l)) st
  let oneofl xs st = List.nth xs (Random.State.int st (List.length xs))
  let oneofa xs st = Array.get xs (Random.State.int st (Array.length xs))

  let frequencyl l st =
    let sums = sum_int (List.map fst l) in
    let i = Random.State.int st sums in
    let rec aux acc = function
      | ((x,g)::xs) -> if i < acc+x then g else aux (acc+x) xs
      | _ -> failwith "frequency"
    in
    aux 0 l

  let frequencya a = frequencyl (Array.to_list a)

  let frequency l st = frequencyl l st st

  (* natural number generator *)
  let nat st =
    let p = RS.float st 1. in
    if p < 0.5 then RS.int st 10
    else if p < 0.75 then RS.int st 100
    else if p < 0.95 then RS.int st 1_000
    else RS.int st 10_000

  let small_int = nat

  let unit _st = ()

  let bool st = RS.bool st

  let float st =
    exp (RS.float st 15. *. (if RS.float st 1. < 0.5 then 1. else -1.))
    *. (if RS.float st 1. < 0.5 then 1. else -1.)

  let pfloat st = abs_float (float st)
  let nfloat st = -.(pfloat st)

  let neg_int st = -(nat st)

  let opt f st =
    let p = RS.float st 1. in
    if p < 0.15 then None
    else Some (f st)

  (* Uniform random int generator *)
  let pint =
    if Sys.word_size = 32 then
      fun st -> RS.bits st
    else (* word size = 64 *)
      fun st ->
        RS.bits st                        (* Bottom 30 bits *)
        lor (RS.bits st lsl 30)           (* Middle 30 bits *)
        lor ((RS.bits st land 3) lsl 60)  (* Top 2 bits *)  (* top bit = 0 *)

  let int st = if RS.bool st then - (pint st) - 1 else pint st
  let int_bound n =
    assert (n >= 0);
    fun st -> Random.State.int st (n+1)
  let int_range a b =
    assert (b >= a);
    fun st -> a + (Random.State.int st (b-a+1))
  let (--) = int_range

  let random_binary_string st length =
    (* 0b011101... *)
    let s = Bytes.create (length + 2) in
    Bytes.set s 0 '0';
    Bytes.set s 1 'b';
    for i = 0 to length - 1 do
      Bytes.set s (i+2) (if RS.bool st then '0' else '1')
    done;
    Bytes.unsafe_to_string s

  let ui32 st = Int32.of_string (random_binary_string st 32)
  let ui64 st = Int64.of_string (random_binary_string st 64)

  let list_size size gen st =
    foldn ~f:(fun acc _ -> (gen st)::acc) ~init:[] (size st)
  let list gen st = list_size nat gen st
  let list_repeat n g = list_size (return n) g

  let array_size size gen st =
    Array.init (size st) (fun _ -> gen st)
  let array gen st = array_size nat gen st
  let array_repeat n g = array_size (return n) g

  let shuffle_a a st =
    for i = Array.length a-1 downto 1 do
      let j = Random.State.int st (i+1) in
      let tmp = a.(i) in
      a.(i) <- a.(j);
      a.(j) <- tmp;
    done

  let shuffle_l l st =
    let a = Array.of_list l in
    shuffle_a a st;
    Array.to_list a

  let pair g1 g2 st = (g1 st, g2 st)

  let triple g1 g2 g3 st = (g1 st, g2 st, g3 st)

  let quad g1 g2 g3 g4 st = (g1 st, g2 st, g3 st, g4 st)

  let char st = char_of_int (RS.int st 255)

  let printable_chars =
    let l = 126-32+1 in
    let s = Bytes.create l in
    for i = 0 to l-2 do
      Bytes.set s i (char_of_int (32+i))
    done;
    Bytes.set s (l-1) '\n';
    Bytes.unsafe_to_string s

  let printable st = printable_chars.[RS.int st (String.length printable_chars)]
  let numeral st = char_of_int (48 + RS.int st 10)

  let string_size ?(gen = char) size st =
    let s = Bytes.create (size st) in
    for i = 0 to String.length s - 1 do
      Bytes.set s i (gen st)
    done;
    Bytes.unsafe_to_string s
  let string ?gen st = string_size ?gen small_int st
  let small_string ?gen st = string_size ?gen (0--10) st

  (* corner cases *)

  let graft_corners gen corners () =
    let cors = ref corners in fun st ->
      match !cors with [] -> gen st
      | e::l -> cors := l; e

  let nng_corners () = graft_corners nat [0;1;2;max_int] ()

  (* sized, fix *)

  let sized f st =
    let n = nat st in
    f n st

  let fix f =
    let rec f' n st = f f' n st in
    f'

  let generate ?(rand=Random.State.make_self_init()) ~n g =
    list_repeat n g rand

  let generate1 ?(rand=Random.State.make_self_init()) g = g rand
end

module Print = struct
  type 'a t = 'a -> string

  let int = string_of_int
  let bool = string_of_bool
  let float = string_of_float
  let string s = s
  let char c = String.make 1 c

  let option f = function
    | None -> "None"
    | Some x -> "Some (" ^ f x ^ ")"

  let pair a b (x,y) = Printf.sprintf "(%s, %s)" (a x) (b y)
  let triple a b c (x,y,z) = Printf.sprintf "(%s, %s, %s)" (a x) (b y) (c z)
  let quad a b c d (x,y,z,w) =
    Printf.sprintf "(%s, %s, %s, %s)" (a x) (b y) (c z) (d w)

  let list pp l =
    let b = Buffer.create 25 in
    Buffer.add_char b '[';
    List.iteri (fun i x ->
      if i > 0 then Buffer.add_string b "; ";
      Buffer.add_string b (pp x))
      l;
    Buffer.add_char b ']';
    Buffer.contents b

  let array pp a =
    let b = Buffer.create 25 in
    Buffer.add_string b "[|";
    Array.iteri (fun i x ->
      if i > 0 then Buffer.add_string b "; ";
      Buffer.add_string b (pp x))
      a;
    Buffer.add_string b "|]";
    Buffer.contents b

  let comap f p x = p (f x)
end

module Iter = struct
  type 'a t = ('a -> unit) -> unit
  let empty _ = ()
  let return x yield = yield x
  let (<*>) a b yield = a (fun f -> b (fun x ->  yield (f x)))
  let (>>=) a f yield = a (fun x -> f x yield)
  let map f a yield = a (fun x -> yield (f x))
  let map2 f a b yield = a (fun x -> b (fun y -> yield (f x y)))
  let (>|=) a f = map f a
  let append a b yield = a yield; b yield
  let (<+>) = append
  let of_list l yield = List.iter yield l
  let of_array a yield = Array.iter yield a
  let pair a b yield = a (fun x -> b(fun y -> yield (x,y)))
  let triple a b c yield = a (fun x -> b (fun y -> c (fun z -> yield (x,y,z))))

  exception IterExit
  let find p iter =
    let r = ref None in
    (try iter (fun x -> if p x then (r := Some x; raise IterExit))
     with IterExit -> ()
    );
    !r
end

module Shrink = struct
  type 'a t = 'a -> 'a Iter.t

  let nil _ = Iter.empty

  (* get closer to 0 *)
  let int x yield =
    if x < -2 || x>2 then yield (x/2); (* faster this way *)
    if x>0 then yield (x-1);
    if x<0 then yield (x+1)

  let option s x = match x with
    | None -> Iter.empty
    | Some x -> Iter.(return None <+> map (fun y->Some y) (s x))

  let string s yield =
    for i =0 to String.length s-1 do
      let s' = Bytes.init (String.length s-1)
        (fun j -> if j<i then s.[j] else s.[j+1])
      in
      yield (Bytes.unsafe_to_string s')
    done

  let array ?shrink a yield =
    for i=0 to Array.length a-1 do
      let a' = Array.init (Array.length a-1)
        (fun j -> if j< i then a.(j) else a.(j+1))
      in
      yield a'
    done;
    match shrink with
    | None -> ()
    | Some f ->
        (* try to shrink each element of the array *)
        for i = 0 to Array.length a - 1 do
          f a.(i) (fun x ->
            let b = Array.copy a in
            b.(i) <- x;
            yield b
          )
        done

  let list ?shrink l yield =
    let rec aux l r = match r with
      | [] -> ()
      | x :: r' ->
          yield (List.rev_append l r');
          aux (x::l) r'
    in
    aux [] l;
    match shrink with
    | None -> ()
    | Some f ->
        let rec aux l r = match r with
          | [] -> ()
          | x :: r' ->
              f x (fun x' -> yield (List.rev_append l (x' :: r')));
              aux (x :: l) r'
        in
        aux [] l

  let pair a b (x,y) yield =
    a x (fun x' -> yield (x',y));
    b y (fun y' -> yield (x,y'))

  let triple a b c (x,y,z) yield =
    a x (fun x' -> yield (x',y,z));
    b y (fun y' -> yield (x,y',z));
    c z (fun z' -> yield (x,y,z'))
end

type 'a arbitrary = {
  gen: 'a Gen.t;
  print: ('a -> string) option; (** print values *)
  small: ('a -> int) option;  (** size of example *)
  shrink: ('a -> 'a Iter.t) option;  (** shrink to smaller examples *)
  collect: ('a -> string) option;  (** map value to tag, and group by tag *)
}

let make ?print ?small ?shrink ?collect gen = {
  gen;
  print;
  small;
  shrink;
  collect;
}

let set_small f o = {o with small=Some f}
let set_print f o = {o with print=Some f}
let set_shrink f o = {o with shrink=Some f}
let set_collect f o = {o with collect=Some f}

let small1 _ = 1

let make_scalar ?print ?collect gen =
  make ~shrink:Shrink.nil ~small:small1 ?print ?collect gen
let make_int ?collect gen =
  make ~shrink:Shrink.int ~small:small1 ~print:Print.int ?collect gen

let adapt_ o gen =
  make ?print:o.print ?small:o.small ?shrink:o.shrink ?collect:o.collect gen

let choose l = match l with
  | [] -> raise (Invalid_argument "quickcheck.choose")
  | l ->
      let a = Array.of_list l in
      adapt_ a.(0)
        (fun st ->
          let arb = a.(RS.int st (Array.length a)) in
          arb.gen st)

let unit : unit arbitrary =
  make ~small:small1 ~shrink:Shrink.nil ~print:(fun _ -> "()") Gen.unit

let bool = make_scalar ~print:string_of_bool Gen.bool
let float = make_scalar ~print:string_of_float Gen.float
let pos_float = make_scalar ~print:string_of_float Gen.pfloat
let neg_float = make_scalar ~print:string_of_float Gen.nfloat

let int = make_int Gen.int
let int_bound n = make_int (Gen.int_bound n)
let int_range a b = make_int (Gen.int_range a b)
let (--) = int_range
let pos_int = make_int Gen.pint
let small_int = make_int Gen.nat
let small_int_corners () = make_int (Gen.nng_corners ())
let neg_int = make_int Gen.neg_int

let int32 = make_scalar ~print:(fun i -> Int32.to_string i ^ "l") Gen.ui32
let int64 = make_scalar ~print:(fun i -> Int64.to_string i ^ "L") Gen.ui64

let char = make_scalar ~print:(sprintf "%C") Gen.char
let printable_char = make_scalar ~print:(sprintf "%C") Gen.printable
let numeral_char = make_scalar ~print:(sprintf "%C") Gen.numeral

let string_gen_of_size size gen =
  make ~shrink:Shrink.string ~small:String.length
    ~print:(sprintf "%S") (Gen.string_size ~gen size)
let string_gen gen =
  make ~shrink:Shrink.string ~small:String.length
    ~print:(sprintf "%S") (Gen.string ~gen)

let string = string_gen Gen.char
let string_of_size size = string_gen_of_size size Gen.char
let small_string = string_gen_of_size Gen.(0--10) Gen.char

let printable_string = string_gen Gen.printable
let printable_string_of_size size = string_gen_of_size size Gen.printable
let small_printable_string = string_gen_of_size Gen.(0--10) Gen.printable

let numeral_string = string_gen Gen.numeral
let numeral_string_of_size size = string_gen_of_size size Gen.numeral

let list_sum_ f l = List.fold_left (fun acc x-> f x+acc) 0 l

let list a =
  (* small sums sub-sizes if present, otherwise just length *)
  let small = _opt_map_or a.small ~f:list_sum_ ~d:List.length in
  let print = _opt_map a.print ~f:Print.list in
  make
    ~small
    ~shrink:(Shrink.list ?shrink:a.shrink)
    ?print
    (Gen.list a.gen)

let list_of_size size a =
  let small = _opt_map_or a.small ~f:list_sum_ ~d:List.length in
  let print = _opt_map a.print ~f:Print.list in
  make
    ~small
    ~shrink:(Shrink.list ?shrink:a.shrink)
    ?print
    (Gen.list_size size a.gen)

let array_sum_ f a = Array.fold_left (fun acc x -> f x+acc) 0 a

let array a =
  let small = _opt_map_or ~d:Array.length ~f:array_sum_ a.small in
  make
    ~small
    ~shrink:(Shrink.array ?shrink:a.shrink)
    ?print:(_opt_map ~f:Print.array a.print)
    (Gen.array a.gen)

let array_of_size size a =
  let small = _opt_map_or ~d:Array.length ~f:array_sum_ a.small in
  make
    ~small
    ~shrink:(Shrink.array ?shrink:a.shrink)
    ?print:(_opt_map ~f:Print.array a.print)
    (Gen.array_size size a.gen)

let pair a b =
  make
    ?small:(_opt_map_2 ~f:(fun f g (x,y) -> f x+g y) a.small b.small)
    ?print:(_opt_map_2 ~f:Print.pair a.print b.print)
    ~shrink:(Shrink.pair (_opt_or a.shrink Shrink.nil) (_opt_or b.shrink Shrink.nil))
    (Gen.pair a.gen b.gen)

let triple a b c =
  make
    ?small:(_opt_map_3 ~f:(fun f g h (x,y,z) -> f x+g y+h z) a.small b.small c.small)
    ?print:(_opt_map_3 ~f:Print.triple a.print b.print c.print)
    ~shrink:(Shrink.triple (_opt_or a.shrink Shrink.nil)
      (_opt_or b.shrink Shrink.nil) (_opt_or c.shrink Shrink.nil))
    (Gen.triple a.gen b.gen c.gen)

let option a =
  let g = Gen.opt a.gen
  and shrink = _opt_map a.shrink ~f:Shrink.option
  and small =
    _opt_map_or a.small ~d:(function None -> 0 | Some _ -> 1)
      ~f:(fun f o -> match o with None -> 0 | Some x -> f x)
  in
  make
    ~small
    ?shrink
    ?print:(_opt_map ~f:Print.option a.print)
    g

(* TODO: explain black magic in this!! *)
let fun1 : 'a arbitrary -> 'b arbitrary -> ('a -> 'b) arbitrary =
  fun a1 a2 ->
    let magic_object = Obj.magic (object end) in
    let gen : ('a -> 'b) Gen.t = fun st ->
      let h = Hashtbl.create 10 in
      fun x ->
        if x == magic_object then
          Obj.magic h
        else
          try Hashtbl.find h x
          with Not_found ->
            let b = a2.gen st in
            Hashtbl.add h x b;
            b in
    let pp : (('a -> 'b) -> string) option = _opt_map_2 a1.print a2.print ~f:(fun p1 p2 f ->
      let h : ('a, 'b) Hashtbl.t = Obj.magic (f magic_object) in
      let b = Buffer.create 20 in
      Hashtbl.iter (fun key value -> Printf.bprintf b "%s -> %s; " (p1 key) (p2 value)) h;
      "{" ^ Buffer.contents b ^ "}"
    ) in
    make
      ?print:pp
      gen

let fun2 gp1 gp2 gp3 = fun1 gp1 (fun1 gp2 gp3)

(* Generator combinators *)

(** given a list, returns generator that picks at random from list *)
let oneofl ?print ?collect xs = make ?print ?collect (Gen.oneofl xs)
let oneofa ?print ?collect xs = make ?print ?collect (Gen.oneofa xs)

(** Given a list of generators, returns generator that randomly uses one of the generators
    from the list *)
let oneof l =
  let gens = List.map (fun a->a.gen) l in
  let first = List.hd l in
  let print = first.print
  and small = first.small
  and collect = first.collect
  and shrink = first.shrink in
  make ?print ?small ?collect ?shrink (Gen.oneof gens)

(** Generator that always returns given value *)
let always ?print x =
  let gen _st = x in
  make ?print gen

(** like oneof, but with weights *)
let frequency ?print ?small ?shrink ?collect l =
  let first = snd (List.hd l) in
  let small = _opt_sum small first.small in
  let print = _opt_sum print first.print in
  let shrink = _opt_sum shrink first.shrink in
  let collect = _opt_sum collect first.collect in
  let gens = List.map (fun (x,y) -> x, y.gen) l in
  make ?print ?small ?shrink ?collect (Gen.frequency gens)

(** Given list of [(frequency,value)] pairs, returns value with probability proportional
    to given frequency *)
let frequencyl ?print ?small l = make ?print ?small (Gen.frequencyl l)
let frequencya ?print ?small l = make ?print ?small (Gen.frequencya l)

let map ?rev f a =
  make
    ?print:(_opt_map_2 rev a.print ~f:(fun r p x -> p (r x)))
    ?small:(_opt_map_2 rev a.small ~f:(fun r s x -> s (r x)))
    ?shrink:(_opt_map_2 rev a.shrink ~f:(fun r g x -> Iter.(g (r x) >|= f)))
    ?collect:(_opt_map_2 rev a.collect ~f:(fun r f x -> f (r x)))
    (fun st -> f (a.gen st))

let map_same_type f a =
  adapt_ a (fun st -> f (a.gen st))

let map_keep_input ?print ?small f a =
  make
    ?print:(match print, a.print with
        | Some f1, Some f2 -> Some (Print.pair f2 f1)
        | Some f, None -> Some (Print.comap snd f)
        | None, Some f -> Some (Print.comap fst f)
        | None, None -> None)
    ?small:(match small, a.small with
        | Some f, _ -> Some (fun (_,y) -> f y)
        | None, Some f -> Some (fun (x,_) -> f x)
        | None, None -> None)
    Gen.(map_keep_input f a.gen)

module TestResult = struct
  type 'a counter_ex = {
    instance: 'a; (** The counter-example(s) *)
    shrink_steps: int; (** How many shrinking steps for this counterex *)
  }

  type 'a failed_state = 'a counter_ex list

  type 'a state =
    | Success
    | Failed of 'a failed_state (** Failed instances *)
    | Error of 'a * exn  (** Error, and instance that triggered it *)

  (* result returned by running a test *)
  type 'a t = {
    mutable state : 'a state;
    mutable count: int;  (* number of tests *)
    mutable count_gen: int; (* number of generated cases *)
    collect_tbl: (string, int) Hashtbl.t lazy_t;
  }

  (* indicate failure on the given [instance] *)
  let fail ?small ~steps:shrink_steps res instance =
    let c_ex = {instance; shrink_steps; } in
    match res.state with
    | Success -> res.state <- Failed [ c_ex ]
    | Error (x, e) ->
        res.state <- Error (x,e); (* same *)
    | Failed [] -> assert false
    | Failed (c_ex' :: _ as l) ->
        match small with
        | Some small ->
            (* all counter-examples in [l] have same size according to [small],
               so we just compare to the first one, and we enforce
               the invariant *)
            begin match Pervasives.compare (small instance) (small c_ex'.instance) with
            | 0 -> res.state <- Failed (c_ex :: l) (* same size: add [c_ex] to [l] *)
            | n when n<0 -> res.state <- Failed [c_ex] (* drop [l] *)
            | _ -> () (* drop [c_ex], not small enough *)
            end
        | _ ->
            (* no [small] function, keep all counter-examples *)
            res.state <-
              Failed (c_ex :: l)

  let error res instance e =
    res.state <- Error (instance, e)
end

module Test = struct
  type 'a cell = {
    count : int; (* number of tests to do *)
    max_gen : int; (* max number of instances to generate (>= count) *)
    max_fail : int; (* max number of failures *)
    law : 'a -> bool; (* the law to check *)
    arb : 'a arbitrary; (* how to generate/print/shrink instances *)
    mutable name : string option; (* name of the law *)
  }

  type t = | Test : 'a cell -> t

  let get_name {name; _} = name
  let set_name c name = c.name <- Some name
  let get_law {law; _} = law
  let get_arbitrary {arb; _} = arb

  let default_count = 100
  let default_max_gen = 300

  let make_cell ?(count=default_count) ?(max_gen=default_max_gen)
  ?(max_fail=1) ?small ?name arb law
  =
    let arb = match small with None -> arb | Some f -> set_small f arb in
    {
      law;
      arb;
      max_gen;
      max_fail;
      name;
      count;
    }

  let make ?count ?max_gen ?max_fail ?small ?name arb law =
    Test (make_cell ?count ?max_gen ?max_fail ?small ?name arb law)


  (** {6 Running the test} *)

  module R = TestResult

  (* state required by {!check} to execute *)
  type 'a state = {
    test: 'a cell;
    rand: Random.State.t;
    mutable res: 'a TestResult.t;
    mutable cur_count: int;  (** number of iterations to do *)
    mutable cur_max_gen: int; (** maximum number of generations allowed *)
    mutable cur_max_fail: int; (** maximum number of counter-examples allowed *)
  }

  let is_done state = state.cur_count <= 0 || state.cur_max_gen <= 0

  let decr_count state =
    state.res.R.count <- state.res.R.count + 1;
    state.cur_count <- state.cur_count - 1

  let new_input state =
    state.res.R.count_gen <- state.res.R.count_gen + 1;
    state.cur_max_gen <- state.cur_max_gen - 1;
    state.test.arb.gen state.rand

  (* statistics on inputs *)
  let collect st i = match st.test.arb.collect with
    | None -> ()
    | Some f ->
        let key = f i in
        let (lazy tbl) = st.res.R.collect_tbl in
        let n = try Hashtbl.find tbl key with Not_found -> 0 in
        Hashtbl.replace tbl key (n+1)

  (* try to shrink counter-ex [i] into a smaller one. Returns
     shrinked value and number of steps *)
  let shrink st i =
    let rec shrink_ st i ~steps = match st.test.arb.shrink with
      | None -> i, steps
      | Some f ->
        let i' = Iter.find
          (fun x ->
            try
              not (st.test.law x)
            with FailedPrecondition -> false
            | _ -> true (* fail test (by error) *)
          ) (f i)
        in
        match i' with
        | None -> i, steps
        | Some i' -> shrink_ st i' ~steps:(steps+1) (* shrink further *)
    in
    shrink_ ~steps:0 st i

  (* [check_state iter gen func] applies [func] repeatedly ([iter] times)
      on output of [gen], and if [func] ever returns false, then the input that
      caused the failure is returned in [Failed].
      If [func input] raises [FailedPrecondition] then  the input is discarded, unless
         max_gen is 0.
      @param max_gen max number of times [gen] is called to replace inputs
        that fail the precondition *)
  let rec check_state state =
    if is_done state then state.res
    else
      let input = new_input state in
      collect state input;
      try
        if state.test.law input
        then (
          (* one test ok *)
          decr_count state;
          check_state state
        ) else handle_fail state input
      with
      | FailedPrecondition when state.cur_max_gen > 0 -> check_state state
      | e -> handle_exn state input e
  (* test failed on [input], which means the law is wrong. Continue if
     we should. *)
  and handle_fail state input =
    (* first, shrink *)
    let input, steps = shrink state input in
    (* fail *)
    decr_count state;
    state.cur_max_fail <- state.cur_max_fail - 1;
    R.fail state.res ~steps input;
    if _is_some state.test.arb.small && state.cur_max_fail > 0
      then check_state state
      else state.res
  (* test raised [e] on [input]; stop immediately *)
  and handle_exn state input e =
    R.error state.res input e;
    state.res

  type 'a callback = string -> 'a cell -> 'a TestResult.t -> unit

  let callback_nil_ _ _ _ = ()

  let name_ cell = match cell.name with
    | None -> "<test>"
    | Some n -> n

  (* main checking function *)
  let check_cell ?(call=callback_nil_) ?(rand=Random.State.make [| 0 |]) cell =
    let state = {
      test=cell;
      rand;
      cur_count=cell.count;
      cur_max_gen=cell.max_gen;
      cur_max_fail=cell.max_fail;
      res = {R.
        state=R.Success; count=0; count_gen=0;
        collect_tbl=lazy (Hashtbl.create 10);
      };
    } in
    let res = check_state state in
    call (name_ cell) cell res;
    res

  exception Test_fail of string * string list
  exception Test_error of string * string * exn

  (* print instance using [arb] *)
  let print_instance arb i = match arb.print with
    | None -> "<instance>"
    | Some pp -> pp i

  let print_c_ex arb c =
    if c.R.shrink_steps > 0
    then Printf.sprintf "%s (after %d shrink steps)"
      (print_instance arb c.R.instance) c.R.shrink_steps
    else print_instance arb c.R.instance

  let pp_print_test_fail name out l =
    let rec pp_list out = function
      | [] -> ()
      | [x] -> Format.fprintf out "%s@," x
      | x :: y -> Format.fprintf out "%s@,%a" x pp_list y
    in
    Format.fprintf out "@[<hv2>test `%s`@ failed on ≥ %d cases:@ @[<v>%a@]@]"
      name (List.length l) pp_list l

  let asprintf fmt =
    let buf = Buffer.create 128 in
    let out = Format.formatter_of_buffer buf in
    Format.kfprintf (fun _ -> Buffer.contents buf) out fmt

  let print_test_fail name l = asprintf "@[<2>%a@]@?" (pp_print_test_fail name) l

  let print_test_error name i e =
    Format.sprintf "@[<2>test `%s`@ raised exception `%s`@ on %s@]"
      name (Printexc.to_string e) i

  let () = Printexc.register_printer
    (function
      | Test_fail (name,l) -> Some (print_test_fail name l)
      | Test_error (name,i,e) -> Some (print_test_error name i e)
      | _ -> None)

  let print_fail arb name l =
    print_test_fail name (List.map (print_c_ex arb) l)

  let print_error arb name (i,e) =
    print_test_error name (print_instance arb i) e

  let check_result cell res = match res.R.state with
    | R.Success -> ()
    | R.Error (i,e) -> raise (Test_error (name_ cell, print_instance cell.arb i, e))
    | R.Failed l ->
        let l = List.map (print_c_ex cell.arb) l in
        raise (Test_fail (name_ cell, l))

  let check_cell_exn ?call ?rand cell =
    let res = check_cell ?call ?rand cell in
    check_result cell res

  let check_exn ?rand (Test cell) = check_cell_exn ?rand cell
end
