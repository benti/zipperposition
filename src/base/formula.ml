
(*
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 First-order Formulas} *)

module T = ScopedTerm
module Sym = Symbol

type symbol = Sym.t

module type S = sig
  type term

  type t = private ScopedTerm.t

  type form = t

  type sourced_form = t * string * string
    (** form, filename, axiom name *)

  type view = private
    | True
    | False
    | Atom of term
    | And of t list
    | Or of t list
    | Not of t
    | Imply of t * t
    | Equiv of t * t
    | Xor of t * t
    | Eq of term * term
    | Neq of term * term
    | Forall of Type.t * t  (** Quantified formula, with De Bruijn index *)
    | Exists of Type.t * t

  val view : t -> view
    (** View of the formula *)

  val kind : ScopedTerm.Kind.t
  val of_term : ScopedTerm.t -> t option
  val of_term_exn : ScopedTerm.t -> t  (** @raise Invalid_argument *)
  val is_form : ScopedTerm.t -> bool

  include Interfaces.HASH with type t := t
  include Interfaces.ORD with type t := t

  (** {2 Containers} *)

  module Tbl : Hashtbl.S with type key = t
  module Set : Sequence.Set.S with type elt = t
  module Map : Sequence.Map.S with type key = t

  (** {b Caution}: constructors can raise Failure if the types are not
      as expected.
      {!atom} expects a term of type {!Type.o}
      {!eq} and {!neq} expect two terms of the exact same type
  *)

  module Base : sig
    val true_ : t
    val false_ : t
    val atom : term -> t
    val not_ : t -> t
    val and_ : t list -> t
    val or_ : t list -> t
    val imply : t -> t -> t
    val equiv : t -> t -> t
    val xor : t -> t -> t
    val eq : term -> term -> t
    val neq : term -> term -> t

    (** Quantifiers: the term list must be a list of free variables. *)

    val forall : term list -> t -> t
    val exists : term list -> t -> t

    val __mk_forall : varty:Type.t -> t -> t
    val __mk_exists : varty:Type.t -> t -> t
  end

  (** {2 Sequence} *)

  module Seq : sig
    val terms : t -> term Sequence.t
    val vars : t -> term Sequence.t
    val atoms : t -> t Sequence.t
    val symbols : t -> symbol Sequence.t
  end

  (** {2 Combinators} *)

  val map_leaf : (t -> t) -> t -> t
    (** Call the function on leaves (atom,equal,true,false) and replace the
        leaves by their image. The image formulas should {b not} contain
        free De Bruijn indexes (ie, should verify {! db_closed}). *)

  val map : (term -> term) -> t -> t    (** Map on terms *)
  val fold : ('a -> term -> 'a) -> 'a -> t -> 'a  (** Fold on terms *)
  val iter : (term -> unit) -> t -> unit

  val map_depth: ?depth:int ->
                  (int -> term -> term) ->
                  t -> t
    (** Map each term to another term. The number of binders from the root
        of the formula to the term is given to the function. *)

  val map_leaf_depth : ?depth:int ->
                        (int -> t -> t) ->
                        t -> t

  val fold_depth : ?depth:int ->
                ('a -> int -> term -> 'a) ->
                'a -> t -> 'a
    (** Fold on terms, but with an additional argument, the number of
        De Bruijn indexes bound on through the path to the term *)

  val weight : t -> int
    (** Number of 'nodes' of the formula, including the terms *)

  val subterm : term -> t -> bool
    (** [subterm t f] true iff [t] occurs in some term of [f] *)

  val is_atomic : t -> bool   (** No connectives? *)
  val is_ground : t -> bool   (** No variables? *)
  val is_closed : t -> bool   (** All variables bound? *)

  val contains_symbol : Symbol.t -> t -> bool

  val symbols : ?init:Symbol.Set.t -> t -> Symbol.Set.t
    (** Set of symbols occurring in the formula *)

  (** {2 High level operations} *)

  val free_vars : t -> term list (** Set of free vars *)

  val close_forall : t -> t   (** Bind all free variables with forall *)
  val close_exists : t -> t   (** Bind all free variables with exists *)

  val open_forall : ?offset:int -> t -> t
    (** Remove outer forall binders, using fresh vars instead of DB symbols *)

  val open_and : t -> t list
    (** If the formula is an outer conjunction, return the list of elements of
        the conjunction *)

  val open_or : t -> t list

  (** {2 Simplifications} *)

  val flatten : t -> t        (** Flatten AC connectives (or/and) *)
  val simplify : t -> t       (** Simplify the formula *)

  val is_trivial : t -> bool  (** Trivially true formula? *)

  val ac_normal_form : t -> t (** Normal form modulo AC of "or" and "and" *)
  val ac_eq : t -> t -> bool  (** Equal modulo AC? *)

  (** {2 Conversions} TODO

  val to_term : t -> HOTerm.t   (** Conversion to higher-order term *)
  val of_term : HOTerm.t -> t
  *)

  (** {2 IO} *)

  include Interfaces.PRINT with type t := t
  include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := term

  module TPTP : sig
    include Interfaces.PRINT with type t := t
    include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := term
      and type print_hook := print_hook
  end

  (* TODO
  include Interfaces.SERIALIZABLE with type t := t
  *)
