
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Constraint for a Clause} *)

open Libzipperposition
open Hornet_types

type t = c_constraint

val empty : t

val is_trivial : t -> bool
(** Anything is a solution *)

val is_absurd: t -> bool
(** No solution *)

val add_dismatch : Dismatching_constr.t -> t -> t
(** Add another dismatching constraint to this *)

val combine : t -> t -> t
(** Conjunction of two constraints *)

val apply_subst :
  renaming:Subst.Renaming.t ->
  Subst.t ->
  t Scoped.t ->
  t

val variant :
  subst:Subst.t ->
  t Scoped.t ->
  t Scoped.t ->
  Subst.t Sequence.t
(** Substitution that make these two constraints the same *)

include Interfaces.PRINT with type t := t
