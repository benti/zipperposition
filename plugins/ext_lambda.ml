(*
Zipperposition: a functional superposition prover for prototyping
Copyright (C) 2012 Simon Cruanes

This is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.
*)

(** {1 Plugin for Beta-reduction} *)

open Basic

module T = Terms

let lambda_canonize t =
  T.eta_reduce (T.beta_reduce t)

let ext =
  let open Extensions in
  let actions =
    [ Ext_term_rewrite ("lambda", lambda_canonize);
      Ext_signal_incompleteness]
  in
  { name = "lambda";
    actions;
  }

let _ =
  Extensions.register ext