end

module type TERM = sig
  type t = private ScopedTerm.t

  val of_term_exn : ScopedTerm.t -> t

  val ty : t -> Type.t

  val size : t -> int

  val kind : ScopedTerm.Kind.t

  include Interfaces.HASH with type t := t
  include Interfaces.ORD with type t := t

  module Seq : sig
    val vars : t -> t Sequence.t
  end

  module Set : Sequence.Set.S with type elt = t

  include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := t
  module TPTP : sig
    include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := t
      and type print_hook := print_hook
  end
end

module Make(MyT : TERM) = struct
  type term = MyT.t

  type t = ScopedTerm.t

  type form = t

  type sourced_form = t * string * string
    (** form, filename, axiom name *)

  let eq = T.eq
  let cmp = T.cmp
  let hash = T.hash

  type view =
    | True
    | False
    | Atom of term
    | And of t list
    | Or of t list
    | Not of t
    | Imply of t * t
    | Equiv of t * t
    | Xor of t * t
    | Eq of term * term
    | Neq of term * term
    | Forall of Type.t * t  (** Quantified formula, with De Bruijn index *)
    | Exists of Type.t * t

  let view t = match T.kind t with
    | kind when kind = MyT.kind ->
      (* atoms aren't formulas! *)
      Atom (MyT.of_term_exn t)
    | T.Kind.Formula subkind when subkind = MyT.kind ->
      (* proper formula *)
      begin match T.view t with
      | T.Const (Sym.Conn Sym.True) -> True
      | T.Const (Sym.Conn Sym.False) -> False
      | T.App (hd, [a]) ->
          begin match T.view hd with
          | T.Const (Sym.Conn Sym.Not) -> Not a
          | T.Const (Sym.Conn Sym.And) -> And [a]
          | T.Const (Sym.Conn Sym.Or) -> Or [a]
          | _ -> assert false
          end
      | T.App (hd, [a; b]) ->
          begin match T.view hd with
          | T.Const (Sym.Conn conn) ->
              begin match conn with
              | Sym.Equiv -> Equiv (a,b)
              | Sym.Xor -> Xor (a,b)
              | Sym.Imply -> Equiv (a,b)
              | Sym.Eq -> Eq (MyT.of_term_exn a, MyT.of_term_exn b)
              | Sym.Neq -> Neq (MyT.of_term_exn a, MyT.of_term_exn b)
              | _ -> assert false
              end
          | _ -> assert false
          end
      | T.App (hd, l) ->
          begin match T.view hd with
          | T.Const (Sym.Conn Sym.And) -> And l
          | T.Const (Sym.Conn Sym.Or) -> Or l
          | _ -> assert false
          end
      | T.Bind (Sym.Conn Sym.Forall, varty, f') ->
          Forall (Type.of_term_exn varty, f')
      | T.Bind (Sym.Conn Sym.Exists, varty, f') ->
          Exists (Type.of_term_exn varty, f')
      | _ -> assert false
      end
    | _ -> failwith "wrong kind for formula"

  let kind = T.Kind.Formula MyT.kind

  let of_term t = match T.kind t with
    | T.Kind.Formula kind when kind = MyT.kind -> Some t
    | _ -> None

  let of_term_exn t = match T.kind t with
    | T.Kind.Formula kind when kind = MyT.kind -> t
    | _ -> raise (Invalid_argument "Formula.of_term_exn")

  let is_form t = match T.kind t with
    | T.Kind.Formula kind when kind = MyT.kind -> true
    | _ -> false

  (** {2 Containers} *)

  module Tbl = Hashtbl.Make(struct
    type t = form
    let equal = eq
    let hash = hash
  end)

  module Set = Sequence.Set.Make(struct
    type t = form
    let compare = cmp
  end)

  module Map = Sequence.Map.Make(struct
    type t = form
    let compare = cmp
  end)

  (* "type" of a formula *)
  let ty = T.const ~kind ~ty:T.tType (Sym.of_string "prop")

  module Base = struct
    let true_ = T.const ~kind ~ty Sym.Base.true_
    let false_ = T.const ~kind ~ty Sym.Base.false_
    let atom (t:term) = (t:>T.t)

    let __not = T.const ~kind ~ty Sym.Base.not_
    let __and = T.const ~kind ~ty Sym.Base.and_
    let __or = T.const ~kind ~ty Sym.Base.or_
    let __imply = T.const ~kind ~ty Sym.Base.imply
    let __equiv = T.const ~kind ~ty Sym.Base.equiv
    let __xor = T.const ~kind ~ty Sym.Base.xor
    let __eq = T.const ~kind ~ty Sym.Base.eq
    let __neq = T.const ~kind ~ty Sym.Base.neq

    let not_ f = T.app ~kind ~ty __not [f]
    let imply f1 f2 = T.app ~kind ~ty __imply [f1; f2]
    let equiv f1 f2 = T.app ~kind ~ty __equiv [f1; f2]
    let xor f1 f2 = T.app ~kind ~ty __xor [f1; f2]

    let __check_same t1 t2 =
      let ty1 = MyT.ty t1 and ty2 = MyT.ty t2 in
      if not (Type.eq ty1 ty2)
        then
          let msg = Util.sprintf
            "Formula.Base.eq: expect same types for %a and %a, got %a and %a"
            (MyT.pp_depth 0) t1 Type.pp ty1 (MyT.pp_depth 0) t2 Type.pp ty2
          in
          raise (Type.Error msg)

    let eq t1 t2 =
      __check_same t1 t2;
      T.app ~kind ~ty __eq ([t1; t2] : term list :> T.t list)

    let neq t1 t2 = T.app ~kind ~ty __neq ([t1; t2] : term list :> T.t list)

    let and_ = function
      | [] -> true_
      | [f] -> f
      | l -> T.app ~kind ~ty __and l

    let or_ = function
      | [] -> false_
      | [f] -> f
      | l -> T.app ~kind ~ty __or l

    let __mk_forall ~(varty:Type.t) f =
      T.bind ~kind ~ty ~varty:(varty:>T.t) Sym.Base.forall f

    let __mk_exists ~(varty:Type.t) f =
      T.bind ~kind ~ty ~varty:(varty:>T.t) Sym.Base.exists f

    let forall vars f =
      List.fold_right
        (fun (v:term) f ->
          let f' = T.DB.replace (T.DB.shift 1 f) ~sub:(v:>T.t) in
          __mk_forall ~varty:(MyT.ty v) f')
        vars f

    let exists vars f =
      List.fold_right
        (fun (v:term) f ->
          let f' = T.DB.replace (T.DB.shift 1 f) ~sub:(v:>T.t) in
          __mk_exists ~varty:(MyT.ty v) f')
        vars f
  end

  (** {2 Combinators} *)

  let rec map_leaf f form = match view form with
    | And l -> Base.and_ (List.map (map_leaf f) l)
    | Or l -> Base.or_ (List.map (map_leaf f) l)
    | Imply (f1, f2) -> Base.imply (map_leaf f f1) (map_leaf f f2)
    | Equiv (f1, f2) -> Base.equiv (map_leaf f f1) (map_leaf f f2)
    | Xor (f1, f2) -> Base.xor (map_leaf f f1) (map_leaf f f2)
    | Not f' -> Base.not_ (map_leaf f f')
    | True
    | False
    | Atom _
    | Neq _
    | Eq _ -> f form  (* replace by image *)
    | Forall (varty,f') -> Base.__mk_forall ~varty (map_leaf f f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (map_leaf f f')

  let map (f:term->term) form =
    map_leaf
      (fun form -> match view form with
        | True
        | False -> form
        | Atom p -> Base.atom (f p)
        | Eq (t1, t2) -> Base.eq (f t1) (f t2)
        | Neq (t1, t2) -> Base.neq (f t1) (f t2)
        | _ -> assert false)
      form

  let rec fold_atom f acc form = match view form with
    | And l
    | Or l -> List.fold_left (fold_atom f) acc l
    | Xor (f1, f2)
    | Imply (f1, f2)
    | Equiv (f1, f2) -> fold_atom f (fold_atom f acc f1) f2
    | Not f' -> fold_atom f acc f'
    | True
    | False -> f acc form
    | Atom _ -> f acc form
    | Eq _
    | Neq _ -> f acc form
    | Forall (_,f')
    | Exists (_,f') -> fold_atom f acc f'

  let fold f acc form =
    fold_atom
      (fun acc form -> match view form with
        | True
        | False -> acc
        | Eq (t1, t2)
        | Neq (t1, t2) -> f (f acc t1) t2
        | Atom p -> f acc p
        | _ -> assert false)
      acc form

  let rec fold f acc form = match view form with
    | And l
    | Or l -> List.fold_left (fold f) acc l
    | Xor (f1, f2)
    | Imply (f1, f2)
    | Equiv (f1, f2) -> fold f (fold f acc f1) f2
    | Not f' -> fold f acc f'
    | True
    | False -> acc
    | Atom p -> f acc p
    | Eq (t1, t2)
    | Neq (t1, t2) -> f (f acc t1) t2
    | Forall (_,f')
    | Exists (_,f') -> fold f acc f'

  let iter f form = fold (fun () t -> f t) () form

  let rec map_depth ?(depth=0) f form = match view form with
    | And l -> Base.and_ (List.map (map_depth ~depth f) l)
    | Or l -> Base.or_ (List.map (map_depth ~depth f) l)
    | Imply (f1, f2) -> Base.imply (map_depth ~depth f f1) (map_depth ~depth f f2)
    | Equiv (f1, f2) -> Base.equiv (map_depth ~depth f f1) (map_depth ~depth f f2)
    | Xor (f1, f2) -> Base.xor (map_depth ~depth f f1) (map_depth ~depth f f2)
    | Not f' -> Base.not_ (map_depth ~depth f f')
    | True
    | False -> form
    | Atom p -> Base.atom (f depth p)
    | Eq (t1, t2) -> Base.eq (f depth t1) (f depth t2)
    | Neq (t1, t2) -> Base.neq (f depth t1) (f depth t2)
    | Forall (varty,f') -> Base.__mk_forall ~varty (map_depth ~depth:(depth+1) f f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (map_depth ~depth:(depth+1) f f')

  let rec map_leaf_depth ?(depth=0) f form = match view form with
    | And l -> Base.and_ (List.map (map_leaf_depth ~depth f) l)
    | Or l -> Base.or_ (List.map (map_leaf_depth ~depth f) l)
    | Imply (f1, f2) -> Base.imply (map_leaf_depth ~depth f f1) (map_leaf_depth ~depth f f2)
    | Equiv (f1, f2) -> Base.equiv (map_leaf_depth ~depth f f1) (map_leaf_depth ~depth f f2)
    | Xor (f1, f2) -> Base.xor (map_leaf_depth ~depth f f1) (map_leaf_depth ~depth f f2)
    | Not f' -> Base.not_ (map_leaf_depth ~depth f f')
    | True
    | False
    | Atom _
    | Neq _
    | Eq _ -> f depth form  (* replace by image *)
    | Forall (varty,f') -> Base.__mk_forall ~varty (map_leaf_depth ~depth:(depth+1) f f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (map_leaf_depth ~depth:(depth+1) f f')

  let fold_depth ?(depth=0) f acc form =
    let rec recurse f acc depth form = match view form with
    | And l
    | Or l -> List.fold_left (fun acc f' -> recurse f acc depth f') acc l
    | Xor (f1, f2)
    | Imply (f1, f2)
    | Equiv (f1, f2) ->
      let acc = recurse f acc depth f1 in
      let acc = recurse f acc depth f2 in
      acc
    | Not f' -> recurse f acc depth f'
    | True
    | False -> acc
    | Atom p -> f acc depth p
    | Neq (t1, t2)
    | Eq (t1, t2) ->
      let acc = f acc depth t1 in
      let acc = f acc depth t2 in
      acc
    | Forall (_, f')
    | Exists (_, f') ->
      recurse f acc (depth+1) f'
    in
    recurse f acc depth form

  let weight f =
    let rec count n f = match view f with
    | True
    | False -> n + 1
    | Not f'
    | Forall (_,f')
    | Exists (_,f') -> count (n+1) f'
    | Neq (t1, t2)
    | Eq (t1, t2) -> n + MyT.size t1 + MyT.size t2
    | Atom p -> n + MyT.size p
    | Or l
    | And l -> List.fold_left count (n+1) l
    | Xor (f1, f2)
    | Imply (f1, f2)
    | Equiv (f1, f2) ->
      let n = count (n+1) f1 in
      count n f2
    in
    count 0 f

  module Seq = struct
    let terms f k = iter k f

    let vars f =
      Sequence.flatMap MyT.Seq.vars (terms f)

    let atoms f k =
      fold_atom
        (fun () atom -> k atom)
        () f

    let symbols f = T.Seq.symbols f
  end

  let subterm t f =
    Sequence.exists (MyT.eq t) (Seq.terms f)

  let is_atomic f = match view f with
    | And _
    | Or _
    | Imply _
    | Equiv _
    | Xor _
    | Not _
    | Forall _
    | Exists _ -> false
    | True
    | False
    | Atom _
    | Eq _
    | Neq _ -> true

  let is_ground f = T.ground f

  let free_vars f =
    Seq.vars f
      |> Sequence.fold (fun set v -> MyT.Set.add v set) MyT.Set.empty
      |> MyT.Set.elements

  let is_closed f =
    match free_vars f with
    | [] -> true
    | _ -> false

  let contains_symbol sy f =
    Sequence.exists (Symbol.eq sy) (Seq.symbols f)

  let symbols ?(init=Symbol.Set.empty) f =
    Sequence.fold (fun set s -> Symbol.Set.add s set) init (Seq.symbols f)

  (** {2 High level operations} *)

  let close_forall f =
    let fv = free_vars f in
    Base.forall fv f

  let close_exists f =
    let fv = free_vars f in
    Base.exists fv f

  let open_forall ?(offset=0) f =
    let offset = max offset (T.Seq.max_var (T.Seq.vars f)) + 1 in
    (* open next forall, replacing it with a fresh var *)
    let rec open_one offset env f = match view f with
    | Forall (varty,f') ->
      let v = T.var ~kind:MyT.kind ~ty:(varty:>T.t) offset in
      let env' = DBEnv.push env v in
      open_one (offset+1) env' f'
    | _ ->
      of_term_exn (T.DB.eval env f)  (* replace *)
    in
    open_one offset DBEnv.empty f

  let rec open_and f = match view f with
    | And l -> Util.list_flatmap open_and l
    | True -> []
    | _ -> [f]

  let rec open_or f = match view f with
    | Or l -> Util.list_flatmap open_or l
    | False -> []
    | _ -> [f]

  (** {2 Simplifications} *)

  let rec flatten f =
    match view f with
    | Or l ->
      let l' = open_or f in
      let l' = List.map flatten l' in
      Base.or_ l'
    | And l ->
      let l' = open_and f in
      let l' = List.map flatten l' in
      Base.and_ l'
    | Imply (f1, f2) -> Base.imply (flatten f1) (flatten f2)
    | Equiv (f1, f2) -> Base.equiv (flatten f1) (flatten f2)
    | Xor (f1, f2) -> Base.xor (flatten f1) (flatten f2)
    | Not f' -> Base.not_ (flatten f')
    | Forall (varty,f') -> Base.__mk_forall ~varty (flatten f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (flatten f')
    | True
    | False
    | Atom _
    | Eq _
    | Neq _ -> f

  let simplify f =
    let rec simplify ~depth f = match view f with
      | And l ->
        let l' = List.map (simplify ~depth) l in
        flatten (Base.and_ l')
      | Or l ->
        let l' = List.map (simplify ~depth) l in
        flatten (Base.or_ l')
      | Forall (_,f')
      | Exists (_,f') when not (T.DB.contains f' 0) ->
        simplify ~depth (of_term_exn (T.DB.unshift ~depth 1 f'))
      | Forall (varty,f') -> Base.__mk_forall ~varty (simplify ~depth:(depth+1) f')
      | Exists (varty,f') -> Base.__mk_exists ~varty (simplify ~depth:(depth+1) f')
      | Neq (a, b) when MyT.eq a b -> Base.false_
      | Eq (a,b) when MyT.eq a b -> Base.true_
      | Neq _
      | Eq _ -> f
      | Atom _
      | True
      | False -> f
      | Not f' ->
          let f' = simplify ~depth f' in
          begin match view f' with
          | Xor (f1, f2) -> Base.equiv f1 f2
          | Equiv (f1, f2) -> Base.xor f1 f2
          | Neq (t1, t2) -> Base.eq t1 t2
          | Eq (t1, t2) -> Base.neq t1 t2
          | Imply (f1, f2) -> Base.and_ [f1; simplify ~depth (Base.not_ f2)]
          | Not f' -> f'
          | _ -> Base.not_ f'
          end
      | Imply (a, b) ->
          begin match view a, view b with
          | True, _ -> simplify ~depth b
          | False, _
          | _, True -> Base.true_
          | _, False -> simplify ~depth (Base.not_ a)
          | _ -> Base.imply (simplify ~depth a) (simplify ~depth b)
          end
      | Equiv (a, b) ->
          begin match view a, view b with
          | _ when eq a b -> Base.true_
          | True, _ -> simplify ~depth b
          | _, True -> simplify ~depth a
          | False, _ -> simplify ~depth (Base.not_ b)
          | _, False -> simplify ~depth (Base.not_ a)
          | _ -> Base.equiv (simplify ~depth a) (simplify ~depth b)
          end
      | Xor (f1, f2) -> Base.xor (simplify ~depth f1) (simplify ~depth f2) (* TODO *)
    in simplify ~depth:0 f

  let rec is_trivial f = match view f with
    | True -> true
    | Neq _
    | Atom _ -> false
    | Eq (l,r) -> MyT.eq l r
    | False -> false
    | Imply (a, b) when eq a Base.false_ -> true
    | Equiv (l,r) -> eq l r
    | Xor (l, r) -> false
    | Or l -> List.exists is_trivial l
    | And _
    | Imply _
    | Not _ -> false
    | Exists (_,f')
    | Forall (_,f') -> is_trivial f'

  let ac_normal_form f =
    let rec recurse f = match view f with
    | True
    | False
    | Atom _ -> f
    | Imply (f1, f2) -> Base.imply (recurse f1) (recurse f2)
    | Equiv (f1, f2) -> Base.equiv (recurse f1) (recurse f2)
    | Xor (f1, f2) -> Base.xor (recurse f1) (recurse f2)
    | Not f' -> Base.not_ (recurse f')
    | Eq (t1, t2) ->
      (* put bigger term first *)
      begin match MyT.cmp t1 t2 with
      | n when n >= 0 -> f
      | _ -> Base.eq t2 t1
      end
    | Neq (t1, t2) ->
      (* put bigger term first *)
      begin match MyT.cmp t1 t2 with
      | n when n >= 0 -> f
      | _ -> Base.neq t2 t1
      end
    | And l ->
      let l' = List.map recurse l in
      let l' = List.sort compare l' in
      Base.and_ l'
    | Or l ->
      let l' = List.map recurse l in
      let l' = List.sort compare l' in
      Base.or_ l'
    | Forall (varty,f') -> Base.__mk_forall ~varty (recurse f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (recurse f')
    in
    recurse (flatten f)

  let ac_eq f1 f2 =
    let f1 = ac_normal_form f1 in
    let f2 = ac_normal_form f2 in
    eq f1 f2

  (** {2 Conversion} FIXME

  let __cache_f2t = FCache.create 513

  let to_term f =
    let module T = HOTerm in
    FCache.with_cache_rec __cache_f2t
      (fun to_term f ->
      match f.form with
      | True -> T.true_term
      | False -> T.false_term
      | And l -> T.Base.and__list (List.map to_term l)
      | Or l -> T.Base.or__list (List.map to_term l)
      | Equiv (f1, f2) -> T.Base.equiv (to_term f1) (to_term f2)
      | Imply (f1, f2) -> T.Base.imply (to_term f1) (to_term f2)
      | Equal (t1, t2) -> T.Base.eq (T.curry t1) (T.curry t2)
      | Not f' -> T.Base.not_ (to_term f')
      | Forall (ty,f') -> T.__mk_forall ~varty:ty (to_term f')
      | Exists (ty,f') -> T.__mk_exists ~varty:ty (to_term f')
      | Atom p -> T.curry p)
      f

  let of_term t =
    let module T = HOTerm in
    let rec recurse t = match t.T.term with
    | _ when t == T.true_term -> mk_true
    | _ when t == T.false_term -> mk_false
    | T.At ({T.term=T.Const s}, _, [{T.term=T.Lambda t'} as lam]) when S.eq s S.forall_symbol ->
      let ty = T.lambda_var_ty lam in
      __mk_forall ~ty (recurse t')
    | T.At ({T.term=T.Const s}, _, [{T.term=T.Lambda t'} as lam]) when S.eq s S.exists_symbol ->
      let ty = T.lambda_var_ty lam in
      __mk_exists ~ty (recurse t')
    | T.Lambda _ -> failwith "FOFormula.of_term: unexpected lambda term"
    | T.Const s -> Base.atom (FOTerm.mk_const s)
    | T.Var _ | T.BoundVar _ -> failwith "F.of_term: not first-order, var under formula"
    | T.At ({T.term=T.Const s}, _, l) when S.eq s S.and_symbol ->
        Base.and_ (List.map recurse l)
    | T.At ({T.term=T.Const s}, _, l) when S.eq s S.or_symbol ->
        Base.or_ (List.map recurse l)
    | T.At ({T.term=T.Const s}, _, [a; b]) when S.eq s S.equiv_symbol ->
      Base.equiv (recurse a) (recurse b)
    | T.At ({T.term=T.Const s}, _, [a; b]) when S.eq s S.imply_symbol ->
      Base.imply (recurse a) (recurse b)
    | T.At ({T.term=T.Const s}, _, [a; b]) when S.eq s S.or_symbol ->
      Base.and_ [recurse a; recurse b]
    | T.At ({T.term=T.Const s}, _, [a; b]) when S.eq s S.and_symbol ->
      Base.or_ [recurse a; recurse b]
    | T.At ({T.term=T.Const s}, _, [a; b]) when S.eq s S.eq_symbol ->
      Base.eq (T.uncurry a) (T.uncurry b)
    | T.At ({T.term=T.Const s}, _, [t']) when S.eq s S.not_symbol ->
      Base.not_ (recurse t')
    | _ -> Base.atom (T.uncurry t)
    in
    recurse t
  *)

  (** {2 IO} *)

  type print_hook = int -> (Buffer.t -> term -> unit) -> Buffer.t -> term -> bool

  let pp_depth ?(hooks=[]) depth buf f =
    let depth = ref depth in
    (* outer formula *)
    let rec pp_outer buf f = match view f with
    | True -> Buffer.add_string buf "true"
    | False -> Buffer.add_string buf "false"
    | Atom t -> (MyT.pp_depth ~hooks !depth) buf t
    | Neq (t1, t2) ->
      MyT.pp_depth ~hooks !depth buf t1;
      Buffer.add_string buf " ≠ ";
      MyT.pp_depth ~hooks !depth buf t2
    | Eq (t1, t2) ->
      MyT.pp_depth ~hooks !depth buf t1;
      Buffer.add_string buf " = ";
      MyT.pp_depth ~hooks !depth buf t2
    | Xor(f1, f2) ->
      pp_inner buf f1; Buffer.add_string buf " <~> "; pp_inner buf f2
    | Equiv (f1, f2) ->
      pp_inner buf f1; Buffer.add_string buf " <=> "; pp_inner buf f2
    | Imply (f1, f2) ->
      pp_inner buf f1; Buffer.add_string buf " => "; pp_inner buf f2
    | Not f' -> Buffer.add_string buf "¬ "; pp_inner buf f'
    | Forall (ty,f') ->
      let v = !depth in
      incr depth;
      Printf.bprintf buf "∀ Y%d: %a. %a" v Type.pp ty pp_inner f';
      decr depth
    | Exists (ty, f') ->
      let v = !depth in
      incr depth;
      Printf.bprintf buf "∃ Y%d: %a. %a" v Type.pp ty pp_inner f';
      decr depth
    | And l -> Util.pp_list ~sep:" ∧ " pp_inner buf l
    | Or l -> Util.pp_list ~sep:" ∨ " pp_inner buf l
    and pp_inner buf f = match view f with
    | And _
    | Or _
    | Equiv _
    | Xor _
    | Imply _ ->
      (* cases where ambiguities could arise *)
      Buffer.add_char buf '('; pp_outer buf f; Buffer.add_char buf ')';
    | _ -> pp_outer buf f
    in
    pp_outer buf (flatten f)

  let pp = pp_depth 0

  let to_string f = Util.on_buffer pp f

  let fmt fmt f = Format.pp_print_string fmt (to_string f)

  module TPTP = struct
    let pp_depth ?(hooks=[]) depth buf f =
      let depth = ref 0 in
      (* outer formula *)
      let rec pp_outer buf f = match view f with
      | True -> Buffer.add_string buf "$true"
      | False -> Buffer.add_string buf "$false"
      | Atom t -> (MyT.TPTP.pp_depth !depth) buf t
      | Neq (t1, t2) ->
        (MyT.TPTP.pp_depth !depth) buf t1;
        Buffer.add_string buf " != ";
        (MyT.TPTP.pp_depth !depth) buf t2
      | Eq (t1, t2) ->
        (MyT.TPTP.pp_depth !depth) buf t1;
        Buffer.add_string buf " = ";
        (MyT.TPTP.pp_depth !depth) buf t2
      | Xor (f1, f2) ->
        pp_inner buf f1; Buffer.add_string buf " <~> "; pp_inner buf f2
      | Equiv (f1, f2) ->
        pp_inner buf f1; Buffer.add_string buf " <=> "; pp_inner buf f2
      | Imply (f1, f2) ->
        pp_inner buf f1; Buffer.add_string buf " => "; pp_inner buf f2
      | Not f' -> Buffer.add_string buf "~ "; pp_inner buf f'
      | Forall (ty,f') ->
        let v = !depth in
        incr depth;
        if Type.eq ty Type.TPTP.i
          then Printf.bprintf buf "![Y%d]: %a" v pp_inner f'
          else Printf.bprintf buf "![Y%d:%a]: %a" v Type.pp ty pp_inner f';
        decr depth
      | Exists (ty, f') ->
        let v = !depth in
        incr depth;
        if Type.eq ty Type.TPTP.i
          then Printf.bprintf buf "?[Y%d]: %a" v pp_inner f'
          else Printf.bprintf buf "?[Y%d:%a]: %a" v Type.pp ty pp_inner f';
        decr depth
      | And l -> Util.pp_list ~sep:" & " pp_inner buf l
      | Or l -> Util.pp_list ~sep:" | " pp_inner buf l
      and pp_inner buf f = match view f with
      | And _
      | Or _
      | Equiv _
      | Xor _
      | Imply _ ->
        (* cases where ambiguities could arise *)
        Buffer.add_char buf '('; pp_outer buf f; Buffer.add_char buf ')';
      | _ -> pp_outer buf f
      in
      pp_outer buf (flatten f)

    let pp = pp_depth 0

    let to_string f = Util.on_buffer pp f

    let fmt fmt f = Format.pp_print_string fmt (to_string f)
  end

  (* FIXME
  let bij =
    Bij.(map
      ~inject:to_term
      ~extract:of_term
      HOTerm.bij)
  *)
end

module FO = Make(FOTerm)

module Map(From : S)(To : S) = struct
  let rec map f form = match From.view form with
    | _ -> assert false (* TODO *)
end
