(*
 * This file is part of SAWJA
 * Copyright (c)2007 Tiphaine Turpin (Université de Rennes 1)
 * Copyright (c)2007, 2008, 2009 Laurent Hubert (CNRS)
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

open Javalib_pack
open JBasics

(** Builds high level representations of Java bytecode programs using basic
    Class Reachability Analysis. *)

(** [parse_program classpath names] parses a list of classes, looking for them
    in the classpath (a list of directories and [.jar] or [.zip] files separated
    with ':' or ';' under Windows).  [other_classes] is set to [default_classes]
    if not given. *)
val parse_program :
  ?other_classes:class_name list -> string -> class_name list -> JCode.jcode JProgram.program

(** classes always loaded (natively) by Sun's JVM HotSpot. *)
val default_classes : class_name list

(**/**)

val parse_program_bench : ?other_classes:class_name list -> string -> class_name list -> unit
