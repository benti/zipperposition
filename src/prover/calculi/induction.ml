
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Induction through Cut} *)

open Libzipperposition

module Lits = Literals
module TI = InnerTerm
module T = FOTerm
module Su = Substs
module Ty = Type

module type S = Induction_intf.S

let section = Util.Section.make ~parent:Const.section "induction"
let section_guess = Util.Section.make ~parent:Const.section "lemma_guess"

let stats_lemmas = Util.mk_stat "induction.inductive_lemmas"
let stats_guess_lemmas_absurd = Util.mk_stat "induction.guess_lemmas_absurd"
let stats_guess_lemmas_trivial = Util.mk_stat "induction.guess_lemmas_trivial"
let stats_guess_lemmas = Util.mk_stat "induction.guess_lemmas"
let stats_min = Util.mk_stat "induction.assert_min"

let prof_guess_lemma = Util.mk_profiler "induction.guess_lemma"
let prof_check_lemma = Util.mk_profiler "induction.check_lemma"

let k_enable : bool Flex_state.key = Flex_state.create_key()
let k_lemma_guess : bool Flex_state.key = Flex_state.create_key()
let k_lemma_gen_depth : int Flex_state.key = Flex_state.create_key()
let k_ind_depth : int Flex_state.key = Flex_state.create_key()

