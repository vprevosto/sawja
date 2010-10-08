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

open Javalib_pack

(** SSA form of the {!A3Bir} intermediate representation.*)


(** {2 Language} *)

(** {3 Expressions} *)

(** Abstract data type for variables *)
type var

(** [var_equal v1 v2] is equivalent to [v1 = v2], but is faster.  *)
val var_equal : var -> var -> bool

(** [var_orig v] is [true] if and only if the variable [v] was already used at
    bytecode level. *)
val var_orig : var -> bool

(** [var_name v] returns a string representation of the variable [v]. *)
val var_name : var -> string

(** [var_name_g v] returns a string representation of the variable [v]. 
    If the initial class was compiled using debug information, original 
    variable names are build on this information. It is equivalent to
    [var_name_g x = match var_name_debug with Some s -> s | _ -> var_name x] *)
val var_name_g : var -> string

(** [bc_num v] returns the local var number if the variable comes from the initial bytecode program. *)
val bc_num : var -> int option

(** [var_origin v] returns original [A3Bir] local var from which [v] is obtained *)
val var_origin : var -> A3Bir.var

(** [var_ssa_index v] returns the SSA index of [v] *)
val var_ssa_index : var -> int

(** [index v] returns the unique index of [v] *)
val index : var -> int


(** Side-effect free basic expressions *)
type basic_expr = 
  | Const of A3Bir.const (** constants *)
  | Var of JBasics.value_type * var (** variables are given a type information. *)

(** Side-effect free expressions. Only variables and static fields can be assigned such expressions. *)
type expr =
    BasicExpr of basic_expr (** basic expressions *)
  | Unop of A3Bir.unop * basic_expr
  | Binop of A3Bir.binop * basic_expr * basic_expr
  | Field of basic_expr * JBasics.class_name * JBasics.field_signature  (** Reading fields of arbitrary expressions *)
  | StaticField of JBasics.class_name * JBasics.field_signature  (** Reading static fields *)

(** [type_of_basic_expr e] returns the type of the expression [e]. *)      
val type_of_basic_expr : basic_expr -> JBasics.value_type

