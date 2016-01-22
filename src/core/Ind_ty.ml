
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Inductive Types} *)

module T = FOTerm

let section = Util.Section.(make ~parent:zip "ind")

type constructor = {
  cstor_name: ID.t;
  cstor_ty: Type.t;
}

(** {6 Inductive Types} *)

(** An inductive type, along with its set of constructors *)
type t = {
  id: ID.t; (* name *)
  ty_vars: Type.t HVar.t list; (* list of variables *)
  ty_pattern: Type.t; (* equal to  [id ty_vars] *)
  constructors : constructor list;
    (* constructors, all returning [pattern] and containing
       no other type variables than [ty_vars] *)
}

let fail_ fmt = CCFormat.ksprintf fmt ~f:failwith
let invalid_argf_ fmt = CCFormat.ksprintf fmt ~f:invalid_arg

exception AlreadyDeclaredType of ID.t
exception NotAnInductiveType of ID.t
exception NotAnInductiveConstructor of ID.t

let () =
  let spf = CCFormat.sprintf in
  Printexc.register_printer
  (function
    | AlreadyDeclaredType id ->
        Some (spf "%a already declared as an inductive type" ID.pp id)
    | NotAnInductiveType id ->
        Some (spf "%a is not an inductive type" ID.pp id)
    | NotAnInductiveConstructor id ->
        Some (spf "%a is not an inductive constructor" ID.pp id)
    | _ -> None)

exception Payload_ind_type of t
exception Payload_ind_cstor of constructor * t

let type_hd_exn ty =
  let _, ret = Type.open_fun ty in
  match Type.view ret with
  | Type.App (s, _) -> s
  | _ ->
      invalid_argf_ "expected function type, got %a" Type.pp ty

let as_inductive_ty id =
  CCList.find
    (function
      | Payload_ind_type ty -> Some ty
      | _ -> None)
    (ID.payload id)

let as_inductive_ty_exn id = match as_inductive_ty id with
  | Some ty -> ty
  | None -> raise (NotAnInductiveType id)

let is_inductive_ty id =
  match as_inductive_ty id with Some _ -> true | None -> false

let is_inductive_type ty =
  let id = type_hd_exn ty in
  is_inductive_ty id

let as_inductive_type ty =
  let id = type_hd_exn ty in
  as_inductive_ty id

(* declare that the given type is inductive *)
let declare_ty id ~ty_vars constructors =
  Util.debugf ~section 1 "declare inductive type %a" (fun k->k ID.pp id);
  if constructors = []
  then invalid_argf_ "Ind_types.declare_ty %a: no constructors provided" ID.pp id;
  (* check that [ty] is not declared already *)
  List.iter
    (function
      | Payload_ind_type _ -> fail_ "inductive type %a already declared" ID.pp id;
      | _ -> ())
    (ID.payload id);
  let ity = {
    id;
    ty_vars;
    ty_pattern=Type.app id (List.map Type.var ty_vars);
    constructors;
  } in
  (* map the constructors to [ity] too *)
  List.iter
    (fun c ->
      ID.add_payload c.cstor_name (Payload_ind_cstor (c, ity)))
    constructors;
  (* map [id] to [ity] *)
  ID.add_payload id (Payload_ind_type ity);
  ity

(** {6 Constructors} *)

let as_constructor id =
  CCList.find
    (function
      | Payload_ind_cstor (cstor,ity) -> Some (cstor,ity)
      | _ -> None)
    (ID.payload id)

let as_constructor_exn id = match as_constructor id with
  | None -> raise (NotAnInductiveConstructor id)
  | Some x -> x

let is_constructor s =
  match as_constructor s with Some _ -> true | None -> false

let contains_inductive_types t =
  T.Seq.subterms t
  |> Sequence.exists (fun t -> is_inductive_type (T.ty t))