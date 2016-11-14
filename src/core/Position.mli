(* This file is free software, part of Libzipperposition. See file "license" for more details. *)

(** {1 Positions in terms, clauses...} *)

(** A position is a path in a tree *)
type t =
  | Stop
  | Type of t (** Switch to type *)
  | Left of t (** Left term in curried application *)
  | Right of t (** Right term in curried application, and subterm of binder *)
  | Head of t (** Head of uncurried term *)
  | Arg of int * t (** argument term in uncurried term, or in multiset *)
  | Body of t (** Body of binder *)

type position = t

val stop : t
val left : t -> t
val right : t -> t
val type_ : t -> t
val left : t -> t
val right : t -> t
val head : t -> t
val arg : int -> t -> t

val opp : t -> t
(** Opposite position, when it makes sense (left/right) *)

val rev : t -> t
(** Reverse the position *)

val append : t -> t -> t
(** Append two positions *)

val compare : t -> t -> int
val eq : t -> t -> bool
val hash : t -> int

include Interfaces.PRINT with type t := t

(** {2 Position builder} *)

module Build : sig
  type t

  val empty : t
  (** Empty builder (position=[Stop]) *)

  val to_pos : t -> position
  (** Extract current position *)

  val of_pos : position -> t
  (** Start from a given position *)

  val prefix : position -> t -> t
  (** Prefix the builder with the given position *)

  val suffix : t -> position -> t
  (** Append position at the end *)

  (** All the following builders add elements to the {b end}
      of the builder. This is useful when a term is traversed and
      positions of subterms are needed, since positions are
      easier to build in the wrong order (leaf-to-root). *)

  val type_ : t -> t

  val left : t -> t
  (** Add [left] at the end *)

  val right : t -> t
  (** Add [left] at the end *)

  val body : t -> t

  val head : t -> t

  val arg : int -> t -> t
  (** Arg position at the end *)

  include Interfaces.PRINT with type t := t
end