(** [type_of_expr e] returns the type of the expression [e]. 
 N.B.: a [(TBasic `Int) value_type] could also represent a boolean value for the expression [e].*)
val type_of_expr : expr -> JBasics.value_type

(** {3 Instructions} *)

(** [check] is the type of A3BirSSA assertions. They are generated by
    the transformation so that execution errors arise in the same
    order in the initial bytecode program and its A3BirSSA version. Next
    to each of them is the informal semantics they should be given. *)

type check =
  | CheckNullPointer of basic_expr
      (** [CheckNullPointer e] checks that the expression [e] is not a null
          pointer and raises the Java NullPointerException if this not the case. *)
  | CheckArrayBound of basic_expr * basic_expr
      (** [CheckArrayBound(a,idx)] checks the index [idx] is a valid index for
          the array denoted by the expression [a] and raises the Java
          IndexOutOfBoundsException if this is not the case. *)
  | CheckArrayStore of basic_expr * basic_expr
      (** [CheckArrayStore(a,e)] checks [e] can be stored as an element of the
          array [a] and raises the Java ArrayStoreException if this is not the
          case. *)
  | CheckNegativeArraySize of basic_expr
      (** [CheckNegativeArray e] checks that [e], denoting an array size, is positive
          or zero and raises the Java NegativeArraySizeException if this is not the
          case.*)
  | CheckCast of basic_expr * JBasics.object_type
      (** [CheckCast(e,t)] checks the object denoted by [e] can be casted to the
          object type [t] and raises the Java ClassCastException if this is not the
          case. *)
  | CheckArithmetic of basic_expr
      (** [CheckArithmetic e] checks that the divisor [e] is not zero,
          and raises ArithmeticExcpetion if this is not the case. *)
  | CheckLink of JCode.jopcode
      (** [CheckLink op] checks if linkage mechanism, depending on
	  [op] instruction, must be started and if so if it
	  succeeds. These instructions are only generated if the
	  option is activated during transformation (cf. {!transform}).

	  Linkage mechanism and errors that could be thrown
	  are described in chapter 6 of JVM Spec 1.5 for each bytecode
	  instruction (only a few instructions imply linkage
	  operations: checkcast, instanceof, anewarray,
	  multianewarray, new, get_, put_, invoke_). *)
      


(** A3BirSSA instructions are register-based and unstructured. Next to
    them is the informal semantics (using a traditional instruction
    notations) they should be given. 
    
    Exceptions that could be raised by the virtual
    machine are described beside each instruction, except for the
    virtual machine errors, subclasses of
    [java.lang.VirtualMachineError], that could be raised at any time
    (cf. JVM Spec 1.5 §6.3 ).*)

type instr =
    Nop
  | AffectVar of var * expr
      (** [AffectVar(x,e)] denotes x := e.  *)
  | AffectArray of basic_expr * basic_expr * basic_expr
      (** [AffectArray(a,idx,e)] denotes   a\[idx\] := e. *)
  | AffectField of basic_expr * JBasics.class_name * JBasics.field_signature * basic_expr
      (** [AffectField(e,c,fs,e')] denotes   e.<c:fs> := e'. *)
  | AffectStaticField of JBasics.class_name * JBasics.field_signature * expr
      (** [AffectStaticField(c,fs,e)] denotes   <c:fs> := e .*)
  | Goto of int
      (** [Goto pc] denotes goto pc. (absolute address) *)
  | Ifd of ([ `Eq | `Ge | `Gt | `Le | `Lt | `Ne ] * basic_expr * basic_expr) * int
      (** [Ifd((op,e1,e2),pc)] denotes    if (e1 op e2) goto pc. (absolute address) *)
  | Throw of basic_expr (** [Throw e] denotes throw e.  

			The exception [IllegalMonitorStateException] could be thrown by the virtual machine.  *)
  | Return of basic_expr option
      (** [Return opte] denotes 
          - return void when [opte] is [None] 
          - return opte otherwise 

	  The exception [IllegalMonitorStateException] could be thrown by the
	  virtual machine.*)
  | New of var * JBasics.class_name * JBasics.value_type list * basic_expr list
      (** [New(x,c,tl,args)] denotes x:= new c<tl>(args), [tl] gives the type of
          [args]. *)
  | NewArray of var * JBasics.value_type * basic_expr list
      (** [NewArray(x,t,el)] denotes x := new c\[e1\]...\[en\] where ei are the
          elements of [el] ; they represent the length of the corresponding
          dimension. Elements of the array are of type [t].  *)
  | InvokeStatic of var option * JBasics.class_name *  JBasics.method_signature * basic_expr list
      (** [InvokeStatic(x,c,ms,args)] denotes 
          - c.m<ms>(args) if [x] is [None] (void returning method)
          - x :=  c.m<ms>(args) otherwise  

	  The exception [UnsatisfiedLinkError] could be
	  thrown if the method is native and the code cannot be
	  found.*)
  | InvokeVirtual of var option * basic_expr * A3Bir.virtual_call_kind * JBasics.method_signature * basic_expr list
      (** [InvokeVirtual(x,e,k,ms,args)] denotes the [k] call
          - e.m<ms>(args) if [x] is [None]  (void returning method)
          - x := e.m<ms>(args) otherwise

												      If [k] is a [VirtualCall _] then the virtual machine could throw the following errors in the same order: [AbstractMethodError, UnsatisfiedLinkError].  

	  											      If [k] is a [InterfaceCall _] then the virtual machine could throw the following errors in the same order: [IncompatibleClassChangeError, AbstractMethodError, IllegalAccessError, AbstractMethodError, UnsatisfiedLinkError]. *)
  | InvokeNonVirtual of var option * basic_expr * JBasics.class_name * JBasics.method_signature * basic_expr list
      (** [InvokeNonVirtual(x,e,c,ms,args)] denotes the non virtual call
          - e.C.m<ms>(args) if [x] is [None]  (void returning method)
          - x := e.C.m<ms>(args) otherwise  

	  The exception [UnsatisfiedLinkError] could be thrown if the
	  method is native and the code cannot be found.*)
  | MonitorEnter of basic_expr (** [MonitorEnter e] locks the object [e]. *)
  | MonitorExit of basic_expr (** [MonitorExit e] unlocks the object [e]. 
				  
				  The exception
				  [IllegalMonitorStateException] could
				  be thrown by the virtual
				  machine.  *)
  | MayInit of JBasics.class_name
      (** [MayInit c] initializes the class [c] whenever it is required. 
	  
	  The exception [ExceptionInInitializerError] could be thrown
	  by the virtual machine.
	  
      *)
  | Check of check
      (** [Check c] evaluates the assertion [c].  
	  
	  Exceptions that could be thrown by the virtual
	  machine are described in {!check} type
	  declaration.*)


type exception_handler = {
  e_start : int;
  e_end : int;
  e_handler : int;
  e_catch_type : JBasics.class_name option;
  e_catch_var : var
}

(** [t] is the parameter type for A3BirSSA methods. *)
type t = {
  vars : var array;  
    (** All variables that appear in the method. [vars.(i)] is the variable of
	index [i]. *)
  params : (JBasics.value_type * var) list;
  (** [params] contains the method parameters (including the receiver this for
      virtual methods). *)
  code : instr array;
  (** Array of instructions the immediate successor of [pc] is [pc+1].  Jumps
      are absolute. *)
  phi_nodes : (var * var array) list array;
  (** Array of phi nodes assignments. Each phi nodes assignments at point [pc] must
      be executed before the corresponding [code.(pc)] instruction. *)
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

(** [jump_target m] indicates whether program points are join points or not in [m]. *)
val jump_target : t -> bool array

(** [exception_edges m] returns a list of edges [(i,e);...] where
    [i] is an instruction index in [m] and [e] is a handler whose
    range contains [i]. *)
val exception_edges :  t -> (int * exception_handler) list

(** {2 Printing functions} *)

(** [print_handler exc] returns a string representation for exception handler
    [exc]. *)
val print_handler : exception_handler -> string

(** [print_expr e] returns a string representation for expression [e]. *)
val print_expr : ?show_type:bool -> expr -> string

(** [print_instr ins] returns a string representation for instruction [ins]. *)
val print_instr : ?show_type:bool -> instr -> string

(** [print_phi_node phi] returns a string representation for phi node [phi]. *)
val print_phi_node : var * var array -> string

(** [print_phi_nodes phi_list] returns a string representation for phi nodes 
    [phi_list]. *)
val print_phi_nodes : (var * var array) list -> string

(** [print c] returns a list of string representations for instruction of [c]
    (one string for each program point of the code [c]). *)
val print : t -> string list

(** {2 Bytecode transformation} *)

(** [transform_from_a3bir ir_code] transforms the {!A3Bir} [ir_code] into 
    its SSA representation. *)
val transform_from_a3bir : A3Bir.t -> t

(** [transform ~bcv ~ch_link cm jcode] transforms the code [jcode]
    into its A3BirSSA representation. The transformation is performed in
    the context of a given concrete method [cm].  The type checking
    normally performed by the ByteCode Verifier (BCV) is done if and
    only if [bcv] is [true]. Check instructions are generated when a
    linkage operation is done if and only if [ch_link] is
    true. [transform] can raise several exceptions. See exceptions
    below for details. *)
val transform :
  ?bcv:bool -> ?ch_link:bool -> JCode.jcode Javalib.concrete_method -> JCode.jcode -> t

(** {2 Exceptions} *)

(** See {!A3Bir} Exceptions section*)

