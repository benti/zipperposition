
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Meta Prover for zipperposition} *)

open Libzipperposition

type 'a or_error = [`Ok of 'a | `Error of string]

let prof_scan_clause = Util.mk_profiler "meta.scan_clause"
let prof_scan_formula = Util.mk_profiler "meta.scan_formula"

module T = TypedSTerm
module M = Libzipperposition_meta
module Lit = Literal
module Lits = Literals

type term = T.t

(** {2 Implementation} *)

let section = Util.Section.make ~parent:Const.section "meta"

module LitMap = T.Map

module type S = MetaProverState_intf.S

(* TODO: handle ground convergent systems in Meta Prover, e.g. using
    a specific file... *)

let theory_files = ref []
let flag_print_rules = ref false
let flag_print_signature = ref false
let flag_print_rules_exit = ref false

module Make(E : Env.S) : S with module E = E = struct
  module E = E
  module C = E.C

  type lemma = C.t (** Lemma *)
  type axiom = ID.t * term list
  type theory = ID.t * term list
  type rewrite = (FOTerm.t * FOTerm.t) list (** Rewrite system *)
  type pre_rewrite = (term * term) list

  module Result = struct
    type t = {
      lemmas : lemma list;
      theories : theory list;
      axioms : axiom list;
      rewrite : rewrite list; (** list of rewrite systems *)
      pre_rewrite : pre_rewrite list;
    }

    let empty = {
      lemmas=[];
      theories=[];
      axioms=[];
      rewrite=[];
      pre_rewrite=[];
    }

    let is_empty r =
      let aux = function [] -> true | _ -> false in
      aux r.lemmas
      && aux r.theories
      && aux r.axioms
      && aux r.rewrite
      && aux r.pre_rewrite

    let lemmas t = t.lemmas
    let theories t = t.theories
    let axioms t = t.axioms
    let rewrite t = t.rewrite
    let pre_rewrite t = t.pre_rewrite

    let add_lemmas l t = {t with lemmas=l@t.lemmas}
    let add_theories l t = {t with theories=l@t.theories}
    let add_axioms l t = {t with axioms=l@t.axioms}
    let add_rewrite l t = {t with rewrite=l@t.rewrite}
    let add_pre_rewrite l t = {t with pre_rewrite=l@t.pre_rewrite}

    (** Merge [r] into [into] *)
    let merge_into r ~into =
      into
      |> add_lemmas r.lemmas
      |> add_theories r.theories
      |> add_axioms r.axioms
      |> add_rewrite r.rewrite
      |> add_pre_rewrite r.pre_rewrite

    let pp_theory_axiom out (name, args) =
      Format.fprintf out "%a %a" ID.pp name (Util.pp_list ~sep:" " T.pp) args

    let pp_rewrite_ ppt out l =
      Format.fprintf out "@[<hov2>rewrite system@ @[<hv>%a@]@]"
        (Util.pp_list
          (fun out (a,b) -> Format.fprintf out "@[%a@]@ --> @[%a@]" ppt a ppt b))
        l

    let pp_rewrite_system out l =
      pp_rewrite_ FOTerm.pp out l

    let pp_pre_rewrite_system out l =
      pp_rewrite_ T.pp out l

    let print out r =
      Format.fprintf out "@[<hv2>results{@ ";
      if r.axioms <> []
      then
        Format.fprintf out "@[<hv2>axioms:@,%a@]@,"
          (Util.pp_list pp_theory_axiom) r.axioms;
      if r.theories <> []
      then Format.fprintf out "@[<hv2>theories:@ %a@]@,"
          (Util.pp_list pp_theory_axiom) r.theories;
      if r.lemmas <> []
      then Format.fprintf out "@[<hv2>lemmas:@ %a@]@,"
          (Util.pp_list (fun out c -> E.C.pp out c)) r.lemmas;
      if r.rewrite <> []
      then Format.fprintf out "@[<hv2>rewrite systems:@ %a@]@,"
          (CCList.print pp_rewrite_system) r.rewrite;
      if r.pre_rewrite <> []
      then Format.fprintf out "@[<hv2>pre-rewrite systems:@ %a@]@,"
          (CCList.print pp_pre_rewrite_system) r.pre_rewrite;
      Format.fprintf out "@]}";
      ()
  end

  (** {2 Induction} *)

  (* TODO move to induction *)
  module Induction = struct
    type ty = {
      ty : T.Ty.t;
      cstors : (ID.t * T.Ty.t) list;
    }

    let make ty cstors = {ty; cstors; }

    let print out ity =
      let pp_cstor out (s, ty) =
        Format.fprintf out "@[%a:@,%a@]" ID.pp s T.pp ty
      in
      Format.fprintf out "@[<hov2>ity{ty:@,%a,@ cstors:@,%a}@]"
        T.pp ity.ty (CCFormat.list pp_cstor) ity.cstors

    let const_cstor = T.Ty.const (ID.make"inductive_constructor")

    (* assert [τ] is inductive using
       [inductive {ty=@τ, cstors=[cstor @ty1 c1, cstor @ty2 c2]}] *)
    let sym_inductive = ID.make "inductive"
    let ty_sym_inductive =
      let a = Var.of_string ~ty:T.Ty.tType "a" in
      T.Ty.(forall a (
        [record ~rest:None [
            "ty", T.Ty.var a;
            "cstors", multiset const_cstor
          ]] ==> M.Reasoner.property_ty
      ))

    (* build a constructor with a term [cstor(sym)] *)
    let sym_cstor = ID.make "cstor"
    let ty_sym_cstor =
      let a = Var.of_string ~ty:T.Ty.tType "a" in
      T.Ty.(forall a ([T.Ty.var a] ==> const_cstor))

    let signature =
      ID.Map.of_list
        [ sym_inductive, ty_sym_inductive
        ; sym_cstor, ty_sym_cstor
        ]

    let pred_inductive = T.const ~ty:ty_sym_inductive sym_inductive
    let pred_cstor = T.const ~ty:ty_sym_cstor sym_cstor

    let t : ty M.Plugin.t = object
      method signature = signature
      method owns t = match T.view t with
        | T.App (hd, _) -> T.equal hd pred_inductive
        | _ -> false
      method clauses = []
      method to_fact ity =
        (* encode constructors *)
        let arg =
          (* FIXME *)
          let ty = assert false in
          T.record ~rest:None ~ty
            [ "ty", ity.ty
            ; "cstors", T.multiset ~ty:(T.Ty.multiset const_cstor)
                (List.map
                   (fun (s, ty_s) ->
                      (* term "cstor(ty_s, s)", roughly *)
                      T.app_infer pred_cstor [ty_s; T.const ~ty:ty_s s])
                   ity.cstors
                )
            ]
        in
        T.app_infer pred_inductive [ity.ty; arg]
      method of_fact _ =
        None (* TODO: real implementation *)
    end
  end

  (** {2 Arithmetic} *)

  (* TODO: encode sum as a multiset *)
  (* TODO: move to ArithInt... *)

  module Arith = struct
    let t : unit M.Plugin.t = object
      method signature = ID.Map.empty
      method owns _ = false
      method clauses = []
      method to_fact () = T.Form.true_
      method of_fact _ = None
    end
  end

  (** {2 Interface to the Meta-prover} *)

  let on_theory : theory Signal.t = Signal.create()
  let on_lemma : lemma Signal.t = Signal.create()
  let on_axiom : axiom Signal.t = Signal.create()
  let on_rewrite : rewrite Signal.t = Signal.create()
  let on_pre_rewrite : pre_rewrite Signal.t = Signal.create()

  type t = {
    mutable prover : M.Prover.t; (* real meta-prover *)
    mutable sources : C.t ProofStep.of_ LitMap.t; (** for reconstructing proofs *)
    mutable results : Result.t;
    mutable new_results : Result.t; (* recent results *)
  }

  let mk_prover_ =
    let p = M.Prover.empty in
    (* FIXME
    let p = M.Prover.add_signature p Induction.t#signature in
    let p = M.Prover.add_signature p Arith.t#signature in
    *)
    p

  (* global meta-prover *)
  let p = {
    prover = mk_prover_;
    sources = LitMap.empty;
    results = Result.empty;
    new_results = Result.empty;
  }

  let results () = p.results

  let pop_new_results ()  =
    let r = p.new_results in
    p.new_results <- Result.empty;
    r

  let reasoner = M.Prover.reasoner p.prover

  let theories k = Result.theories p.results |> List.iter k

  let prover = p.prover

  let proof_of_explanation p exp =
    M.Reasoner.Proof.facts exp
    |> Sequence.filter_map
      (fun fact -> try Some (LitMap.find fact p.sources) with Not_found -> None)
    |> Sequence.to_rev_list

  (* conversion back from meta-prover clauses *)
  let clause_of_foclause_ l =
    List.map
      (function
        | M.Encoding.Eq (a, b, true) -> SLiteral.eq a b
        | M.Encoding.Eq (a, b, false) -> SLiteral.neq a b
        | M.Encoding.Prop (a, sign) -> SLiteral.atom a sign
        | M.Encoding.Bool true -> SLiteral.true_
        | M.Encoding.Bool false -> SLiteral.false_)
      l

  (* print content of the reasoner *)
  let print_rules out r =
    Sequence.pp_seq M.Reasoner.Clause.pp out (M.Reasoner.Seq.to_seq r)

  (* adds [consequences] to [p] *)
  let add_consequences consequences =
    let facts = Sequence.map fst consequences in
    (* filter theories, axioms, lemmas... *)
    let theories =
      Sequence.filter_map M.Plugin.theory#of_fact facts
      |> Sequence.to_list
    and lemmas =
      Sequence.filter_map
        (fun (fact, explanation) ->
           CCOpt.(
             M.Plugin.lemma#of_fact fact
             >|= clause_of_foclause_
             >|= List.map E.Ctx.Lit.of_form
             >|= fun lits ->
             let proofs = proof_of_explanation p explanation in
             let proof =
               ProofStep.mk_inference ~rule:(ProofStep.mk_rule "lemma") proofs in
             let c = C.create lits ~trail:C.Trail.empty proof in
             c))
        consequences
      |> Sequence.to_list
    and axioms =
      Sequence.filter_map M.Plugin.axiom#of_fact facts
      |> Sequence.to_list
    and rewrite =
      Sequence.filter_map M.Plugin.rewrite#of_fact facts
      |> Sequence.to_list
    and pre_rewrite =
      Sequence.filter_map M.Plugin.pre_rewrite#of_fact facts
      |> Sequence.to_list
    in
    let r = { Result.theories; lemmas; axioms; rewrite; pre_rewrite ; } in
    p.new_results <- Result.merge_into r ~into:p.new_results;
    p.results <- Result.merge_into r ~into:p.results;
    (* trigger signals *)
    List.iter (Signal.send on_theory) r.Result.theories;
    List.iter (Signal.send on_axiom) r.Result.axioms;
    List.iter (Signal.send on_lemma) r.Result.lemmas;
    List.iter (Signal.send on_rewrite) r.Result.rewrite;
    List.iter (Signal.send on_pre_rewrite) r.Result.pre_rewrite;
    (* return new results *)
    r

  (* parse a theory file and update prover with it *)
  let parse_theory_file filename =
    Util.debugf ~section 1 "@[<2>parse theory file@ `%s`@]" (fun k->k filename);
    CCError.(
      M.Prover.parse_file p.prover filename >|=
      fun (prover', consequences) ->
      (* update prover; return new results *)
      p.prover <- prover';
      let r = add_consequences consequences in
      r
    )

  (* parse the given theory files into the prover *)
  let parse_theory_files files =
    let open CCError in
    fold_l
      (fun r f ->
        parse_theory_file f
         >|= fun r' ->
           Result.merge_into r' ~into:r)
      Result.empty files

  let add_fact_ fact =
    let prover', consequences = M.Prover.add_fact p.prover fact in
    p.prover <- prover';
    add_consequences consequences

  (* scan the clause [c] with proof [proof] *)
  let scan_ c proof =
    let fact =
      M.Encoding.foclause_of_clause c
      |> M.Plugin.holds#to_fact
    in
    (* save proof for later *)
    p.sources <- LitMap.add fact proof p.sources;
    add_fact_ fact

  let scan_clause c =
    Util.enter_prof prof_scan_clause;
    let proof = C.proof c in
    let c' =
      C.lits c
      |> Lits.Conv.to_forms ~hooks:(C.Ctx.Lit.to_hooks ())
    in
    let r = scan_ c' proof in
    Util.exit_prof prof_scan_clause;
    r

  (* be sure to scan clauses *)
  let infer_scan c =
    let r = scan_clause c in
    if not (Result.is_empty r) then (
      Util.debugf ~section 3 "@[scan@ %a@ →@ %a@]" (fun k->k C.pp c Result.print r);
    );
    []

  (** {6 Extension} *)

  (* global setup *)
  let setup () =
    Signal.on_every on_theory
      (fun th ->
        Util.debugf ~section 1 "@[detected theory@ @[%a@]@]"
          (fun k->k Result.pp_theory_axiom th));
    (* parse theory into [p] *)
    begin match parse_theory_files !theory_files with
      | `Error msg ->
          Format.printf "error: %s@." msg;
          raise Exit
      | `Ok _ ->
          if !flag_print_rules
          then
            Util.debugf ~section 1 "@[<v2>rules:@ %a@]" (fun k->k print_rules reasoner)
    end;
    (* register inferences *)
    E.add_unary_inf "meta.scan" infer_scan;
    (* printing *)
    Signal.once E.on_start
      (fun () ->
         if !flag_print_signature then
           Util.debugf ~section 1 "@[<hv2>signature:@,%a@]"
             (fun k->k (ID.Map.print ID.pp T.pp) (M.Prover.signature prover))
      );
    Signal.once Signals.on_exit
      (fun _ ->
         if !flag_print_rules_exit
         then
           Util.debugf ~section 1 "@[<hv2>detected:@,%a@]"
            (fun k->k Result.print (results ()));
      );
    ()
end

(** {2 Interface to {!Env} *)

let key = Flex_state.create_key ()

let get_env (module E : Env.S) = E.flex_get key

(** {2 Extension} *)

let extension =
  let action (module E: Env.S) =
    let module M = Make(E) in
    (* register in Env *)
    E.update_flex_state (Flex_state.add key (module M : S));
    M.setup()
  in
  { Extensions.default with Extensions.
    prio = 10;
    name = "meta";
    env_actions=[action];
  }

(** {2 CLI Options} *)

let add_theory f =
  (* register on first file *)
  if !theory_files = [] then (
    Extensions.register extension;
  );
  theory_files := f :: !theory_files

(* add options *)
let () = Params.add_opts
    [ "--theory", Arg.String add_theory, " use given theory file for meta-prover"
    ; "--meta-rules", Arg.Set flag_print_rules, " print all rules of meta-prover"
    ; "--meta-summary", Arg.Set flag_print_rules_exit, " print all rules before exit"
    ; "--meta-sig", Arg.Set flag_print_signature, " print meta signature"
    ]
