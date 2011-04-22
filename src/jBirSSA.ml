(*
 * This file is part of SAWJA
 * Copyright (c)2009 David Pichardie (INRIA)
 * Copyright (c)2010 Vincent Monfort (INRIA)
 *
 * This program is free software: you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program.  If not, see
 * <http://www.gnu.org/licenses/>.
 *)

include SsaBir.T (SsaBir.Var(JBir)) (JBir.Internal.InstrRep (SsaBir.Var(JBir)))
include JBir.Internal.InstrRep (SsaBir.Var(JBir))  
include SsaBir.Var(JBir)



module JBir2SSA = struct
  let use_bcvars =
    let rec vars acc = function
      | JBir.Const _ -> acc
      | JBir.Var (_,x) -> if JBir.var_ssa x then acc else Ptset.add (JBir.index x) acc 
      | JBir.Field (e,_,_) 
      | JBir.Unop (_,e) -> vars acc e
      | JBir.Binop (_,e1,e2) -> vars (vars acc e1) e2
      | JBir.StaticField _ -> acc in
      function
	| JBir.AffectField (e1,_,_,e2) 
	| JBir.Ifd ((_,e1,e2), _) -> vars (vars Ptset.empty e1) e2
	| JBir.Goto _ 
	| JBir.MayInit _ 
	| JBir.Nop 
	| JBir.Return None -> Ptset.empty
	| JBir.Throw e 
	| JBir.Return (Some e)
	| JBir.AffectVar (_,e) 
	| JBir.MonitorEnter e 
	| JBir.MonitorExit e
	| JBir.AffectStaticField (_,_,e) -> vars Ptset.empty e
	| JBir.NewArray (_,_,le)
	| JBir.New (_,_,_,le) 
	| JBir.InvokeStatic (_,_,_,le) -> List.fold_left vars Ptset.empty le
	| JBir.InvokeVirtual (_,e,_,_,le) 
	| JBir.InvokeNonVirtual (_,e,_,_,le) -> List.fold_left vars Ptset.empty (e::le)
	| JBir.AffectArray (e1,e2,e3) -> vars (vars (vars Ptset.empty e1) e2) e3
	| JBir.Check c -> begin
	    match c with
	      | JBir.CheckArrayBound (e1,e2)
	      | JBir.CheckArrayStore (e1,e2) -> vars (vars Ptset.empty e1) e2
	      | JBir.CheckNullPointer e
	      | JBir.CheckNegativeArraySize e
	      | JBir.CheckCast (e,_)
	      | JBir.CheckArithmetic e -> vars Ptset.empty e
	      | JBir.CheckLink _ -> Ptset.empty
	  end

  let def_bcvar = function
    | JBir.AffectVar (v,_) 
    | JBir.NewArray (v,_,_)
    | JBir.New (v,_,_,_) 
    | JBir.InvokeStatic (Some v,_,_,_)
    | JBir.InvokeVirtual (Some v,_,_,_,_) 
    | JBir.InvokeNonVirtual (Some v,_,_,_,_) 
      -> if JBir.var_ssa v then Ptset.empty else Ptset.singleton (JBir.index v) 
    | _ -> Ptset.empty

  let var_defs m =
    JUtil.foldi
      (fun i ins -> 
	 match ins with
	   | JBir.AffectVar (x,_) 
	   | JBir.NewArray (x,_,_)
	   | JBir.New (x,_,_,_) 
	   | JBir.InvokeStatic (Some x,_,_,_)
	   | JBir.InvokeVirtual (Some x,_,_,_,_) 
	   | JBir.InvokeNonVirtual (Some x,_,_,_,_) 
	     -> if JBir.var_ssa x  then (fun m->m) else Ptmap.add ~merge:Ptset.union (JBir.index x) (Ptset.singleton i)
	   | _ -> fun m -> m)
      (List.fold_right
	 (fun (_,x) -> Ptmap.add (JBir.index x) (Ptset.singleton (-1)))
	 m.JBir.params Ptmap.empty)
      m.JBir.code 

  let map_instr def use =
    let map_expr f =
      let rec aux expr = 
	match expr with
	  | JBir.Const c -> Const c
	  | JBir.StaticField (c,fs) -> StaticField (c,fs)
	  | JBir.Field (e,c,fs) -> Field (aux e,c,fs)
	  | JBir.Var (t,x) -> Var (t,f x)
	  | JBir.Unop (s,e) -> Unop (s,aux e)
	  | JBir.Binop (s,e1,e2) -> Binop (s,aux e1,aux e2)
      in aux 
    in
    let use = map_expr use in
      function
	| JBir.AffectField (e1,c,f0,e2) -> AffectField (use e1,c,f0,use e2)
	| JBir.Ifd ((c,e1,e2), pc) -> Ifd ((c,use e1,use e2), pc) 
	| JBir.Goto i -> Goto i
	| JBir.Throw e -> Throw (use e) 
	| JBir.MayInit c -> MayInit c
	| JBir.Nop -> Nop
	| JBir.Return None -> Return None
	| JBir.Return (Some e) -> Return (Some (use e))
	| JBir.AffectVar (x,e) -> AffectVar (def x,use e)
	| JBir.MonitorEnter e -> MonitorEnter (use e)
	| JBir.MonitorExit e -> MonitorExit (use e)
	| JBir.AffectStaticField (c,f0,e) -> AffectStaticField (c,f0,use e)
	| JBir.NewArray (x,t,le) -> NewArray (def x,t,List.map (use) le)
	| JBir.New (x,c,lt,le) -> New (def x,c,lt,List.map (use) le)
	| JBir.InvokeStatic (None,c,ms,le) -> InvokeStatic (None,c,ms,List.map (use) le)
	| JBir.InvokeStatic (Some x,c,ms,le) -> InvokeStatic (Some (def x),c,ms,List.map (use) le)
	| JBir.InvokeVirtual (None,e,c,ms,le) -> InvokeVirtual (None,use e,c,ms,List.map (use) le)
	| JBir.InvokeVirtual (Some x,e,c,ms,le) -> InvokeVirtual (Some (def x),use e,c,ms,List.map (use) le)
	| JBir.InvokeNonVirtual (None,e,c,ms,le) -> InvokeNonVirtual (None,use e,c,ms,List.map (use) le)
	| JBir.InvokeNonVirtual (Some x,e,c,ms,le) -> InvokeNonVirtual (Some (def x),use e,c,ms,List.map (use) le)
	| JBir.AffectArray (e1,e2,e3) -> AffectArray (use e1,use e2,use e3)
	| JBir.Check c -> Check begin
	    match c with
	      | JBir.CheckArrayBound (e1,e2) -> CheckArrayBound (use e1,use e2)
	      | JBir.CheckArrayStore (e1,e2) -> CheckArrayStore (use e1,use e2)
	      | JBir.CheckNullPointer e -> CheckNullPointer (use e)
	      | JBir.CheckNegativeArraySize e -> CheckNegativeArraySize (use e)
	      | JBir.CheckCast (e,t) -> CheckCast (use e,t)
	      | JBir.CheckArithmetic e -> CheckArithmetic (use e)
	      | JBir.CheckLink op -> CheckLink op
	  end

  let map_exception_handler f e = {
    e_start = e.JBir.e_start;
    e_end = e.JBir.e_end;
    e_handler = e.JBir.e_handler;
    e_catch_type = e.JBir.e_catch_type;
    e_catch_var = f e.JBir.e_catch_var 0
  }

    
  let live_analysis ir_code = 
    let live = Live_bir.run ir_code in
      fun i x  ->  Live_bir.Env.mem x (live i)
	
  let preds m =
    let preds = Array.make (Array.length m.JBir.code) Ptset.empty in
    let add_pred i j = preds.(i) <- Ptset.add j preds.(i) in
      add_pred 0 (-1);
      Array.iteri 
	(fun i ins ->
	   match ins with
	     | JBir.Ifd (_ , j) -> add_pred (i+1) i; add_pred j i
	     | JBir.Goto j -> add_pred j i
	     | JBir.Throw _
	     | JBir.Return _ -> ()
	     | _ -> add_pred (i+1) i) m.JBir.code;
      List.iter
	(fun (i,e) -> add_pred e.JBir.e_handler i) (JBir.exception_edges m);
      let preds = Array.map Ptset.elements preds in
      let preds i = preds.(i) in
	preds

  let succs m =
    let succs = Array.make (Array.length m.JBir.code) Ptset.empty in
    let add i j = succs.(i) <- Ptset.add j succs.(i) in
      Array.iteri 
	(fun i ins ->
	   match ins with
	     | JBir.Ifd (_ , j) -> add i (i+1); add i j
	     | JBir.Goto j -> add i j
	     | JBir.Throw _
	     | JBir.Return _ -> ()
	     | _ -> add i (i+1)) m.JBir.code;
      List.iter
	(fun (i,e) -> add i e.JBir.e_handler) (JBir.exception_edges m);
      let succs = Array.map Ptset.elements succs in
      let succs i =
	if i=(-1) then [0] else succs.(i) in
	succs

