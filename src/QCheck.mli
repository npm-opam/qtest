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

(** The library takes inspiration from Haskell's QuickCheck library. The
rough idea is that the programer describes invariants that values of
a certain type need to satisfy ("properties"), as functions from this type
to bool. She also needs to desribe how to generate random values of the type,
so that the property is tried and checked on a number of random instances.

This explains the organization of this module:

- {! 'a arbitrary} is used to describe how to generate random values,
  shrink them (make counter-examples as small as possible), print
  them, etc. Auxiliary modules such as {!Gen}, {!Print}, and {!Shrink}
  can be used along with {!make} to build one's own arbitrary instances.

- {!Test} is used to describe a single test, that is, a property of
  type ['a -> bool] combined with an ['a arbitrary] that is used to generate
  the test cases for this property. Optional parameters
  allow to specify the random generator state, number of instances to generate
  and test, etc.


Examples:

  - List.rev is involutive:

{[

let test =
  QCheck.(Test.make ~count:1000
   (list int) (fun l -> List.rev (List.rev l) = l));;

QCheck.Test.run_exn test;;
]}

  - Not all lists are sorted (false property that will fail. The 15 smallest
    counter-example lists will be printed):

{[
let test = QCheck.(
  Test.make
    ~count:10_000 ~max_fail:3
    (list small_int)
    (fun l -> l = List.sort compare l));;
QCheck.Test.check_exn test;;
]}


  - generate 20 random trees using {! Arbitrary.fix} :

{[
type tree = Leaf of int | Node of tree * tree

let leaf x = Leaf x
let node x y = Node (x,y)

let g = QCheck.Gen.(sized @@ fix
  (fun self n -> match n with
    | 0 -> map leaf nat
    | n ->
      frequency
        [1, map leaf nat;
         2, map2 node (self (n/2)) (self (n/2))]
    ))

Gen.generate ~n:20 g;;
]}

More complex and powerful combinators can be found in Gabriel Scherer's
{!Generator} module. Its documentation can be found
{{:http://gasche.github.io/random-generator/doc/Generator.html } here}.
*)

val (==>) : bool -> bool -> bool
(** [b1 ==> b2] is the logical implication [b1 => b2]
    ie [not b1 || b2] (except that it is strict and will interact
    better with {!Test.check_exn} and the likes, because they will know
    the precondition was not satisfied.).
*)

(** {2 Generate Random Values} *)
module Gen : sig
  type 'a t = Random.State.t -> 'a
  (** A random generator for values of type 'a *)

  type 'a sized = int -> Random.State.t -> 'a
  (** Random generator with a size bound *)

  val return : 'a -> 'a t
  val (>>=) : 'a t -> ('a -> 'b t) -> 'b t
  val (<*>) : ('a -> 'b) t -> 'a t -> 'b t
  val map : ('a -> 'b) -> 'a t -> 'b t
  val map2 : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
  val map3 : ('a -> 'b -> 'c -> 'd) -> 'a t -> 'b t -> 'c t -> 'd t
  val map_keep_input : ('a -> 'b) -> 'a t -> ('a * 'b) t
  val (>|=) : 'a t -> ('a -> 'b) -> 'b t

  val oneof : 'a t list -> 'a t
  val oneofl : 'a list -> 'a t
  val oneofa : 'a array -> 'a t
  val frequency : (int * 'a t) list -> 'a t
  val frequencyl : (int * 'a) list -> 'a t
  val frequencya : (int * 'a) array -> 'a t

  val shuffle_a : 'a array -> unit t
  (** Shuffle the array in place *)

  val shuffle_l : 'a list -> 'a list t

  val unit: unit t
  val bool: bool t

  val float: float t
  val pfloat : float t (** positive float *)
  val nfloat : float t (** negative float *)

  val nat : int t (** small nat *)
  val neg_int : int t (** negative int *)
  val pint : int t (** positive uniform int *)
  val int : int t (** uniform int *)
  val small_int : int t (** Synonym to {!nat} *)
  val int_bound : int -> int t (** Uniform within [0... bound] *)
  val int_range : int -> int -> int t (** Uniform within [low,high] *)
  val (--) : int -> int -> int t (** Synonym to {!int_range} *)

  val ui32 : int32 t
  val ui64 : int64 t

  val list : 'a t -> 'a list t
  val list_size : int t -> 'a t -> 'a list t
  val list_repeat : int -> 'a t -> 'a list t

  val array : 'a t -> 'a array t
  val array_size : int t -> 'a t -> 'a array t
  val array_repeat : int -> 'a t -> 'a array t

  val opt : 'a t -> 'a option t

  val pair : 'a t -> 'b t -> ('a * 'b) t
  val triple : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
  val quad : 'a t -> 'b t -> 'c t -> 'd t -> ('a * 'b * 'c * 'd) t

  val char : char t
  val printable : char t
  val numeral : char t

  val string_size : ?gen:char t -> int t -> string t
  val string : ?gen:char t -> string t
  val small_string : ?gen:char t -> string t

  val sized : 'a sized -> 'a t

  val fix : ('a sized -> 'a sized) -> 'a sized (** Fixpoint; size decreases *)

  (** Example:
  {[
  type tree = Leaf of int | Node of tree * tree

  let leaf x = Leaf x
  let node x y = Node (x,y)

  let g = QCheck.Gen.(sized @@ fix
    (fun self n -> match n with
      | 0 -> map leaf nat
      | n ->
        frequency
          [1, map leaf nat;
           2, map2 node (self (n/2)) (self (n/2))]
      ))

  ]}

  *)

  val generate : ?rand:Random.State.t -> n:int -> 'a t -> 'a list
  (** [generate ~n g] generates [n] instances of [g] *)

  val generate1 : ?rand:Random.State.t -> 'a t -> 'a
  (** [generate1 g] generates one instance of [g] *)
end

(** {2 Pretty printing} *)

(** {2 Show Values} *)
module Print : sig
  type 'a t = 'a -> string

  val int : int t
  val bool : bool t
  val float : float t
  val char : char t
  val string : string t
  val option : 'a t -> 'a option t

  val pair : 'a t -> 'b t -> ('a*'b) t
  val triple : 'a t -> 'b t -> 'c t -> ('a*'b*'c) t
  val quad : 'a t -> 'b t -> 'c t -> 'd t -> ('a*'b*'c*'d) t

  val list : 'a t -> 'a list t
  val array : 'a t -> 'a array t

  val comap : ('a -> 'b) -> 'b t -> 'a t
end

(** {2 Iterators}

    Compatible with the library "sequence". An iterator [i] is simply
    a function that accepts another function [f] (of type ['a -> unit])
    and calls [f] on a sequence of elements [f x1; f x2; ...; f xn]. *)
module Iter : sig
  type 'a t = ('a -> unit) -> unit

  val empty : 'a t
  val return : 'a -> 'a t
  val (<*>) : ('a -> 'b) t -> 'a t -> 'b t
  val (>>=) : 'a t -> ('a -> 'b t) -> 'b t
  val map : ('a -> 'b) -> 'a t -> 'b t
  val map2 : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
  val (>|=) : 'a t -> ('a -> 'b) -> 'b t
  val append : 'a t -> 'a t -> 'a t
  val (<+>) : 'a t -> 'a t -> 'a t (** Synonym to {!append} *)
  val of_list : 'a list -> 'a t
  val of_array : 'a array -> 'a t
  val pair : 'a t -> 'b t -> ('a * 'b) t
  val triple : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
  val find : ('a -> bool) -> 'a t -> 'a option
end

(** {2 Shrink Values}

    Shrinking is used to reduce the size of a counter-example. It tries
    to make the counter-example smaller by decreasing it, or removing
    elements, until the property to test holds again; then it returns the
    smallest value that still made the test fail *)
module Shrink : sig
  type 'a t = 'a -> 'a Iter.t
  (** Given a counter-example, return an iterator on smaller versions
      of the counter-example *)

  val nil : 'a t
  (** No shrink *)

  val int : int t
  val option : 'a t -> 'a option t
  val string : string t
  val array : ?shrink:'a t -> 'a array t
  val list : ?shrink:'a t -> 'a list t

  val pair : 'a t -> 'b t -> ('a * 'b) t
  val triple : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
end

(** {2 Arbitrary}

    A value of type ['a arbitrary] glues together a random generator,
    and optional functions for shrinking, printing, computing the size,
    etc. It is the "normal" way of describing how to generate
    values of a given type, to be then used in tests (see {!Test}) *)

type 'a arbitrary = {
  gen: 'a Gen.t;
  print: ('a -> string) option; (** print values *)
  small: ('a -> int) option;  (** size of example *)
  shrink: ('a Shrink.t) option;  (** shrink to smaller examples *)
  collect: ('a -> string) option;  (** map value to tag, and group by tag *)
}
(** a value of type ['a arbitrary] is an object with a method for generating random
    values of type ['a], and additional methods to compute the size of values,
    print them, and possibly shrink them into smaller counterexamples

    {b NOTE} the collect field is unstable and might be removed, or
    moved into {!Test}.
*)

val make :
  ?print:'a Print.t ->
  ?small:('a -> int) ->
  ?shrink:'a Shrink.t ->
  ?collect:('a -> string) ->
  'a Gen.t -> 'a arbitrary
(** Builder for arbitrary. Default is to only have a generator, but other
    arguments can be added *)

val set_print : 'a Print.t -> 'a arbitrary -> 'a arbitrary
val set_small : ('a -> int) -> 'a arbitrary -> 'a arbitrary
val set_shrink : 'a Shrink.t -> 'a arbitrary -> 'a arbitrary
val set_collect : ('a -> string) -> 'a arbitrary -> 'a arbitrary

val choose : 'a arbitrary list -> 'a arbitrary
(** Choose among the given list of generators. The list must not
  be empty; if it is Invalid_argument is raised. *)

val unit : unit arbitrary
(** always generates [()], obviously. *)

val bool : bool arbitrary
(** uniform boolean generator *)

val float : float arbitrary
(* FIXME: does not generate nan nor infinity I think *)
(** generates regular floats (no nan and no infinities) *)

val pos_float : float arbitrary
(** positive float generator (no nan and no infinities) *)

val neg_float : float arbitrary
(** negative float generator (no nan and no infinities) *)

val int : int arbitrary
(** int generator. Uniformly distributed *)

val int_bound : int -> int arbitrary
(** [int_bound n] is uniform between [0] and [n] included *)

val int_range : int -> int -> int arbitrary
(** [int_range a b] is uniform between [a] and [b] included. [b] must be
    larger than [a]. *)

val (--) : int -> int -> int arbitrary
(** Synonym to {!int_range} *)

val int32 : int32 arbitrary
(** int32 generator. Uniformly distributed *)

val int64 : int64 arbitrary
(** int generator. Uniformly distributed *)

val pos_int : int arbitrary
(** positive int generator. Uniformly distributed *)

val small_int : int arbitrary
(** positive int generator. The probability that a number is chosen
    is roughly an exponentially decreasing function of the number.
*)

val small_int_corners : unit -> int arbitrary
(** As [small_int], but each newly created generator starts with
 a list of corner cases before falling back on random generation. *)

val neg_int : int arbitrary
(** negative int generator. The distribution is similar to that of
    [small_int], not of [pos_int].
*)

val char : char arbitrary
(** Uniformly distributed on all the chars (not just ascii or
    valid latin-1) *)

val printable_char : char arbitrary
(* FIXME: describe which subset *)
(** uniformly distributed over a subset of chars *)

val numeral_char : char arbitrary
(** uniformy distributed over ['0'..'9'] *)

val string_gen_of_size : int Gen.t -> char Gen.t -> string arbitrary

val string_gen : char Gen.t -> string arbitrary
(** generates strings with a distribution of length of [small_int] *)

val string : string arbitrary
(** generates strings with a distribution of length of [small_int]
    and distribution of characters of [char] *)

val small_string : string arbitrary
(** Same as {!string} but with a small length (that is, [0--10]) *)

val string_of_size : int Gen.t -> string arbitrary
(** generates strings with distribution of characters if [char] *)

val printable_string : string arbitrary
(** generates strings with a distribution of length of [small_int]
    and distribution of characters of [printable_char] *)

val printable_string_of_size : int Gen.t -> string arbitrary
(** generates strings with distribution of characters of [printable_char] *)

val small_printable_string : string arbitrary

val numeral_string : string arbitrary
(** generates strings with a distribution of length of [small_int]
    and distribution of characters of [numeral_char] *)

val numeral_string_of_size : int Gen.t -> string arbitrary
(** generates strings with a distribution of characters of [numeral_char] *)

val list : 'a arbitrary -> 'a list arbitrary
(** generates lists with length generated by [small_int] *)

val list_of_size : int Gen.t -> 'a arbitrary -> 'a list arbitrary
(** generates lists with length from the given distribution *)

val array : 'a arbitrary -> 'a array arbitrary
(** generates arrays with length generated by [small_int] *)

val array_of_size : int Gen.t -> 'a arbitrary -> 'a array arbitrary
(** generates arrays with length from the given distribution *)

val pair : 'a arbitrary -> 'b arbitrary -> ('a * 'b) arbitrary
(** combines two generators into a generator of pairs *)

val triple : 'a arbitrary -> 'b arbitrary -> 'c arbitrary -> ('a * 'b * 'c) arbitrary
(** combines three generators into a generator of 3-uples *)

val option : 'a arbitrary -> 'a option arbitrary
(** choose between returning Some random value, or None *)

val fun1 : 'a arbitrary -> 'b arbitrary -> ('a -> 'b) arbitrary
(** generator of functions of arity 1.
    The functions are always pure and total functions:
    - when given the same argument (as decided by Pervasives.(=)), it returns the same value
    - it never does side effects, like printing or never raise exceptions etc.
    The functions generated are really printable.
*)

val fun2 : 'a arbitrary -> 'b arbitrary -> 'c arbitrary -> ('a -> 'b -> 'c) arbitrary
(** generator of functions of arity 2. The remark about [fun1] also apply
    here.
*)

val oneofl : ?print:'a Print.t -> ?collect:('a -> string) ->
             'a list -> 'a arbitrary
(** Pick an element randomly in the list *)

val oneofa : ?print:'a Print.t -> ?collect:('a -> string) ->
             'a array -> 'a arbitrary
(** Pick an element randomly in the array *)

val oneof : 'a arbitrary list -> 'a arbitrary
(** Pick a generator among the list, randomly *)

val always : ?print:'a Print.t -> 'a -> 'a arbitrary
(** Always return the same element *)

val frequency : ?print:'a Print.t -> ?small:('a -> int) ->
                ?shrink:'a Shrink.t -> ?collect:('a -> string) ->
                (int * 'a arbitrary) list -> 'a arbitrary
(** Similar to {!oneof} but with frequencies *)

val frequencyl : ?print:'a Print.t -> ?small:('a -> int) ->
                (int * 'a) list -> 'a arbitrary
(** Same as {!oneofl}, but each element is paired with its frequency in
    the probability distribution (the higher, the more likely) *)

val frequencya : ?print:'a Print.t -> ?small:('a -> int) ->
                (int * 'a) array -> 'a arbitrary
(** Same as {!frequencyl}, but with an array *)

val map : ?rev:('b -> 'a) -> ('a -> 'b) -> 'a arbitrary -> 'b arbitrary
(** [map f a] returns a new arbitrary instance that generates values using
    [a#gen] and then transforms them through [f].
    @param rev if provided, maps values back to type ['a] so that the printer,
      shrinker, etc. of [a] can be used. We assume [f] is monotonic in
      this case (that is, smaller inputs are transformed into smaller outputs).
*)

val map_same_type : ('a -> 'a) -> 'a arbitrary -> 'a arbitrary
(** Specialization of [map] when the transformation preserves the type, which
   makes shrinker, printer, etc. still relevant *)

val map_keep_input :
  ?print:'b Print.t -> ?small:('b -> int) ->
  ('a -> 'b) -> 'a arbitrary -> ('a * 'b) arbitrary
(** [map_keep_input f a] generates random values from [a], and maps them into
    values of type ['b] using the function [f], but it also keeps  the
    original value.
    For shrinking, it is assumed that [f] is monotonic and that smaller input
      values will map into smaller values
    @param print optional printer for the [f]'s output
*)

(** {2 Tests} *)

module TestResult : sig
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
end

module Test : sig
  type 'a cell
  (** A single property test *)

  val make_cell :
    ?count:int -> ?max_gen:int -> ?max_fail:int -> ?small:('a -> int) ->
    ?name:string -> 'a arbitrary -> ('a -> bool) -> 'a cell
  (** [make arb prop] builds a test that checks property [prop] on instances
      of the generator [arb].
     @param name the name of the test
     @param max_gen maximum number of times the generation function is called
      to replace inputs that do not satisfy preconditions
     @param max_fail maximum number of failures before we stop generating
      inputs. This is useful if shrinking takes too much time.
     @param small kept for compatibility reasons; if provided, replaces
       the field [arbitrary.small].
  *)

  val get_arbitrary : 'a cell -> 'a arbitrary
  val get_law : 'a cell -> ('a -> bool)
  val get_name : _ cell -> string option
  val set_name : _ cell -> string -> unit

  type t = Test : 'a cell -> t
  (** Same as ['a cell], but masking the type parameter. This allows to
      put tests on different types in the same list of tests. *)

  val make :
    ?count:int -> ?max_gen:int -> ?max_fail:int -> ?small:('a -> int) ->
    ?name:string -> 'a arbitrary -> ('a -> bool) -> t
  (** [make arb prop] builds a test that checks property [prop] on instances
      of the generator [arb].
      See {!make_cell} for a description of the parameters.
  *)

  (** {6 Running the test} *)

  exception Test_fail of string * string list
  (** Exception raised when a test failed, with the list of counter-examples.
      [Test_fail (name, l)] means test [name] failed on elements of [l] *)

  exception Test_error of string * string * exn
  (** Exception raised when a test raised an exception [e], with
      the sample that triggered the exception.
      [Test_error (name, i, e)] means [name] failed on [i] with exception [e] *)

  val print_instance : 'a arbitrary -> 'a -> string
  val print_c_ex : 'a arbitrary -> 'a TestResult.counter_ex -> string
  val print_fail : 'a arbitrary -> string -> 'a TestResult.counter_ex list -> string
  val print_error : 'a arbitrary -> string -> 'a * exn -> string
  val print_test_fail : string -> string list -> string
  val print_test_error : string -> string -> exn -> string

  val check_result : 'a cell -> 'a TestResult.t -> unit
  (** [check_result cell res] checks that [res] is [Ok _], and returns unit.
      Otherwise, it raises some exception
      @raise Test_error if [res = Error _]
      @raise Test_error if [res = Failed _] *)

  type 'a callback = string -> 'a cell -> 'a TestResult.t -> unit
  (** Callback executed after each test has been run.
      [f name cell res] means test [cell], named [name], gave [res] *)

  val check_cell :
    ?call:'a callback ->
    ?rand:Random.State.t -> 'a cell -> 'a TestResult.t
  (** [check ~rand test] generates up to [count] random
      values of type ['a] using [arbitrary] and the random state [st]. The
      predicate [law] is called on them and if it returns [false] or raises an
      exception then we have a counter example for the [law].

      @param call function called on each test case, with the result
      @return the result of the test
  *)

  val check_cell_exn :
    ?call:'a callback ->
    ?rand:Random.State.t -> 'a cell -> unit
  (** Same as {!check_cell} but calls  {!check_result} on the result.
      @raise Test_error if [res = Error _]
      @raise Test_error if [res = Failed _] *)

  val check_exn : ?rand:Random.State.t -> t -> unit
  (** Same as {!check_cell} but calls  {!check_result} on the result.
      @raise Test_error if [res = Error _]
      @raise Test_error if [res = Failed _] *)
end
