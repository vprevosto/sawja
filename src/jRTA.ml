(*
 * This file is part of JavaLib
 * Copyright (c)2009 Laurent Hubert (CNRS)
 * Copyright (c)2009 Nicolas Barre (INRIA)
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

open JBasics
open JOpcodes
open Javalib
open JProgram

module Dllist =
struct
  exception NilNode
  exception HeadNode
  exception TailNode
  exception NoHeadNode
  exception NoTailNode
  exception NoHeadNode
  exception CellNotFound

  type 'a link = 'a cellule
  and 'a content = Content of 'a | Head | Tail
  and 'a cellule = { mutable prev : 'a link;
		     content : 'a content;
		     mutable next : 'a link }
  and 'a dllist = 'a cellule

  let create () =
    let rec head = { prev = tail; content = Head; next = tail }
    and tail = { prev = head; content = Tail; next = head }
    in head
  let get (l:'a dllist) =
    match l.content with
      | Content c -> c
      | Head -> raise HeadNode
      | Tail -> raise TailNode
  let next (l:'a dllist) : 'a dllist = l.next
  let prev (l:'a dllist) : 'a dllist = l.prev
  let tail (l:'a dllist) : 'a dllist =
    match l.content with
      | Head -> l.prev
      | _ -> raise NoHeadNode

  let add (e:'a) (l:'a dllist) =
    match l.content with
      | Head ->
	  let new_elm = { prev = l;
			  content = Content e;
			  next = l.next } in
	  let cell = new_elm.next in
	    cell.prev <- new_elm;
	    l.next <- new_elm
      | _ -> raise NoHeadNode

  let del (l:'a dllist) =
    match l.content with
      | Head -> raise HeadNode
      | Tail -> raise TailNode
      | _ ->
	  l.next.prev <- l.prev;
	  l.prev.next <- l.next

  let rec mem (e:'a) (l:'a dllist) =
    match l.content with
      | Head ->
	  let cell = l.next in
	    mem e cell
      | Tail -> false
      | Content c ->
	  if (c = e) then
	    true
	  else let cell = l.next in
	    mem e cell

  let add_ifn e l =
    if not( mem e l ) then add e l

  let rec size ?(s=0) (l:'a dllist) =
    match l.content with
      | Head ->
	  let cell = l.next in
	    size ~s:0 cell
      | Tail -> s
      | Content _ ->
	  let cell = l.next in
	    size ~s:(s+1) cell

  let rec iter (f:'a -> unit) (l:'a dllist) =
    match l.content with
      | Head ->
	  let cell = l.next in
	    iter f cell
      | Tail -> ()
      | Content c ->
	  f c;
	  let cell = l.next in
	    iter f cell

  let rec iter_until_cell (f:'a -> unit) (bound:'a dllist) (l:'a dllist) =
    match l.content with
      | Head ->
	  let cell = l.next in
	    iter_until_cell f bound cell
      | Tail -> raise CellNotFound
      | Content c ->
	  if not( bound == l) then
	    (f c;
	     let cell = l.next in
	       iter_until_cell f bound cell)

  let rec iter_to_head_i (f:'a dllist -> 'a -> unit) (l:'a dllist) =
    match l.content with
      | Head -> ()
      | Tail ->
	  let cell = l.prev in
	    iter_to_head_i f cell
      | Content c ->
	  f l c;
	  let cell = l.prev in
	    iter_to_head_i f cell

  let iter_to_head (f:'a -> unit) (l:'a dllist) =
    iter_to_head_i (fun _ x -> f x) l

  let map (f:'a -> 'b) (l:'a dllist) =
    let tail = tail l
    and lm = ref [] in
      iter_to_head (fun x -> lm := (f x) :: !lm) tail;
      !lm
end

module Program =
struct
  type rta_method = { mutable has_been_parsed : bool;
		      c_method : JOpcodes.jvm_opcodes jmethod }
  type class_info =
      { class_data : JOpcodes.jvm_opcodes node;
	mutable is_instantiated : bool;
	mutable instantiated_subclasses : JOpcodes.jvm_opcodes class_node ClassMap.t;
	super_classes : class_name list;
	super_interfaces : ClassSet.t;
	methods : rta_method MethodMap.t;
	mutable children_classes : JOpcodes.jvm_opcodes class_node list;
	mutable children_interfaces : JOpcodes.jvm_opcodes interface_node list;
	mutable memorized_virtual_calls : MethodSet.t;
	mutable memorized_interface_calls : MethodSet.t }
	
  type class_method = JOpcodes.jvm_opcodes class_node * JOpcodes.jvm_opcodes concrete_method

  type program_cache =
      { mutable classes : class_info ClassMap.t;
	(* for each interface, interfaces maps a list of classes
	   that implements this interface or one of its subinterfaces *)
	mutable interfaces : ClassSet.t ClassMap.t;
	mutable static_virtual_lookup : class_method ClassMethodMap.t ClassMethMap.t;
	mutable static_static_lookup : class_method ClassMethodMap.t ClassMethMap.t;
	mutable static_special_lookup : (class_method ClassMethodMap.t
					   ClassMethMap.t) ClassMap.t;
	(* the clinits fields contains a set of class indexes whose clinit
	   methods have already been added to the workset *)
	mutable clinits : ClassSet.t;
	workset : (class_name * JOpcodes.jvm_opcodes concrete_method) Dllist.dllist;
	classpath : Javalib.class_path;
	mutable native_methods : ClassMethSet.t;
	parse_natives : bool;
	native_methods_info : JNativeStubs.t }

  exception Method_not_found

  let methods2rta_methods ioc =
    let mmap =
      match ioc with
	| JClass c -> c.c_methods
	| JInterface i ->
	    let mmap =
	      MethodMap.map (fun am -> AbstractMethod am) i.i_methods in
	      (match i.i_initializer with
		 | None -> mmap
		 | Some cm ->
		     MethodMap.add clinit_signature (ConcreteMethod cm) mmap)
    in
      MethodMap.map (fun m -> { has_been_parsed = false; c_method = m }) mmap

  let rec to_class_node ioc =
    match ioc with
      | Class c -> c
      | Interface _ -> failwith "to_class_node applied on interface !"
  and to_interface_node ioc =
    match ioc with
      | Class _ -> failwith "to_interface_node applied on class !"
      | Interface i -> i

  and ioc2node p ioc =
    match ioc with
      | JClass c ->
	  Class
	    { c_info = c;
	      c_super =
		(match c.c_super_class with
		   | None -> None
		   | Some cs ->
		       Some(to_class_node
			      (get_class_info p cs).class_data));
	      c_interfaces =
		(let c_interfaces = ref ClassMap.empty in
		   List.iter
		     (fun cs ->
			c_interfaces := ClassMap.add cs
			  (to_interface_node
			     (get_class_info p cs).class_data)
			  !c_interfaces)
		     c.Javalib.c_interfaces;
		   !c_interfaces);
	      get_c_children =
		(fun () -> (get_class_info p c.c_name).children_classes) }

      | JInterface i ->
	  Interface
	    { i_info = i;
	      i_super =
		(let object_node =
		   (get_class_info p java_lang_object).class_data in
		   match object_node with
		     | Class c -> c
		     | Interface _ ->
			 failwith "java.lang.object is an interface !");
	      i_interfaces =
		(let i_interfaces = ref ClassMap.empty in
		   List.iter
		     (fun cs ->
			i_interfaces := ClassMap.add cs
			  (to_interface_node
			     (get_class_info p cs).class_data)
			  !i_interfaces)
		     i.Javalib.i_interfaces;
		   !i_interfaces);
	      get_i_children_interfaces =
		(fun () -> (get_class_info p i.i_name).children_interfaces);
	      get_i_children_classes =
		(fun () -> (get_class_info p i.i_name).children_classes) }

  and get_class_info p cs =
    try
      ClassMap.find cs p.classes
    with
      | Not_found ->
	    add_class p cs;
	    try
	      ClassMap.find cs p.classes
	    with _ ->
	      failwith ("Can't load class or interface "
			^ (cn_name cs))
		
  and add_class p cs =
    (* We assume that a call to add_class is done only when a class has never *)
    (* been loaded in the program. Loading a class implies loading all its *)
    (* superclasses recursively. *)
    let ioc = Javalib.get_class p.classpath cs in
    let rta_methods = methods2rta_methods ioc in
      match ioc with
	| JClass c ->
	    let super_classes =
	      (match c.c_super_class with
		 | None -> []
		 | Some sc ->
		     let sc_info = get_class_info p sc in
		       sc :: sc_info.super_classes)
	    and implemented_interfaces =
	      let s = ref ClassSet.empty in
		List.iter (fun iname ->
			     s := ClassSet.add iname !s) c.Javalib.c_interfaces;
		!s in

	    (* For each implemented interface and its super interfaces we add
	       cni in the program interfaces map *)
	    let super_implemented_interfaces =
	      (ClassSet.fold
		 (fun i_sig s ->
		    let i_info = get_class_info p i_sig in
		      ClassSet.add i_sig
			(ClassSet.union s i_info.super_interfaces)
		 ) implemented_interfaces ClassSet.empty) in
	      ClassSet.iter
		(fun i ->
		   if ( ClassMap.mem i p.interfaces ) then
		     p.interfaces <- ClassMap.add i
		       (ClassSet.add cs (ClassMap.find i p.interfaces))
		       p.interfaces
		   else
		     p.interfaces <- ClassMap.add i
		       (ClassSet.add cs ClassSet.empty) p.interfaces
		) super_implemented_interfaces;
	      
	      let ioc_info =
		{ class_data = ioc2node p ioc;
		  is_instantiated = false;
		  instantiated_subclasses = ClassMap.empty;
		  super_classes = super_classes;
		  (* for a class super_interfaces contains
		     the transitively implemented interfaces *)
		  super_interfaces = super_implemented_interfaces;
		  methods = rta_methods;
		  children_classes = [];
		  children_interfaces = [];
		  memorized_virtual_calls = MethodSet.empty;
		  memorized_interface_calls = MethodSet.empty }
	      in
	      let c = to_class_node ioc_info.class_data in
		ClassSet.iter
		  (fun i_name ->
		     let i_info = get_class_info p i_name in
		       i_info.children_classes <- c :: i_info.children_classes
		  )
		  implemented_interfaces;
		List.iter
		  (fun sc_name ->
		     let sc_info = (get_class_info p sc_name) in
		       sc_info.children_classes <- c :: sc_info.children_classes
		  )
		  super_classes;
		p.classes <- ClassMap.add cs ioc_info p.classes;
	| JInterface i ->
	    let super_interfaces =
	      let s = ref ClassSet.empty in
		List.iter (fun si ->
			     let si_info = get_class_info p si in
			       s := ClassSet.add si !s;
			       s := ClassSet.union si_info.super_interfaces !s
			  ) i.Javalib.i_interfaces;
		!s in

	    let ioc_info =
	      { class_data = ioc2node p ioc;
		is_instantiated = false;
		(* An interface will never be instantiated *)
		instantiated_subclasses = ClassMap.empty;
		super_classes = [];
		super_interfaces = super_interfaces;
		methods = rta_methods;
		children_classes = [];
		children_interfaces = [];
		memorized_virtual_calls = MethodSet.empty;
		memorized_interface_calls = MethodSet.empty }
	    in
	    let i = to_interface_node ioc_info.class_data in
	      ClassSet.iter
		(fun si_name ->
		   let si_info = get_class_info p si_name in
		     si_info.children_interfaces <- i :: si_info.children_interfaces
		)
		super_interfaces;
	      p.classes <- ClassMap.add cs ioc_info p.classes;

  and add_clinit p cs =
    let ioc_info = get_class_info p cs in
      if ( not(ClassSet.mem cs p.clinits)
	   && defines_method ioc_info.class_data clinit_signature) then
	(
	  add_to_workset p (cs,clinit_signature);
	  p.clinits <- ClassSet.add cs p.clinits
	)

  and add_class_clinits p cs =
    let ioc_info = get_class_info p cs in
      List.iter
	(fun cs -> add_clinit p cs)
	(cs :: ioc_info.super_classes)
	
  and get_method p cs ms =
    let cl_info = get_class_info p cs in
      try
	MethodMap.find ms cl_info.methods
      with
	| Not_found -> raise Method_not_found
            
  and add_to_workset p (cs,ms) =
    let m = get_method p cs ms in
      match m with
	| { c_method = AbstractMethod _ } ->
	    failwith "Can't add an Abstract Method to the workset"
	| { c_method = ConcreteMethod cm } ->
	    (match cm.cm_implementation with
	       | Native ->
		   if not(m.has_been_parsed) then
		     (m.has_been_parsed <- true;
		      p.native_methods <-
			ClassMethSet.add (cs,ms) p.native_methods;
		      if (p.parse_natives) then Dllist.add (cs,cm) p.workset
		     )
	       | Java _ ->
		   if not(m.has_been_parsed) then
		     (m.has_been_parsed <- true;
		      Dllist.add (cs,cm) p.workset)
	    )

  let resolve_field p cs fs =
    let ioc = (get_class_info p cs).class_data in
    let rioc_list = JControlFlow.resolve_field fs ioc in
      List.map
	(fun rioc ->
	   match rioc with
	     | Class rc -> rc.c_info.c_name
	     | Interface ri -> ri.i_info.i_name) rioc_list

  let update_virtual_lookup_set p (c,ms) instantiated_subclasses =
    let cs = c.c_info.c_name in
    let virtual_lookup_map =
      JControlFlow.invoke_virtual_lookup ~c:(Some c) ms
	instantiated_subclasses in
      ClassMethodMap.iter
	(fun _ (rc,cm) ->
	   let rcs = rc.c_info.c_name in
	     add_to_workset p (rcs,ms);
	     let s = ClassMethMap.find (cs,ms) p.static_virtual_lookup in
	       p.static_virtual_lookup <-
		 ClassMethMap.add (cs,ms)
		 (ClassMethodMap.add cm.cm_class_method_signature (rc,cm) s)
		 p.static_virtual_lookup
	) virtual_lookup_map
	  
  let invoke_virtual_lookup p cs ms =
    (* If this virtual call site appears for the first time, *)
    (* we will update the static_lookup_virtual map, otherwise *)
    (* no work has to be done. *)
    let c_info = get_class_info p cs in
      if not( MethodSet.mem ms c_info.memorized_virtual_calls ) then
	(c_info.memorized_virtual_calls <-
	   MethodSet.add ms c_info.memorized_virtual_calls;
	 p.static_virtual_lookup <-
	   ClassMethMap.add (cs,ms)
	   ClassMethodMap.empty p.static_virtual_lookup;
	 let instantiated_classes =
	   if ( c_info.is_instantiated ) then
	     ClassMap.add cs (to_class_node (c_info.class_data))
	       c_info.instantiated_subclasses
	   else c_info.instantiated_subclasses in
	 let c = to_class_node c_info.class_data in
	   update_virtual_lookup_set p (c,ms) instantiated_classes
	)

  let interface_lookup_action interfaces cs f =
    if ( ClassMap.mem cs interfaces ) then
      (ClassSet.iter
	 f (ClassMap.find cs interfaces))
    else ()
      (* otherwise, the classes implementing the interface have not
	 been charged yet so we can't do anything *)

  let invoke_interface_lookup p cs ms =
    let i_info = get_class_info p cs in
      i_info.memorized_interface_calls <-
  	MethodSet.add ms i_info.memorized_interface_calls;
      interface_lookup_action p.interfaces cs
  	(fun x -> invoke_virtual_lookup p x ms)
	
  let update_interface_lookup_set p interfaces =
    ClassSet.iter
      (fun i ->
	 let i_info = get_class_info p i in
	   MethodSet.iter
	     (fun ms ->
		invoke_interface_lookup p i ms
	     )
	     i_info.memorized_interface_calls
      )
      interfaces
      (* transitivly implemented interfaces *)
      
  let add_instantiated_class p cs =
    let cl_info = get_class_info p cs in
      if not( cl_info.is_instantiated ) then
	(cl_info.is_instantiated <- true;
	 (* Now we need to update the static_lookup_virtual map *)
	 (* for each virtual call that already occurred on A and *)
	 (* its super classes. *)
	 (let calls = cl_info.memorized_virtual_calls in
	  let cl = to_class_node cl_info.class_data in
	  let subclass_map = ClassMap.add cs cl ClassMap.empty in
	    MethodSet.iter
	      (fun ms ->
		 update_virtual_lookup_set p (cl,ms) subclass_map
	      ) calls;
	    update_interface_lookup_set p cl_info.super_interfaces;
	    List.iter
	      (fun scs ->
	   	 let s_info = get_class_info p scs in
		 let sc = to_class_node s_info.class_data in
		   (* We complete the list of instantiated subclasses for cn
		      and its superclasses *)
		   s_info.instantiated_subclasses <-
		     ClassMap.add cs cl s_info.instantiated_subclasses;
	   	   (let calls = s_info.memorized_virtual_calls in
	   	      MethodSet.iter
	   		(fun ms ->
			   update_virtual_lookup_set p (sc,ms) subclass_map
	   		) calls
		   );
		   update_interface_lookup_set p s_info.super_interfaces
	      )
	      cl_info.super_classes);
	)

  let update_special_lookup_set p current_class_sig cs ms s =
    let cmmap =
      try ClassMap.find current_class_sig p.static_special_lookup
      with _ -> ClassMethMap.empty in
    let rmap =
      try ClassMethMap.find (cs,ms) cmmap
      with _ -> ClassMethodMap.empty in
      p.static_special_lookup <-
	(ClassMap.add current_class_sig
	   (ClassMethMap.add (cs,ms)
	      (ClassMethodMap.merge (fun x _ -> x) rmap s) cmmap)
	   p.static_special_lookup)

  let rec invoke_special_lookup p current_class_sig cs ms =
    let current_class = (get_class_info p current_class_sig).class_data in
    let called_class = to_class_node (get_class_info p cs).class_data in
    let (rc,cm) =
      JControlFlow.invoke_special_lookup current_class called_class ms in
    let rcs = rc.c_info.c_name in
    let s = ClassMethodMap.add cm.cm_class_method_signature (rc,cm)
      ClassMethodMap.empty in
      update_special_lookup_set p current_class_sig cs ms s;
      (* we add (cs,ms) to the workset *)
      add_to_workset p (rcs,ms)

  let rec invoke_static_lookup p cs ms =
    let c = to_class_node (get_class_info p cs).class_data in
    let (rc,cm) = JControlFlow.invoke_static_lookup c ms in
    let rcs = rc.c_info.c_name in
      (if not( ClassMethMap.mem (cs,ms) p.static_static_lookup ) then
       	 let s = ClassMethodMap.add cm.cm_class_method_signature
	   (rc,cm) ClassMethodMap.empty in
       	   p.static_static_lookup <-
	     ClassMethMap.add (cs,ms) s p.static_static_lookup;
	   add_to_workset p (rcs,ms)
      );
      rcs

  let parse_instruction p current_class_name op =
    match op with
      | OpNew cs ->
	  add_instantiated_class p cs;
	  add_class_clinits p cs
      | OpConst (`Class _) ->
	  let cs = make_cn "java.lang.Class" in
	    add_instantiated_class p cs;
	    add_class_clinits p cs
      | OpGetStatic (cs,fs)
      | OpPutStatic (cs,fs) ->
	  let rcs_list = resolve_field p cs fs in
	    List.iter
	      (fun rcs ->
		 let ioc_info = get_class_info p rcs in
		   (match ioc_info.class_data with
		      | Class _ -> add_class_clinits p rcs
		      | Interface _ -> add_clinit p rcs
		   )
	      ) rcs_list
      | OpInvoke(`Virtual (TClass cs),ms) ->
	  invoke_virtual_lookup p cs ms
      | OpInvoke(`Virtual (TArray _),ms) ->
	  (* should only happen with [clone()] *)
	  invoke_virtual_lookup p java_lang_object ms
      | OpInvoke(`Interface cs,ms) ->
	  invoke_interface_lookup p cs ms
      | OpInvoke(`Special cs,ms) ->
      	  invoke_special_lookup p current_class_name cs ms
      | OpInvoke(`Static cs,ms) ->
      	  let rcs = invoke_static_lookup p cs ms in
	    add_class_clinits p rcs
      | _ -> ()

  let parse_native_method p allocated_classes calls =
    let normalize_signature s =
      (* hack : why a class should not be encapsulated by L; ? *)
      let len = String.length s in
	if (len > 2) then
	  if (s.[len - 1] = ';') then
	    if (s.[0] = 'L') then
	      String.sub s 1 (len - 2)
	    else failwith "Bad class signature."
	  else s
	else s in
      List.iter
	(fun signature ->
	   match JParseSignature.parse_objectType
	     (normalize_signature signature) with
	       | TArray _ -> ()
	       | TClass cs ->
		   add_instantiated_class p cs;
		   add_class_clinits p cs
	) allocated_classes;
      List.iter
      	(fun (m_class,m_name,m_signature) ->
	   let cs =
	     match JParseSignature.parse_objectType
	       (normalize_signature m_class) with
		 | TArray _ -> failwith "Bad class"
		 | TClass cn -> cn in
	   let (parameters,rettype) =
	     JParseSignature.parse_method_descriptor m_signature in
	   let ms = make_ms m_name parameters rettype in
	     add_to_workset p (cs,ms)
	) calls
    
  let iter_workset p =
    let tail = Dllist.tail p.workset
    in
      Dllist.iter_to_head
	(fun (cs,cm) ->
	   match cm.cm_implementation with
	     | Native ->
		 if not(p.parse_natives) then
		   failwith "A Native Method shouldn't be found in the workset"
		 else
		   let ms = cm.cm_signature in
		   let m_class = JPrint.class_name ~jvm:true cs
		   and m_name = ms_name ms
		   and m_signature =
		     JPrint.method_descriptor ~jvm:true (ms_args ms)
		       (ms_rtype ms) in
		   let m = (m_class,m_name,m_signature) in
		     (try
		   	let (m_alloc, m_calls) =
		   	  (JNativeStubs.get_native_method_allocations m
		   	     p.native_methods_info,
		   	   JNativeStubs.get_native_method_calls m
		   	     p.native_methods_info) in
		   	  parse_native_method p m_alloc m_calls
		      with _ ->
		   	prerr_endline ("warning : found native method " ^ m_class
		   		       ^ "." ^ m_name ^ ":" ^ m_signature
		   		       ^ " not present in the stub file.")
		     )
	     | Java t ->
		 let code = (Lazy.force t).c_code
		 in
		   Array.iter (parse_instruction p cs) code)
	tail

  let new_program_cache entrypoints native_stubs classpath =
    let (parse_natives,native_methods_info) =
      match native_stubs with
	| None -> (false, JNativeStubs.empty_info)
	| Some file -> (true,
			JNativeStubs.parse_native_info_file file) in
    let workset = Dllist.create () in
    let p =
      { classes = ClassMap.empty;
	interfaces = ClassMap.empty;
	static_virtual_lookup = ClassMethMap.empty;
	static_static_lookup = ClassMethMap.empty;
	static_special_lookup = ClassMap.empty;
	clinits = ClassSet.empty;
	workset = workset;
	classpath = classpath;
	native_methods = ClassMethSet.empty;
	parse_natives = parse_natives;
	native_methods_info = native_methods_info }
    in
      List.iter
	(fun (cs,ms) ->
	   add_class_clinits p cs;
	   if defines_method (get_class_info p cs).class_data ms
	   then add_to_workset p (cs,ms))
	entrypoints;
      p
	
  let parse_program entrypoints native_stubs classpath =
    let classpath = Javalib.class_path classpath in
    let p = new_program_cache entrypoints native_stubs classpath in
      iter_workset p;
      if not (ClassMethSet.is_empty p.native_methods)
      then prerr_endline "The program contains native method. Beware that native methods' side effects may invalidate the result of the analysis.";
      Javalib.close_class_path classpath;
      let instantiated_classes =
	ClassMap.fold
	  (fun cs info cmap ->
	     match info.class_data with
	       | Interface _ -> cmap
	       | Class c ->
		   if (info.is_instantiated) then
		     ClassMap.add cs c cmap
		   else cmap) p.classes ClassMap.empty in
	(p, instantiated_classes)

  let parse_program_bench entrypoints classpath =
    let time_start = Sys.time() in
    let (p,_) = parse_program entrypoints None classpath in
    let s = Dllist.size p.workset in
      Printf.printf "Workset of size %d\n" s;
      let time_stop = Sys.time() in
	Printf.printf "program parsed in %fs.\n" (time_stop-.time_start)
end

let static_virtual_lookup virtual_lookup_map cs ms =
  try
    ClassMethMap.find (cs,ms) virtual_lookup_map
  with _ ->
    (* probably dead code *)
    ClassMethodMap.empty

let static_static_lookup static_lookup_map cs ms =
  ClassMethMap.find (cs,ms) static_lookup_map

let static_interface_lookup virtual_lookup_map interfaces_map cs ms =
  let s = ref ClassMethodMap.empty in
  let f =
    (fun x ->
       let calls =
	 static_virtual_lookup virtual_lookup_map x ms in
	 s := ClassMethodMap.merge (fun x _ -> x) !s calls) in
    Program.interface_lookup_action interfaces_map cs f;
    !s

let static_special_lookup special_lookup_map cs ccs cms =
  ClassMethMap.find (ccs,cms) (ClassMap.find cs special_lookup_map)
    
let static_lookup_method p :
    class_name -> method_signature -> int -> Program.class_method ClassMethodMap.t =
  let virtual_lookup_map = p.Program.static_virtual_lookup
  and special_lookup_map = p.Program.static_special_lookup
  and static_lookup_map = p.Program.static_static_lookup
  and interfaces_map = p.Program.interfaces
  and classes_map = p.Program.classes in
    fun cs ms pp ->
      let ioc = to_jclass (ClassMap.find cs classes_map).Program.class_data in
      let m = Javalib.get_method ioc ms in
	match m with
	  | AbstractMethod _ -> failwith "Can't call static_lookup on Abstract Methods"
	  | ConcreteMethod cm ->
	      (match cm.cm_implementation with
		 | Native -> failwith "Can't call static_lookup on Native methods"
		 | Java code ->
		     let c = (Lazy.force code).c_code in
		       try
			 let op = c.(pp) in
			   match op with
			     | OpInvoke(`Interface ccs,cms) ->
				 static_interface_lookup virtual_lookup_map
				   interfaces_map ccs cms
			     | OpInvoke (`Virtual (TClass ccs),cms) ->
				 static_virtual_lookup virtual_lookup_map ccs cms
			     | OpInvoke(`Virtual (TArray _),cms) ->
				 (* should only happen with [clone()] *)
				 static_virtual_lookup virtual_lookup_map
				   java_lang_object cms
			     | OpInvoke (`Static ccs,cms) ->
				 static_static_lookup static_lookup_map ccs cms
			     | OpInvoke (`Special ccs,cms) ->
				 static_special_lookup special_lookup_map cs ccs cms
			     | _ ->
				 failwith "Invalid opcode found at specified program point"
		       with
			 | Not_found -> failwith "Invalid program point"
			 | e -> raise e
	      )

let pcache2jprogram p =
  { classes =
      ClassMap.mapi
	(fun i _ -> (Program.get_class_info p i).Program.class_data)
	p.Program.classes;
    parsed_methods =
      ClassMap.fold
	(fun _ ioc_info cmmap ->
	   MethodMap.fold
	     (fun _ m cmmap ->
		if (m.Program.has_been_parsed) then
		  match m.Program.c_method with
		    | AbstractMethod _ -> assert false
		    | ConcreteMethod cm ->
			ClassMethodMap.add cm.cm_class_method_signature
			  (ioc_info.Program.class_data,cm) cmmap
		else cmmap
	     ) ioc_info.Program.methods cmmap
	) p.Program.classes ClassMethodMap.empty;
    static_lookup_method = static_lookup_method p
  }

(* cf. openjdk6/hotspot/src/share/vm/runtime/thread.cpp *)
let default_entrypoints =
  let initializeSystemClass =
    ("java.lang.System",
     make_ms "initializeSystemClass" [] None)
  in
    List.map
      (fun (cn,ms) -> (make_cn cn, ms))
      (("java.lang.Object",clinit_signature)::
	 ("java.lang.String",clinit_signature)::
	 ("java.lang.System",clinit_signature)::
	 initializeSystemClass::
	 ("java.lang.ThreadGroup",clinit_signature)::
	 ("java.lang.Thread",clinit_signature)::
	 ("java.lang.reflect.Method",clinit_signature)::
	 ("java.lang.ref.Finalizer",clinit_signature)::
	 ("java.lang.Class",clinit_signature)::
	 ("java.lang.OutOfMemoryError",clinit_signature)::
	 ("java.lang.NullPointerException",clinit_signature)::
	 ("java.lang.ClassCastException",clinit_signature)::
	 ("java.lang.ArrayStoreException",clinit_signature)::
	 ("java.lang.ArithmeticException",clinit_signature)::
	 ("java.lang.StackOverflowError",clinit_signature)::
	 ("java.lang.IllegalMonitorStateException",clinit_signature)::
	 ("java.lang.Compiler",clinit_signature)::
	 ("java.lang.reflect.Field",clinit_signature)::
	 []
      )

let parse_program ?(other_entrypoints=default_entrypoints) ?(native_stubs=None)
    classpath csms =
  let (p_cache, instantiated_classes) =
    (Program.parse_program (csms::other_entrypoints) native_stubs classpath) in
    (pcache2jprogram p_cache, instantiated_classes)

let parse_program_bench ?(other_entrypoints=default_entrypoints) classpath csms =
    Program.parse_program_bench (csms::other_entrypoints) classpath