end


module SsaJBir = SsaBir.SSA 
  (JBir) 
  (SsaBir.Var(JBir))
  (SsaBir.T (SsaBir.Var(JBir)) (JBir.Internal.InstrRep (SsaBir.Var(JBir))))
  (struct 
     include JBir2SSA
     type ir_t = JBir.t
     type ir_var = JBir.var
     type ir_instr = JBir.instr
     type ir_exc_h = JBir.exception_handler
     type ssa_var = var
     type ssa_instr = instr
     type ssa_exc_h = exception_handler
   end)
  (* Common parts*)

let transform_from_bir = SsaJBir.transform_from_ir

let transform ?(bcv=false) ?(ch_link=false) cm code = 
  SsaJBir.transform_from_ir (JBir.transform ~bcv:bcv ~ch_link:ch_link cm code)

module Internal = 
struct

  (** Common signature for instructions of JBir and JBirSSA representations*)
  module type InstrSig = JBir.Internal.InstrSig

  (** Common signature for code of JBirSSA and A3BirSSA representations*)
  module type CodeSig = 
  sig

    type var

    module VarSet : Javalib_pack.JBasics.GenericSetSig with type elt = var
    module VarMap : Javalib_pack.JBasics.GenericMapSig with type key = var

    type instr
      
    type exception_handler = {
      e_start : int;
      e_end : int;
      e_handler : int;
      e_catch_type : Javalib_pack.JBasics.class_name option;
      e_catch_var : var
    }

    type phi_node = {
      def : var;
      (** The variable defined in the phi node*)
      use : var array;
      (** Array of used variable in the phi node, the index of a used
	  variable in the array corresponds to the index of the program
	  point predecessor in [preds.(phi_node_pc)].*)
      use_set : VarSet.t;
      (** Set of used variable in the phi node (no information on
	  predecessor program point for a used variable)*)
    }

    type t = {
      vars : var array;  
      (** All variables that appear in the method. [vars.(i)] is the variable of
	  index [i]. *)
      params : (Javalib_pack.JBasics.value_type * var) list;
      (** [params] contains the method parameters (including the receiver this for
	  virtual methods). *)
      code : instr array;
      (** Array of instructions the immediate successor of [pc] is [pc+1].  Jumps
	  are absolute. *)
      preds : (int array) array;
      (** [preds.(pc)] is the array of program points that are predecessors of
	  instruction [pc]. *)
      phi_nodes : phi_node list array;
      (** Array of phi nodes assignments. Each phi nodes assignments at
	  point [pc] must be executed before the corresponding [code.(pc)]
	  instruction. *)
      exc_tbl : exception_handler list;
      (** [exc_tbl] is the exception table of the method code. Jumps are
	  absolute. *)
      line_number_table : (int * int) list option;
      (** [line_number_table] contains debug information. It is a list of pairs
	  [(i,j)] where [i] indicates the index into the bytecode array at which the
	  code for a new line [j] in the original source file begins.  *)
      pc_bc2ir : int Ptmap.t;
      (** map from bytecode code line to ir code line (very sparse). *)
      pc_ir2bc : int array; 
      (** map from ir code line to bytecode code line *)
    }  

    (** [print_handler exc] returns a string representation for
	exception handler [exc]. *)
    val print_handler : exception_handler -> string

    val jump_target : t -> bool array

    (** [print_phi_node phi] returns a string representation for phi node [phi]. *)
    val print_phi_node : ?phi_simpl:bool -> phi_node -> string

    (** [print_phi_nodes phi_list] returns a string representation for phi nodes 
	[phi_list]. *)
    val print_phi_nodes : ?phi_simpl:bool -> phi_node list -> string

    (** [print c] returns a list of string representations for instruction of [c]
	(one string for each program point of the code [c]). *)
    val print : ?phi_simpl:bool -> t -> string list
      
    (** [exception_edges m] returns a list of edges [(i,e);...] where
	[i] is an instruction index in [m] and [e] is a handler whose
	range contains [i]. *)
    val exception_edges :  t -> (int * exception_handler) list

    (** [get_source_line_number pc m] returns the source line number corresponding
	the program point [pp] of the method code [m].  The line number give a rough
	idea and may be wrong.  It uses the field [t.pc_ir2bc] of the code
	representation and the attribute LineNumberTable (cf. JVMS §4.7.8).*)
    val get_source_line_number : int -> t -> int option
  end 


  let vars = vars
  let params = params
  let code = code
  let exc_tbl = exc_tbl
  let line_number_table = line_number_table
  let pc_bc2ir = pc_bc2ir
  let pc_ir2bc = pc_ir2bc

  let print_simple = print_simple


end
