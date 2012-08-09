/*
This file is part of the first order theorem prover Darwin
Copyright (C) 2006  The University of Iowa

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/


%{

  module Counter = struct
    type t = int ref
    let create_with i = ref i
    let set counter i = counter := i
    let inc counter = counter := !counter + 1
    let value counter = !counter
  end

  module T = Terms

  type term = T.foterm
  type variable = T.foterm
  type literal = T.literal
  type clause = T.clause

  (* includes from input *)
  let include_files: string list ref =
    ref []

  (* these are only valid for the current clause
     and have to be invalidated with init_clause for every new clause *)

  (* the variable id counter for the currently read term/clause *)
  let var_id_counter = 
    Counter.create_with 0
      
  (* mapping of the variable names (e.g. "X") of the currently read term/clause
     to variables. *)
  let (var_map: (string * T.sort * variable) list ref) =
    ref []

  (* the literals of the currently read clause *)
  let (literals: literal list ref) =
    ref []

  (* reset everything in order to parse a new term/clause *)
  let init_clause () =
    Counter.set var_id_counter 0;
    var_map := [];
    literals := []
	
  (* gets the variables associated with a string from the variable mapping
     creates a new mapping for a new variable with the given sort *)
  let get_var ?(sort=T.univ_sort) (var_name: string) =
    try 
      (* way faster than List.assoc *)
      match (
	List.find
	  (fun (var_name', var_sort, _) ->
             var_name = var_name' && var_sort == sort
	  )
	  !var_map
      ) with (_, _, t) -> t
    with
      | Not_found ->
	  let new_var = 
	    T.mk_var (Counter.value var_id_counter) sort
	  in
	    Counter.inc var_id_counter;
	    var_map := (var_name, sort, new_var) :: !var_map;
	    new_var

  (* need to detect if input is fof and contains a conjecture *)
  (* is the input in fof format? *)
  let fof =
    ref false

  (* does the fof input contain a conjecture? *)
  let theorem =
    ref false

%}
  
%token LEFT_PARENTHESIS
%token RIGHT_PARENTHESIS
%token LEFT_BRACKET
%token RIGHT_BRACKET
%token DOT
%token NEGATION
%token COLON
%token COMMA
%token EQUALITY
%token DISEQUALITY
%token EOI
%token FOF
%token CNF
%token THF
%token INCLUDE
%token <string> SINGLE_QUOTED
%token <string> DOLLAR_WORD
%token <string> DOLLAR_DOLLAR_WORD
%token <string> DISTINCT_OBJECT
%token <string> LOWER_WORD
%token <string> UPPER_WORD
%token <string> UNSIGNED_INTEGER
%token <string> SIGNED_INTEGER
%token <string> REAL
%token DOLLAR_TRUE
%token DOLLAR_FALSE
%token DOLLAR
%token AND
%token OR
%token FORALL
%token EXISTS
%token BIJECTION
%token LEFT_IMPLICATION
%token RIGHT_IMPLICATION
%token UNKNOWN

%start parse_file
%type <Terms.clause list * string list> parse_file

%start term
%type <Terms.foterm> term

%%

/* start rules */

parse_file:
  | file EOI 
      {
	let clauses = $1 in
        let includes = !include_files in
	let is_fof = !fof in
        let is_theorem = !theorem in

	(* reset for next parser run *)
        include_files := [];
	fof := false;
	theorem := false;
        
        if is_fof then
	  raise (Const.FOF is_theorem)

        else
          clauses, includes
      }

  | EOI
      { print_endline "empty problem specification";
        raise Const.PARSE_ERROR }


/* parse rules */



file:
  | tptp_input
      { match $1 with
        | Some clause -> [clause]
        | None        -> []
      }

  | tptp_input file
      { match $1 with
        | Some clause -> clause :: $2
        | None        -> $2
      }

tptp_input:
  | annotated_formula
      { Some $1 }

  | include_
      { None }



annotated_formula:
  | fof_annotated
      { $1 }

  | cnf_annotated
      { $1 }

  | thf_annotated
      { $1 }