(* TODO
 in any ground inductive clause C[n]<-Gamma, containing inductive [n]:
   - find path [p], if any (empty at worst)
   - extract context C[]
   - find coverset of [n]
   - for every [n' < n] in the coverset, strengthen the path
     (i.e. if there is [c=t, D[]] in the path with the proper
       type, add [not D[n']], because [n' < n ... < c])
   - add C[t] <- [n=t · p], Gamma
     for every [t] in coverset
   - add boolean clause  [n=t1] or [n=t2] .. or [n=tk] <= Gamma
     where coverset = {t1, t2, ... tk}

  rule to make trivial any clause with >= 2 incompatible path literals
*)

module Cst_set = CCSet.Make(struct
    type t = Ind_cst.cst
    let compare = Ind_cst.cst_compare
  end)

(* scan terms for inductive constants *)
let scan_terms (seq:T.t Sequence.t) : Cst_set.t =
  seq
  |> Sequence.flat_map Ind_cst.find_cst_in_term
  |> Cst_set.of_seq

(** {2 Guess new Lemmas} *)

module Make_guess_lemma
    (E : Env.S)(A : Avatar_intf.S with module E = E) : sig
  val inf_guess_lemma : E.generate_rule
end = struct
  module C = E.C
  module SubsumptionIndex = FeatureVector.Make(struct
      type t = Literals.t
      let compare = Literals.compare
      let to_lits c = Array.map Literal.Conv.to_form c |> Sequence.of_array
    end)

  let section = section_guess

  type lemma_candidate = Literals.t list

  (* set of all lemmas so far, to check if a new candidate lemma
     has already been tried *)
  let all_candidates_ = ref (SubsumptionIndex.empty ())

  (* update [all_candidates_] when a lemma is added *)
  let () =
    Signal.on_every A.on_lemma
      (fun cut ->
         let cs = cut.A.cut_pos |> List.map (fun c -> C.lits c) in
         all_candidates_ := SubsumptionIndex.add_list !all_candidates_ cs)

  let pp_lemma out (l:lemma_candidate) =
    Format.fprintf out "{@[<v>%a@]}" (Util.pp_list Literals.pp) l

  (* check lemma on small instances. It returns [true] iff none of the
     instances reduces to [false] *)
  let small_check (lemma:lemma_candidate): bool =
    (* generate instances of [lits]. If [last=true], instantiating variables
       with parametrized constructors is forbidden (must return a leaf) *)
    let gen_instances ~(last:bool) (lits:Literals.t): Literals.t Sequence.t =
      let subst_add subst v t =
        Substs.FO.bind subst ((v:Type.t HVar.t:>TI.t HVar.t),0) (t,0)
      and subst_add_ty subst v ty =
        Substs.Ty.bind subst ((v:Type.t HVar.t:>TI.t HVar.t),0) (ty,0)
      and subst_mem subst v =
        Substs.mem subst ((v:Type.t HVar.t:>TI.t HVar.t),0)
      and subst_apply_ty subst ty =
        Substs.Ty.apply_no_renaming subst (ty,0)
      in
      let rec aux offset subst vars = match vars with
        | [] ->
          let renaming = E.Ctx.renaming_clear() in
          Sequence.return (Literals.apply_subst ~renaming subst (lits,0))
        | v :: vars' when subst_mem subst v ->
          (* ignore bound variables *)
          aux offset subst vars'
        | v :: vars' ->
          begin match Ind_ty.as_inductive_type (HVar.ty v) with
            | None when Type.equal (HVar.ty v) Type.prop ->
              (* try [true] and [false] *)
              Sequence.of_list [T.true_; T.false_]
              |> Sequence.flat_map
                (fun b ->
                   let subst = subst_add subst v b in
                   aux offset subst vars')
            | None -> aux offset subst vars' (* ignore [v] *)
            | Some ({ Ind_ty.ty_constructors; ty_vars; _ }, ind_ty_args) ->
              assert (List.length ty_vars = List.length ind_ty_args);
              let ind_ty_args' = List.map (subst_apply_ty subst) ind_ty_args in
              (* try to replace [v] by each constructor *)
              Sequence.of_list ty_constructors
              |> Sequence.flat_map
                (fun {Ind_ty.cstor_ty=c_ty; cstor_name=c_id} ->
                   let n, _, _ = Type.open_poly_fun c_ty in
                   assert (n = List.length ty_vars);
                   let c_ty_args, _ =
                     Type.apply c_ty ind_ty_args'
                     |> Type.open_fun
                   in
                   if last && c_ty_args <> []
                   then Sequence.empty (* fail *)
                   else (
                     (* fresh variables as arguments to the constructor *)
                     let sub_vars =
                       List.mapi
                         (fun i ty' -> HVar.make ~ty:ty' (i+offset) |> T.var)
                         c_ty_args
                     in
                     let t =
                       T.app_full
                         (T.const ~ty:c_ty c_id)
                         ind_ty_args'
                         sub_vars
                     in
                     let subst = subst_add subst v t in
                     aux (offset+List.length c_ty_args) subst vars'
                   )
                )
          end
      in
      let vars = Literals.vars lits in
      (* replace type variables by [prop], easy to test *)
      let ty_vars = List.filter (fun v -> Type.is_tType (HVar.ty v)) vars in
      let subst =
        List.fold_left
          (fun subst v -> subst_add_ty subst v Type.prop)
          Substs.empty
          ty_vars
      in
      (* offset to allocate new variables without collision *)
      let offset = 1 + T.Seq.max_var (Sequence.of_list vars) in
      aux offset subst vars
    in
    Util.debugf ~section 3 "@[<hv2>small_check lemma@ @[%a@]@]"
      (fun k->k (Util.pp_list Literals.pp_vars) lemma);
    Sequence.of_list lemma
    |> Sequence.flat_map (gen_instances ~last:false) (* depth 1 *)
    |> Sequence.flat_map (gen_instances ~last:false) (* depth 2 *)
    |> Sequence.flat_map (gen_instances ~last:true) (* close leaves *)
    |> Sequence.for_all
      (fun lits ->
         let c = C.create_a ~trail:Trail.empty lits ProofStep.mk_trivial in
         let ds, _ = E.all_simplify c in
         let res = not (List.exists C.is_empty ds) in
         Util.debugf ~section 5
           "@[<hv2>... small_check case@ @[%a@]@ simplified: (@[%a@])@ pass: %B@]"
           (fun k->k C.pp c (Util.pp_list C.pp) ds res);
         res
      )

  (* do only a few steps of inferences for checking if a candidate lemma
     is trivial/absurd *)
  let max_steps_ = 20

  exception Lemma_yields_false of C.t

  (* check that [lemma] is not obviously absurd or trivial, by making a few steps of
     superposition inferences between [lemma] and the Active Set.
     The strategy here is set of support: no inference between clauses of [lemma]
     and no inferences among active clauses, just between active clauses and
     those derived from [lemma]. Inferences with trails are dropped because
     the lemma should be inconditionally true. *)
  let check_not_absurd_or_trivial (lemma:lemma_candidate): bool =
    let q : C.t Queue.t = Queue.create() in (* clauses waiting *)
    let push_c c = Queue.push c q in
    let n : int ref = ref 0 in (* number of steps *)
    let trivial = ref true in
    List.iter
      (fun lits ->
         let c = C.create_a ~trail:Trail.empty lits ProofStep.mk_trivial in
         if not (E.is_trivial c) then push_c c)
      lemma;
    try
      while not (Queue.is_empty q) && !n < max_steps_ do
        incr n;
        let c = Queue.pop q in
        let c, _ = E.simplify c in
        assert (C.trail c |> Trail.is_empty);
        (* check for empty clause *)
        if C.is_empty c then raise (Lemma_yields_false c)
        else if E.is_trivial c then ()
        else (
          trivial := false; (* at least one clause does not simplify to [true] *)
          (* now make inferences with [c] and push non-trivial clauses to [q] *)
          E.generate c
          |> Sequence.filter_map
            (fun new_c ->
               let new_c, _ = E.simplify new_c in
               (* discard trivial/conditional clauses; scan for empty clauses *)
               if not (Trail.is_empty (C.trail new_c)) then None
               else if E.is_trivial new_c then None
               else if C.is_empty new_c then raise (Lemma_yields_false new_c)
               else Some new_c)
          |> Sequence.iter push_c
        )
      done;
      Util.debugf ~section 2
        "@[<2>lemma @[%a@]@ apparently not absurd (after %d steps; trivial:%B)@]"
        (fun k->k pp_lemma lemma !n !trivial);
      if !trivial then Util.incr_stat stats_guess_lemmas_trivial;
      not !trivial
    with Lemma_yields_false c ->
      assert (C.is_empty c);
      Util.debugf ~section 2
        "@[<2>lemma @[%a@] absurd:@ leads to empty clause %a (after %d steps)@]"
        (fun k->k pp_lemma lemma C.pp c !n);
      Util.incr_stat stats_guess_lemmas_absurd;
      false

  let check_not_already_tried (lemma:lemma_candidate): bool =
    let check_lits lits =
      SubsumptionIndex.retrieve_alpha_equiv_c !all_candidates_ lits
      |> Sequence.is_empty
    in
    let res = List.for_all check_lits lemma in
    if not res then (
      Util.debugf ~section 5 "@[lemma @[%a@]@ already tried@]" (fun k->k pp_lemma lemma)
    );
    res

  (* some checks that [l] should be considered as a lemma *)
  let is_acceptable_lemma_ l : bool =
    check_not_already_tried l &&
    small_check l &&
    check_not_absurd_or_trivial l

  let is_acceptable_lemma x = Util.with_prof prof_check_lemma is_acceptable_lemma_ x

  (** {6 Hipspec-like enumeration of possible Lemmas} *)

  (* TODO: try classic lemmas like transitivity on predicates [tau,tau -> prop]
     where [tau] is inductive?
     Or even try implication (instead of equality) *)

  (* is this term made only of constructors and variables? *)
  let cstors_only (t:T.t): bool =
    T.Seq.subterms t
    |> Sequence.for_all
      (fun t -> match T.view t with
         | T.Const id -> Ind_ty.is_constructor id
         | T.Var _ | T.DB _ | T.App _ | T.AppBuiltin _ -> true)

  (* [t] head symbol is a function that is not a constructor *)
  let starts_with_fun (t:T.t): bool = match T.head t with
    | None -> false
    | Some id -> not (Ind_ty.is_constructor id)

  (* simple criterion for determining if [t1 = t2] is a possible lemma? *)
  let is_acceptable_eq (t1:T.t) (t2:T.t) =
    Type.equal (T.ty t1) (T.ty t2)
    &&
    not (T.is_var t1 && T.is_var t2)
    &&
    let vars1 = T.vars t1 in
    let vars2 = T.vars t2 in
    let ground1 = T.VarSet.is_empty vars1 in
    let ground2 = T.VarSet.is_empty vars2 in
    (* both not ground, need some quantification; but if they both
       have variables, one side must include the variables of the
       other side *)
    not (ground1 && ground2) &&
    ( T.VarSet.subset vars1 vars2 ||
      T.VarSet.subset vars2 vars1 )
    &&
    (* at least one function is required *)
    not (cstors_only t1 && cstors_only t2)
    &&
    (starts_with_fun t1 || starts_with_fun t2)

  (* stream of type variables *)
  let ty_vars_stream: Type.t HVar.t LazyList.t =
    LazyList.of_fun (fun i -> HVar.make ~ty:Type.tType i |> CCOpt.return)

  (* never generate terms with more than 3 variables *)
  let max_vars_gen = 3

  (* generate terms that can occur in an equational (or relational) lemma,
     from the signature, up to given depth *)
  let generate_terms ~depth (funs:Signature.t): T.Set.t =
    let open Sequence.Infix in
    (* generate terms of [depth] that have type [ty] *)
    let rec aux_by_ty ~depth vars (ty:Type.t): T.t Sequence.t =
      assert (depth >= 0);
      Signature.Seq.to_seq funs
      |> Sequence.filter_map
        (fun (id,ty_f) ->
           let n, ty_args, _ = Type.open_poly_fun ty_f in
           if depth=0 && ty_args<>[] then None (* too deep *)
           else Some (n,id,ty_f))
      |> Sequence.flat_map
        (fun (n_ty_vars,id_f,ty_f) ->
           let ty_vars =
             ty_vars_stream |> LazyList.take n_ty_vars
             |> LazyList.to_list |> List.map Type.var
           in
           let ty_args, ty_ret = Type.apply ty_f ty_vars |> Type.open_fun in
           begin match
               try Some (Unif.Ty.matching ~pattern:(ty_ret, 1) (ty,0))
               with Unif.Fail -> None
           with
             | None -> Sequence.empty
             | Some subst ->
               (* the return type of [f] matches [ty].
                  Now, instantiate the type arguments and fill term arguments
                  by recursing, if not too deep *)
               let ty_vars =
                 List.map
                   (fun v -> Substs.Ty.apply_no_renaming subst (v,1))
                   ty_vars
               and ty_args =
                 List.map
                   (fun ty -> Substs.Ty.apply_no_renaming subst (ty,1))
                   ty_args
               in
               aux_l ~depth:(depth-1) vars ty_args >|= fun args ->
               T.app_full (T.const ~ty:ty_f id_f) ty_vars args
           end)

    (* pick a variable in [vars] that has the proper type *)
    and pick_var vars (ty:Type.t): T.t Sequence.t =
      let vars_of_ty =
        T.VarSet.to_seq vars
        |> Sequence.filter (fun v -> Type.equal (HVar.ty v) ty)
      in
      let num_vars = T.VarSet.cardinal vars in
      let new_ =
        if T.VarSet.cardinal vars < max_vars_gen
        then Sequence.return (HVar.make ~ty num_vars) (* can add another var *)
        else Sequence.empty
      in
      Sequence.append new_ vars_of_ty |> Sequence.map T.var

    (* generate a list of terms corresponding to the types *)
    and aux_l ~depth vars (tys:Type.t list): T.t list Sequence.t =
      match tys with
        | [] -> Sequence.return []
        | ty :: tys' ->
          (* to get a term of type [ty], search in [vars] and in signature *)
          Sequence.append
            (pick_var vars ty)
            (aux_by_ty ~depth vars ty)
          >>= fun t ->
          (* add variables of [t] to the list *)
          let vars = T.VarSet.union vars (T.vars t) in
          (* compute rest of the list *)
          aux_l ~depth vars tys' >|= fun tail ->
          t :: tail
    in
    (* generate terms that are not variables.
       @param vars set of variables we can re-use *)
    let aux_non_vars ~depth vars: T.t Sequence.t =
      Signature.Seq.to_seq funs
      |> Sequence.flat_map
        (fun (id_f,ty_f) ->
           let n, _, _ = Type.open_poly_fun ty_f in
           (* make type variables *)
           let ty_vars =
             ty_vars_stream |> LazyList.take n |> LazyList.to_list |> List.map Type.var
           in
           (* [ty_f] applied to the fresh type variables *)
           let ty_args, _ = Type.apply ty_f ty_vars |> Type.open_fun in
           aux_l ~depth:(depth-1) vars ty_args >|= fun args ->
           T.app_full (T.const ~ty:ty_f id_f) ty_vars args
        )
    in
    aux_non_vars ~depth T.VarSet.empty
    |> Sequence.flat_map
      (* add the variables of [t] themselves *)
      (fun t -> Sequence.cons t (T.Seq.vars t |> Sequence.map T.var))
    |> T.Set.of_seq

  (* generate lemma candidates up to a certain depth *)
  let generate_up_to ~depth (funs:Signature.t): lemma_candidate Sequence.t =
    (* generate terms, only keep the totally simplified ones *)
    let terms =
      generate_terms ~depth funs
      |> T.Set.filter
        (fun t ->
           let new_t = E.simplify_term t in
           Format.printf "term `@[%a@]` (keep: %B)@." T.pp t (SimplM.is_same new_t);
           SimplM.is_same new_t)
    in
    (* generate the non-ordered pairs that might be relevant equalities *)
    Sequence.product (T.Set.to_seq terms) (T.Set.to_seq terms)
    |> Sequence.filter (fun (t1,t2) -> T.compare t1 t2 < 0)
    |> Sequence.filter (fun (t1,t2) -> is_acceptable_eq t1 t2)
    |> Sequence.map (fun (t1,t2) -> [[| Literal.mk_eq t1 t2 |]])

  (** {6 Creation of lemmas, Inference Rule} *)

  (* check if lemma is relevant/redundant/acceptable, and if yes
     then turn it into clauses *)
  let check_and_add_lemma (lemma:lemma_candidate): C.t list =
    (* if [box f] already exists or is too deep, no need to re-do inference *)
    if is_acceptable_lemma lemma
    then (
      (* introduce cut now *)
      let proof = ProofStep.mk_trivial in
      let cut = A.introduce_cut lemma proof in
      A.add_lemma cut;
      let clauses = cut.A.cut_pos @ cut.A.cut_neg in
      List.iter (fun c -> C.set_flag SClause.flag_lemma c true) clauses;
      Util.incr_stat stats_guess_lemmas;
      Util.debugf ~section 2
        "@[<2>guessed lemma@ @[<hv0>%a@]@]"
        (fun k->k (Util.pp_list C.pp) clauses);
      clauses
    )
    else []

  (* functions in the signature that are not skolems and take
     and return inductive types *)
  let funs_ : Signature.t lazy_t = lazy (
    let module CC = Classify_cst in
    let res =
      E.Ctx.signature ()
      |> ID.Map.filter
        (fun id ty ->
           begin match CC.classify id with
             | CC.DefinedCst _ | CC.Other | CC.Cstor _ -> true
             | CC.Projector _ | CC.Inductive_cst _ | CC.Ty _ -> false
           end
           &&
           (
             let _, args, ret = Type.open_poly_fun ty in
             List.for_all Ind_ty.is_inductive_type args && Ind_ty.is_inductive_type ret
           )
        )
    in
    Util.debugf ~section 2 "@[<2>generate lemmas from signature@ @[%a@]@]"
      (fun k->k Signature.pp res);
    res
  )

  let generate_lemmas ~depth ~funs (): C.t list =
    generate_up_to ~depth funs
    |> Sequence.flat_map_l check_and_add_lemma
    |> Sequence.to_rev_list

  let first_ = ref true

  (* generate some lemmas from the signature *)
  let inf_guess_lemma_ (full:bool): C.t list =
    let lazy funs = funs_ in
    (* do something only if full check, or if we've not been called yet *)
    if full || !first_ then (
      first_ := false;
      let depth = E.flex_get k_lemma_gen_depth in
      Util.debugf ~section 2 "start guessing lemmas (depth %d)…" (fun k->k depth);
      generate_lemmas ~depth ~funs ()
    )
    else []

  let inf_guess_lemma ~full () =
    Util.with_prof prof_guess_lemma inf_guess_lemma_ full
end

(** {2 Perform Induction} *)

module Make
(E : Env.S)
(A : Avatar_intf.S with module E = E)
= struct
  module Env = E
  module Ctx = E.Ctx
  module C = E.C
  module BoolBox = BBox
  module BoolLit = BoolBox.Lit

  (* scan clauses for ground terms of an inductive type,
     and declare those terms *)
  let scan_clause c : Cst_set.t =
    C.lits c
    |> Lits.Seq.terms
    |> scan_terms

  let is_eq_ ~path (t1:Ind_cst.cst) (t2:Ind_cst.case) ctxs =
    let p = Ind_cst.path_cons t1 t2 ctxs path in
    BoolBox.inject_case p

  (* TODO: rephrase this in the context of induction *)
  (* exhaustivity (inference):
    if some term [t : tau] is maximal in a clause, [tau] is inductive,
    and [t] was never split on, then introduce
    [t = c1(...) or t = c2(...) or ... or t = ck(...)] where the [ci] are
    constructors of [tau], and [...] are new Skolems of [t];
    if [t] is ground then Avatar splitting (with xor) should apply directly
      instead, as an optimization, with [k] unary clauses and 1 bool clause
  *)

  (* data required for asserting that a constant is the smallest one
     taht makes a conjunction of clause contexts true in the model *)
  type min_witness = {
    mw_cst: Ind_cst.cst;
      (* the constant *)
    mw_generalize_on: Ind_cst.cst list;
      (* list of other constants we can generalize in the strengthening.
         E.g. in [not p(a,b)], with [mw_cst=a], [mw_generalize_on=[b]],
         we obtain [not p(0,b)], [not p(s(a'),b)], [p(a',X)] where [b]
         was generalized *)
    mw_contexts: ClauseContext.t list;
      (* the conjunction of contexts for which [cst] is minimal
         (that is, in the model, any term smaller than [cst] makes at
         least one context false) *)
    mw_coverset : Ind_cst.cover_set;
      (* minimality should be asserted for each case of the coverset *)
    mw_path: Ind_cst.path;
      (* path leading to this *)
    mw_proof: ProofStep.t;
      (* proof for the result *)
    mw_trail: Trail.t;
      (* trail to carry *)
  }

  (* recover the (possibly empty) path from a boolean trail *)
  let path_of_trail trail : Ind_cst.path =
    Trail.to_seq trail
    |> Sequence.filter_map BBox.as_case
    |> Sequence.max ~lt:(fun a b -> Ind_cst.path_dominates b a)
    |> CCOpt.get Ind_cst.path_empty

  (* the rest of the trail *)
  let trail_rest trail : Trail.t =
    Trail.filter
      (fun lit -> match BBox.as_case lit with
         | None -> true
         | Some _ -> false)
      trail

  (* TODO: incremental strenghtening.
     - when expanding a coverset in clauses_of_min_witness, see if there
       are other constants in the path with same type, in which case
     strenghten! *)

  (* replace the constants by fresh variables *)
  let generalize_lits (lits:Lits.t) ~(generalize_on:Ind_cst.cst list) : Lits.t =
    if generalize_on=[] then lits
    else (
      let offset = (Lits.Seq.vars lits |> T.Seq.max_var) + 1 in
      (* (constant -> variable) list *)
      let pairs =
        List.mapi
          (fun i c ->
             let ty = Ind_cst.cst_ty c in
             let id = Ind_cst.cst_id c in
             T.const ~ty id, T.var (HVar.make ~ty (i+offset)))
          generalize_on
      in
      Util.debugf ~section 5 "@[<2>generalize_lits `@[%a@]`:@ subst (@[%a@])@]"
        (fun k->k Lits.pp lits CCFormat.(list (pair T.pp T.pp)) pairs);
      Lits.map
        (fun t ->
           List.fold_left
             (fun t (cst,var) -> T.replace ~old:cst ~by:var t)
             t pairs)
        lits
    )

  (* for each member [t] of the cover set:
     for each ctx in [mw.mw_contexts]:
      - add ctx[t] <- [cst=t]
      - for each [t' subterm t] of same type, add clause ~[ctx[t']] <- [cst=t]
    @param path the current induction branch
    @param trail precondition to this minimality
  *)
  let clauses_of_min_witness ~trail mw : (C.t list * BoolBox.t list list) =
    let b_lits = ref [] in
    let clauses =
      Ind_cst.cover_set_cases ~which:`All mw.mw_coverset
      |> Sequence.flat_map
        (fun (case:Ind_cst.case) ->
           let b_lit = is_eq_ mw.mw_cst case mw.mw_contexts ~path:mw.mw_path in
           CCList.Ref.push b_lits b_lit;
           (* clauses [ctx[case] <- b_lit] *)
           let pos_clauses =
             List.map
               (fun ctx ->
                  let t = Ind_cst.case_to_term case in
                  let lits = ClauseContext.apply ctx t in
                  C.create_a lits mw.mw_proof ~trail:(Trail.add b_lit mw.mw_trail))
               mw.mw_contexts
           in
           (* clauses [CNF(¬ And_i ctx_i[t']) <- b_lit] for
              each t' subterm of case, with generalization on other
              inductive constants *)
           let neg_clauses =
             Ind_cst.case_sub_constants case
             |> Sequence.filter_map
               (fun sub ->
                  (* only keep sub-constants that have the same type as [cst] *)
                  let sub = Ind_cst.cst_to_term sub in
                  let ty = Ind_cst.cst_ty mw.mw_cst in
                  if Type.equal (T.ty sub) ty
                  then Some sub else None)
             |> Sequence.flat_map
               (fun sub ->
                  (* for each context, apply it to [sub] and negate its
                     literals, obtaining a DNF of [¬ And_i ctx_i[t']];
                     then turn DNF into CNF *)
                  let clauses =
                    mw.mw_contexts
                    |> Util.map_product
                      ~f:(fun ctx ->
                         let lits = ClauseContext.apply ctx sub in
                         let lits = Array.map Literal.negate lits in
                         [Array.to_list lits])
                    |> List.map
                      (fun l ->
                         let lits =
                           Array.of_list l
                           |> generalize_lits ~generalize_on:mw.mw_generalize_on
                         in
                         C.create_a lits mw.mw_proof
                           ~trail:(Trail.add b_lit mw.mw_trail))
                  in
                  Sequence.of_list clauses)
            |> Sequence.to_rev_list
           in
           (* all new clauses *)
           let res = List.rev_append pos_clauses neg_clauses in
           Util.debugf ~section 2
             "@[<2>minimality of `%a`@ in case `%a` \
              @[generalize_on (@[%a@])@]:@ @[<hv>%a@]@]"
             (fun k-> k
                 Ind_cst.pp_cst mw.mw_cst T.pp (Ind_cst.case_to_term case)
                 (Util.pp_list Ind_cst.pp_cst) mw.mw_generalize_on
                 (Util.pp_list C.pp) res);
           Sequence.of_list res)
      |> Sequence.to_rev_list
    in
    (* boolean constraint(s) *)
    let b_clauses =
      (* trail => \Or b_lits *)
      let pre = trail |> Trail.to_list |> List.map BoolLit.neg in
      let post = !b_lits in
      [ pre @ post ]
    in
    clauses, b_clauses

  (* ensure the proper declarations are done for this constant *)
  let decl_cst_ cst =
    Util.debugf ~section 3 "@[<2>declare ind.cst. `%a`@]" (fun k->k Ind_cst.pp_cst cst);
    Ind_cst.declarations_of_cst cst
    |> Sequence.iter (fun (id,ty) -> Ctx.declare id ty)

  (* [cst] is the minimal term for which contexts [ctxs] holds, returns
     clauses expressing that, and assert boolean constraints *)
  let assert_min
      ~trail ~proof ~(generalize_on:Ind_cst.cst list) ctxs (cst:Ind_cst.cst) =
    let path = path_of_trail trail in
    let trail' = trail_rest trail in
    match Ind_cst.cst_cover_set cst with
      | Some set when not (Ind_cst.path_contains_cst path cst) ->
        decl_cst_ cst;
        let mw = {
          mw_cst=cst;
          mw_generalize_on=generalize_on;
          mw_contexts=ctxs;
          mw_coverset=set;
          mw_path=path;
          mw_proof=proof;
          mw_trail=trail';
        } in
        let clauses, b_clauses = clauses_of_min_witness ~trail mw in
        A.Solver.add_clauses ~proof b_clauses;
        Util.debugf ~section 2 "@[<2>add boolean constraints@ @[<hv>%a@]@ proof: %a@]"
          (fun k->k (Util.pp_list BBox.pp_bclause) b_clauses
              ProofPrint.pp_normal_step proof);
        Util.incr_stat stats_min;
        clauses
      | Some _ (* path already contains [cst] *)
      | None -> []  (* too deep for induction *)

  (* TODO: trail simplification that removes all path literals except
     the longest? *)

  (* checks whether the trail is trivial, that is:
     - contains two literals [i = t1] and [i = t2] with [t1], [t2]
        distinct cover set members, or
     - two literals [loop(i) minimal by a] and [loop(i) minimal by b], or
     - two literals [C in loop(i)], [D in loop(j)] if i,j do not depend
        on one another *)
  let trail_is_trivial trail =
    let seq = Trail.to_seq trail in
    (* all boolean literals that express paths *)
    let relevant_cases = Sequence.filter_map BoolBox.as_case seq in
    (* are there two distinct incompatible paths in the trail? *)
    Sequence.product relevant_cases relevant_cases
    |> Sequence.exists
      (fun (p1, p2) ->
         let res =
           not (Ind_cst.path_equal p1 p2) &&
           not (Ind_cst.path_dominates p1 p2) &&
           not (Ind_cst.path_dominates p2 p1)
         in
         if res
         then (
           Util.debugf ~section 4
             "@[<2>trail@ @[%a@]@ is trivial because of@ \
              {@[@[%a@],@,@[%a@]}@]@]"
             (fun k->k C.pp_trail trail Ind_cst.pp_path p1 Ind_cst.pp_path p2)
         );
         res)

  (* TODO: only do this when the clause already has some induction
     in its trail (must comes from lemma/goal) *)
  (* when a clause contains new inductive constants, assert minimality
     of the clause for all those constants independently *)
  let inf_assert_minimal c =
    let consts = scan_clause c in
    let proof =
      ProofStep.mk_inference [C.proof c] ~rule:(ProofStep.mk_rule "min")
    in
    let clauses =
      Cst_set.elements consts
      |> CCList.flat_map
        (fun cst ->
           decl_cst_ cst;
           let ctx = ClauseContext.extract_exn (C.lits c) (Ind_cst.cst_to_term cst) in
           (* no generalization, we have no idea whether [consts]
              originate from a universal quantification *)
           assert_min ~trail:(C.trail c) ~proof ~generalize_on:[] [ctx] cst)
    in
    clauses

  (* clauses when we do induction on [cst], generalizing the constants
     [generalize_on] *)
  let induction_on_
      ?(trail=Trail.empty) (clauses:C.t list) ~cst ~generalize_on : C.t list =
    decl_cst_ cst;
    Util.debugf ~section 1 "@[<2>perform induction on `%a`@ in `@[%a@]`@]"
      (fun k->k Ind_cst.pp_cst cst (Util.pp_list C.pp) clauses);
    (* extract a context from every clause, even those that do not contain [cst] *)
    let ctxs =
      List.map
        (fun c ->
           let sub = Ind_cst.cst_to_term cst in
           match ClauseContext.extract (C.lits c) sub with
             | Some ctx -> ctx
             | None -> ClauseContext.trivial (C.lits c) sub)
        clauses
    in
    (* proof: one step from all the clauses above *)
    let proof =
      ProofStep.mk_inference (List.map C.proof clauses)
        ~rule:(ProofStep.mk_rule "min")
    in
    assert_min ~trail ~proof ~generalize_on ctxs cst

  (* find inductive constants within the skolems *)
  let ind_consts_of_skolems (l:(ID.t*Type.t) list) : Ind_cst.cst list =
    l
    |> List.filter (CCFun.uncurry Ind_cst.is_potential_cst)
    |> List.map (CCFun.uncurry Ind_cst.cst_of_id)

  (* hook for converting some statements to clauses.
     It check if [Negated_goal l] contains inductive clauses, in which case
     it states their collective minimality.
     It also handles inductive Lemmas *)
  let convert_statement st =
    match Statement.view st with
    | Statement.NegatedGoal (skolems, _) ->
      (* find inductive constants *)
      begin match ind_consts_of_skolems skolems with
        | [] -> E.CR_skip
        | consts ->
          (* first, get "proper" clauses, with proofs *)
          let clauses = C.of_statement st in
          (* for each new inductive constant, assert minimality of
             this constant w.r.t the set of clauses that contain it *)
          consts
          |> CCList.flat_map
            (fun cst ->
               (* generalize on the other constants *)
               let generalize_on =
                 CCList.remove ~eq:Ind_cst.cst_equal ~x:cst consts
               in
               induction_on_ clauses ~cst ~generalize_on)
          |> E.cr_return (* do not add the clause itself *)
        end
    | _ -> E.cr_skip

  let new_lemmas_ : C.t list ref = ref []

  (* look whether, to prove the lemma, we need induction *)
  let on_lemma cut =
    (* find inductive constants within the skolems *)
    let consts = ind_consts_of_skolems cut.A.cut_skolems in
    begin match consts with
      | [] -> () (* regular lemma *)
      | consts ->
        (* add the condition that the lemma is false *)
        let trail = Trail.singleton (BoolLit.neg cut.A.cut_lit) in
        let l =
          CCList.flat_map
            (fun cst ->
               let generalize_on =
                 CCList.remove ~eq:Ind_cst.cst_equal ~x:cst consts
               in
               induction_on_ ~trail ~generalize_on cut.A.cut_neg ~cst)
            consts
        in
        Util.incr_stat stats_lemmas;
        new_lemmas_ := List.rev_append l !new_lemmas_;
    end

  let inf_new_lemmas ~full:_ () =
    let l = !new_lemmas_ in
    new_lemmas_ := [];
    l

  (** {2 Register} *)

  let register () =
    Util.debug ~section 2 "register induction";
    let d = Env.flex_get k_ind_depth in
    Util.debugf ~section 2 "maximum induction depth: %d" (fun k->k d);
    Ind_cst.max_depth_ := d;
    Env.add_unary_inf "induction.ind" inf_assert_minimal;
    Env.add_clause_conversion convert_statement;
    Env.add_is_trivial_trail trail_is_trivial;
    Signal.on_every A.on_lemma on_lemma;
    Env.add_generate "ind.lemmas" inf_new_lemmas;
    if Env.flex_get k_lemma_guess then (
      Util.debug ~section 2 "enable lemma guessing";
      let module G = Make_guess_lemma(E)(A) in
      Env.add_generate "ind.guess_lemma" G.inf_guess_lemma;
    );
    (* declare new constants to [Ctx] *)
    Signal.on_every Ind_cst.on_new_cst decl_cst_;
    ()
end

(** {2 Options and Registration} *)

let enabled_ = ref true
let lemma_guess = ref true
let depth_ = ref !Ind_cst.max_depth_
let lemma_depth = ref 2

(* if induction is enabled AND there are some inductive types,
   then perform some setup after typing, including setting the key
   [k_enable].
   It will update the parameters. *)
let post_typing_hook stmts state =
  let p = Flex_state.get_exn Params.key state in
  (* only enable if there are inductive types *)
  let should_enable =
    CCVector.exists
      (fun st -> match Statement.view st with
        | Statement.Data _ -> true
        | _ -> false)
      stmts
  in
  if !enabled_ && should_enable then (
    Util.debug ~section 1
      "Enable induction: requires ord=rpo6; select=NoSelection";
    let p = {
      p with Params.
      param_ord = "rpo6";
      param_select = "NoSelection";
    } in
    state
    |> Flex_state.add Params.key p
    |> Flex_state.add k_enable true
    |> Flex_state.add k_lemma_guess !lemma_guess
    |> Flex_state.add k_ind_depth !depth_
    |> Flex_state.add k_lemma_gen_depth !lemma_depth
    |> Flex_state.add Ctx.Key.lost_completeness true
  ) else Flex_state.add k_enable false state

(* if enabled: register the main functor, with inference rules, etc. *)
let env_action (module E : Env.S) =
  let is_enabled = E.flex_get k_enable in
  if is_enabled then (
    let (module A) = Avatar.get_env (module E) in
    (* XXX here we do not use E anymore, because we do not know
       that A.E = E. Therefore, it is simpler to use A.E. *)
    let module E = A.E in
    E.Ctx.lost_completeness ();
    E.Ctx.set_selection_fun Selection.no_select;
    let module M = Make(A.E)(A) in
    M.register ();
  )

let extension =
  Extensions.(
    {default with
     name="induction_simple";
     post_typing_actions=[post_typing_hook];
     env_actions=[env_action];
    })

let () =
  Params.add_opts
    [ "--induction", Options.switch_set true enabled_, " enable induction"
    ; "--no-induction", Options.switch_set false enabled_, " disable induction"
    ; "--lemma-guess", Options.switch_set true lemma_guess, " enable lemma guess"
    ; "--no-lemma-guess", Options.switch_set false lemma_guess, " disable lemma guess"
    ; "--induction-depth", Arg.Set_int depth_, " maximum depth of nested induction"
    ; "--lemma-guess-depth", Arg.Set_int lemma_depth, " maximum depth of lemma generation"
    ]