thf_annotated:
  | THF LEFT_PARENTHESIS name COMMA formula_role COMMA
    fof_formula annotations RIGHT_PARENTHESIS DOT
    { failwith "Parser_tptp: tfh syntax not supported." }

fof_annotated:
  | FOF LEFT_PARENTHESIS name COMMA formula_role COMMA
    fof_formula annotations RIGHT_PARENTHESIS DOT
    { fof := true; failwith "fof formula not handled (no CNF-ication)" }

fof_formula:
  | binary_formula
    { "" }

  | unitary_formula
    { "" }


binary_formula:
  | nonassoc_binary
    { "" }

  | assoc_binary
    { "" }

nonassoc_binary:
  | unitary_formula binary_connective unitary_formula
    { "" }

binary_connective:
  | BIJECTION
    { "" }
  | LEFT_IMPLICATION
    { "" }
  | RIGHT_IMPLICATION
    { "" }
  | UNKNOWN
    { "" }
  | NEGATION OR
    { "" }
  | NEGATION AND
    { "" }

assoc_binary:
  | or_formula
    { "" }
  | and_formula
    { "" }

or_formula:
  | unitary_formula OR more_or_formula
    { "" }

more_or_formula:
  | unitary_formula
    { "" }
  | unitary_formula OR more_or_formula
    { "" }

and_formula:
  | unitary_formula AND more_and_formula
    { "" }

more_and_formula:
  | unitary_formula
    { "" }
  | unitary_formula AND more_and_formula
    { "" }

unitary_formula:
  | quantified_formula
    { "" }
  | unary_formula
    { "" }
  | LEFT_PARENTHESIS fof_formula RIGHT_PARENTHESIS
    { "" }
  | atomic_formula
    { "" }

quantified_formula:
  | quantifier LEFT_BRACKET variable_list RIGHT_BRACKET
    COLON unitary_formula
    { "" }

quantifier:
  | FORALL
    { "" }
  | EXISTS
    { "" }

variable_list:
  | variable
    { "" }
  | variable COMMA variable_list
    { "" }

unary_formula:
  | unary_connective unitary_formula
    { "" }

unary_connective:
  | NEGATION
    { "" }


cnf_annotated:
  | CNF LEFT_PARENTHESIS name COMMA formula_role COMMA
  cnf_formula annotations RIGHT_PARENTHESIS DOT
      // ignore everything except for the formula
      {
	let clause = 
	  FoUtils.mk_clause $7 (T.Axiom $3)
	in
	  init_clause ();
	  clause
      }

formula_role:
  | LOWER_WORD
    { let role =
        $1
      in
        if role = "conjecture" then
          theorem := true;
        $1
    }

annotations:
  | null
      { "" }

  | COMMA source optional_info
      { "" }



cnf_formula:
  | LEFT_PARENTHESIS disjunction RIGHT_PARENTHESIS
      { $2 }

  | disjunction
      { $1 }

disjunction:
  | literal
      { [$1] }

  | literal OR disjunction
      { $1 :: $3 }




literal:
  | atomic_formula
      { $1 }

  | NEGATION atomic_formula
      { FoUtils.negate_lit $2 }

atomic_formula:
  | plain_atom
      { $1 }

  | defined_atom
      { $1 }

  | system_atom
      { $1 }

plain_atom:
  | plain_term_top
      { let t = T.cast $1 T.bool_sort in (* cast term to bool *)
        FoUtils.mk_eq t T.true_term }

arguments:
  | term
      { [ $1 ] }

  | term COMMA arguments
      { $1 :: $3 }

defined_atom:
  | DOLLAR_TRUE
      { FoUtils.mk_eq T.true_term T.true_term }

  | DOLLAR_FALSE
      { FoUtils.mk_neq T.true_term T.true_term (* T!=T is false *) }

  | term EQUALITY term
      { FoUtils.mk_eq $1 $3 }
  | term DISEQUALITY term
      { FoUtils.mk_neq $1 $3 }

system_atom:
  | system_term_top
      { let t = T.cast $1 T.bool_sort in
        FoUtils.mk_eq t T.true_term }

term:
  | function_term
      { $1 }

  | variable
      { $1 }

function_term:
  | plain_term
      { $1 }

  | defined_term
      { $1 }

  | system_term
      { $1 }

plain_term_top:
  | constant
      { T.mk_leaf $1 T.univ_sort }

  | functor_ LEFT_PARENTHESIS arguments RIGHT_PARENTHESIS
      { let subterms = $1 :: $3 in
        T.mk_node subterms
      }

plain_term:
  | constant
      { T.mk_leaf $1 T.univ_sort }

  | functor_ LEFT_PARENTHESIS arguments RIGHT_PARENTHESIS
      { let subterms = $1 :: $3 in
        T.mk_node subterms
      }

constant:
  | atomic_word
      { let sym = Signature.str_to_sym $1 in sym }

functor_:
  | atomic_word
      { let sym = Signature.str_to_sym $1 in
        T.mk_leaf sym T.univ_sort }

defined_term:
  | number
      { print_endline ("Parser_tptp: <defined_term: number> not supported: "
                      ^ $1);
        raise Const.PARSE_ERROR }

  | DISTINCT_OBJECT
      { print_endline ("Parser_tptp: <defined_term: distinct_object> not supported: " ^ $1);
        raise Const.PARSE_ERROR }

system_term_top:
  | system_constant
      { T.mk_leaf $1 T.univ_sort }

  | system_functor LEFT_PARENTHESIS arguments RIGHT_PARENTHESIS
      { let subterms = (T.mk_leaf $1 T.univ_sort) :: $3 in
        T.mk_node subterms
      }

system_term:
  | system_constant
      { T.mk_leaf $1 T.univ_sort }

  | system_functor LEFT_PARENTHESIS arguments RIGHT_PARENTHESIS
      { let subterms = (T.mk_leaf $1 T.univ_sort) :: $3 in
        T.mk_node subterms
      }

system_functor:
  | atomic_system_word
      { $1 }
      
system_constant:
  | atomic_system_word
      { $1 }



variable:
  | UPPER_WORD
      { get_var $1 }


source:
  | general_term
      { "" }

optional_info:
  | COMMA useful_info
      { "" }

  | null
      { "" }

useful_info:
  | general_term_list
      { "" }
      

include_:
  | INCLUDE LEFT_PARENTHESIS file_name formula_selection RIGHT_PARENTHESIS DOT
      { include_files := $3 :: !include_files }

formula_selection:
  | COMMA '[' name_list ']'
      { $3 }

  | null
      { [] }

name_list:
  | name
      { [$1] }

  | name COMMA name_list
      { $1 :: $3 }



general_term:
  | general_data
      { "" }

  | general_data COLON general_term
      { "" }

  | general_list
      { "" }

general_data:
  | atomic_word
      { "" }

  | atomic_word LEFT_PARENTHESIS general_arguments RIGHT_PARENTHESIS
      { "" }

  | number
      { "" }

  | DISTINCT_OBJECT
      { "" }

general_arguments:
  | general_term
      { [$1] }

  | general_term COMMA general_arguments
      { $1 :: $3 }

general_list:
  | '[' ']'
      { [] }

  | '[' general_term_list ']'
      { $2 }

general_term_list:
  | general_term
      { [$1] }

  | general_term COMMA general_term_list
      { $1 :: $3 }


name:
  | atomic_word
      { $1 }

  | UNSIGNED_INTEGER
      { $1 }

atomic_word:
  | LOWER_WORD
      { $1 }

  | SINGLE_QUOTED
      { $1 }

atomic_system_word:
  | DOLLAR_DOLLAR_WORD
      { print_endline ("Parser_tptp: <$$word> not supported: " ^ $1);
        raise Const.PARSE_ERROR  }

number:
  | REAL
      { $1 }

  | SIGNED_INTEGER
      { $1 }

  | UNSIGNED_INTEGER
      { $1 }

file_name:
  | SINGLE_QUOTED
      { let quoted = $1 in
        String.sub quoted 1 (String.length quoted - 2)
      }

null:
      { }

%%




