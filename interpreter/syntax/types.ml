(* Types *)

type name = int list

and syn_var = int32
and sem_var = ctx_type Lib.Promise.t
and var = SynVar of syn_var | SemVar of sem_var | RecVar of int32

and mutability = Immutable | Mutable
and nullability = NonNullable | Nullable

and pack_size = Pack8 | Pack16 | Pack32
and extension = SX | ZX

and num_type = I32Type | I64Type | F32Type | F64Type
and ref_type = nullability * heap_type
and heap_type =
  | AnyHeapType
  | EqHeapType
  | I31HeapType
  | DataHeapType
  | FuncHeapType
  | ExternHeapType
  | DefHeapType of var
  | RttHeapType of var
  | BotHeapType

and value_type = NumType of num_type | RefType of ref_type | BotType
and result_type = value_type list

and storage_type =
  ValueStorageType of value_type | PackedStorageType of pack_size
and field_type = FieldType of storage_type * mutability

and struct_type = StructType of field_type list
and array_type = ArrayType of field_type
and func_type = FuncType of result_type * result_type

and str_type =
  | StructDefType of struct_type
  | ArrayDefType of array_type
  | FuncDefType of func_type

and sub_type = SubType of var list * str_type
and def_type = DefType of sub_type | RecDefType of sub_type list
and ctx_type = CtxType of sub_type | RecCtxType of (var * sub_type) list * int32

type 'a limits = {min : 'a; max : 'a option}
type table_type = TableType of Int32.t limits * ref_type
type memory_type = MemoryType of Int32.t limits
type global_type = GlobalType of value_type * mutability
type extern_type =
  | ExternFuncType of func_type
  | ExternTableType of table_type
  | ExternMemoryType of memory_type
  | ExternGlobalType of global_type

type export_type = ExportType of extern_type * name
type import_type = ImportType of extern_type * name * name
type module_type =
  ModuleType of def_type list * import_type list * export_type list


(* Attributes *)

let size = function
  | I32Type | F32Type -> 4
  | I64Type | F64Type -> 8

let packed_size = function
  | Pack8 -> 1
  | Pack16 -> 2
  | Pack32 -> 4


let is_packed_storage_type = function
  | ValueStorageType _ -> false
  | PackedStorageType _ -> true


let is_syn_var = function SynVar _ -> true | _ -> false
let is_sem_var = function SemVar _ -> true | _ -> false
let is_rec_var = function RecVar _ -> true | _ -> false

let as_syn_var = function SynVar x -> x | _ -> assert false
let as_sem_var = function SemVar x -> x | _ -> assert false
let as_rec_var = function RecVar x -> x | _ -> assert false


let is_num_type = function
  | NumType _ | BotType -> true
  | RefType _ -> false

let is_ref_type = function
  | NumType _ -> false
  | RefType _ | BotType -> true


let defaultable_num_type = function
  | _ -> true

let defaultable_ref_type = function
  | (nul, _) -> nul = Nullable

let defaultable_value_type = function
  | NumType t -> defaultable_num_type t
  | RefType t -> defaultable_ref_type t
  | BotType -> assert false


(* Projections *)

let unpacked_storage_type = function
  | ValueStorageType t -> t
  | PackedStorageType _ -> NumType I32Type

let unpacked_field_type (FieldType (t, _)) = unpacked_storage_type t


let as_func_str_type (st : str_type) : func_type =
  match st with
  | FuncDefType ft -> ft
  | _ -> assert false

let as_struct_str_type (st : str_type) : struct_type =
  match st with
  | StructDefType st -> st
  | _ -> assert false

let as_array_str_type (st : str_type) : array_type =
  match st with
  | ArrayDefType at -> at
  | _ -> assert false

let extern_type_of_import_type (ImportType (et, _, _)) = et
let extern_type_of_export_type (ExportType (et, _)) = et


(* Filters *)

let funcs =
  Lib.List.map_filter (function ExternFuncType t -> Some t | _ -> None)
let tables =
  Lib.List.map_filter (function ExternTableType t -> Some t | _ -> None)
let memories =
  Lib.List.map_filter (function ExternMemoryType t -> Some t | _ -> None)
let globals =
  Lib.List.map_filter (function ExternGlobalType t -> Some t | _ -> None)


(* Allocation *)

let alloc_uninit () = Lib.Promise.make ()
let init p ct = Lib.Promise.fulfill p ct
let alloc ct = let p = alloc_uninit () in init p ct; p

let def_of x = Lib.Promise.value x


(* Substitution *)

let subst_num_type s t = t

let subst_heap_type s = function
  | AnyHeapType -> AnyHeapType
  | EqHeapType -> EqHeapType
  | I31HeapType -> I31HeapType
  | DataHeapType -> DataHeapType
  | FuncHeapType -> FuncHeapType
  | ExternHeapType -> ExternHeapType
  | DefHeapType x -> DefHeapType (s x)
  | RttHeapType x -> RttHeapType (s x)
  | BotHeapType -> BotHeapType

let subst_ref_type s = function
  | (nul, t) -> (nul, subst_heap_type s t)

let subst_value_type s = function
  | NumType t -> NumType (subst_num_type s t)
  | RefType t -> RefType (subst_ref_type s t)
  | BotType -> BotType

let subst_stack_type s ts =
 List.map (subst_value_type s) ts

let subst_storage_type s = function
  | ValueStorageType t -> ValueStorageType (subst_value_type s t)
  | PackedStorageType sz -> PackedStorageType sz

let subst_field_type s = function
  | FieldType (t, mut) -> FieldType (subst_storage_type s t, mut)

let subst_struct_type s = function
  | StructType ts -> StructType (List.map (subst_field_type s) ts)

let subst_array_type s = function
  | ArrayType t -> ArrayType (subst_field_type s t)

let subst_func_type s (FuncType (ts1, ts2)) =
  FuncType (subst_stack_type s ts1, subst_stack_type s ts2)

let subst_str_type s = function
  | StructDefType st -> StructDefType (subst_struct_type s st)
  | ArrayDefType at -> ArrayDefType (subst_array_type s at)
  | FuncDefType ft -> FuncDefType (subst_func_type s ft)

let subst_sub_type s = function
  | SubType (xs, st) ->
    SubType (List.map s xs, subst_str_type s st)

let subst_def_type s = function
  | DefType st -> DefType (subst_sub_type s st)
  | RecDefType sts -> RecDefType (List.map (subst_sub_type s) sts)

let subst_rec_type s (x, st) = (s x, subst_sub_type s st)

let subst_ctx_type s = function
  | CtxType st -> CtxType (subst_sub_type s st)
  | RecCtxType (rts, i) -> RecCtxType (List.map (subst_rec_type s) rts, i)


let subst_memory_type s (MemoryType lim) =
  MemoryType lim

let subst_table_type s (TableType (lim, t)) =
  TableType (lim, subst_ref_type s t)

let subst_global_type s (GlobalType (t, mut)) =
  GlobalType (subst_value_type s t, mut)

let subst_extern_type s = function
  | ExternFuncType ft -> ExternFuncType (subst_func_type s ft)
  | ExternTableType tt -> ExternTableType (subst_table_type s tt)
  | ExternMemoryType mt -> ExternMemoryType (subst_memory_type s mt)
  | ExternGlobalType gt -> ExternGlobalType (subst_global_type s gt)


let subst_export_type s (ExportType (et, name)) =
  ExportType (subst_extern_type s et, name)

let subst_import_type s (ImportType (et, module_name, name)) =
  ImportType (subst_extern_type s et, module_name, name)


(* Recursive types *)

let ctx_types_of_def_type x (dt : def_type) : ctx_type list =
  match dt with
  | DefType st -> [CtxType st]
  | RecDefType sts ->
    let rts = Lib.List32.mapi (fun i st -> (SynVar (Int32.add x i), st)) sts in
    Lib.List32.mapi (fun i _ -> RecCtxType (rts, i)) sts

let ctx_types_of_def_types (dts : def_type list) : ctx_type list =
  let rec iter x dts =
    match dts with
    | [] -> []
    | dt::dts' ->
      let cts = ctx_types_of_def_type x dt in
      cts @ iter (Int32.add x (Lib.List32.length cts)) dts'
  in iter 0l dts


let unroll_ctx_type (ct : ctx_type) : sub_type =
  match ct with
  | CtxType st -> st
  | RecCtxType (rts, i) -> snd (Lib.List32.nth rts i)

let expand_ctx_type (ct : ctx_type) : str_type =
  match unroll_ctx_type ct with
  | SubType (_, st) -> st


(* Conversion *)

let sem_var_type c = function
  | SynVar x -> SemVar (Lib.List32.nth c x)
  | SemVar _ -> assert false
  | RecVar x -> RecVar x

let sem_heap_type c = subst_heap_type (sem_var_type c)
let sem_value_type c = subst_value_type (sem_var_type c)
let sem_func_type c = subst_func_type (sem_var_type c)
let sem_memory_type c = subst_memory_type (sem_var_type c)
let sem_table_type c = subst_table_type (sem_var_type c)
let sem_global_type c = subst_global_type (sem_var_type c)
let sem_extern_type c = subst_extern_type (sem_var_type c)

let sem_sub_type c = subst_sub_type (sem_var_type c)
let sem_ctx_type c = subst_ctx_type (sem_var_type c)

let sem_module_type (ModuleType (dts, its, ets)) =
  let cts = ctx_types_of_def_types dts in
  let c = List.map (fun _ -> alloc_uninit ()) cts in
  let s = sem_var_type c in
  List.iter2 (fun x ct -> init x (subst_ctx_type s ct)) c cts;
  let its = List.map (subst_import_type s) its in
  let ets = List.map (subst_export_type s) ets in
  ModuleType ([], its, ets)


(* Free semantic types *)

let hash_sem_var x = Hashtbl.hash_param 20 256 x

module FreeSem =
struct
  let list free xs ts = List.fold_left (fun xs t -> free xs t) xs ts

  let var_type xs = function
    | SemVar x -> if List.memq x xs then xs else x::xs
    | _ -> xs

  let num_type xs = function
    | I32Type | I64Type | F32Type | F64Type -> xs

  let heap_type xs = function
    | AnyHeapType | EqHeapType | I31HeapType | DataHeapType
    | FuncHeapType | ExternHeapType | BotHeapType -> xs
    | DefHeapType x | RttHeapType x -> var_type xs x

  let ref_type xs = function
    | (_, t) -> heap_type xs t

  let value_type xs = function
    | NumType t -> num_type xs t
    | RefType t -> ref_type xs t
    | BotType -> xs

  let packed_type xs t = xs

  let storage_type xs = function
    | ValueStorageType t -> value_type xs t
    | PackedStorageType t -> packed_type xs t

  let field_type xs = function
    | FieldType (st, _) -> storage_type xs st

  let struct_type xs (StructType fts) = list field_type xs fts
  let array_type xs (ArrayType ft) = field_type xs ft
  let func_type xs (FuncType (ts1, ts2)) = list (list value_type) xs [ts1; ts2]

  let str_type xs = function
    | StructDefType st -> struct_type xs st
    | ArrayDefType at -> array_type xs at
    | FuncDefType ft -> func_type xs ft

  let sub_type xs = function
    | SubType (xs', st) -> list var_type (str_type xs st) xs'
  let def_type xs = function
    | DefType st -> sub_type xs st
    | RecDefType sts -> list sub_type xs sts
  let ctx_type xs = function
    | CtxType st -> sub_type xs st
    | RecCtxType (xsts, _) ->
      let xs', sts = List.split xsts in
      list sub_type (list var_type xs xs') sts

  let global_type xs (GlobalType (t, _mut)) = value_type xs t
  let table_type xs (TableType (_lim, t)) = ref_type xs t
  let memory_type xs (MemoryType (_lim)) = xs

  let extern_type xs = function
    | ExternFuncType ft -> func_type xs ft
    | ExternTableType tt -> table_type xs tt
    | ExternMemoryType mt -> memory_type xs mt
    | ExternGlobalType gt -> global_type xs gt


  let rec transitive' xs = function
    | [] -> xs
    | x::rest ->
      let xs' = ctx_type xs (Lib.Promise.value x) in
      transitive' xs' (Lib.List.take (List.length xs' - List.length xs) xs' @ rest)

  let transitive xs =
    List.sort (fun t1 t2 -> compare (hash_sem_var t1) (hash_sem_var t2))
      (transitive' xs xs)
end


(* String conversion *)

let string_of_name n =
  let b = Buffer.create 16 in
  let escape uc =
    if uc < 0x20 || uc >= 0x7f then
      Buffer.add_string b (Printf.sprintf "\\u{%02x}" uc)
    else begin
      let c = Char.chr uc in
      if c = '\"' || c = '\\' then Buffer.add_char b '\\';
      Buffer.add_char b c
    end
  in
  List.iter escape n;
  Buffer.contents b

let string_of_sem_var x =
  Printf.sprintf "%08x" (hash_sem_var x)

let rec string_of_var =
  let inner = ref [] in
  function
  | SynVar x -> I32.to_string_u x
  | SemVar x ->
    let h = hash_sem_var x in
    string_of_sem_var x ^
    if List.mem h !inner || true then "" else
    ( inner := h :: !inner;
      try
        let s = string_of_ctx_type (def_of x) in
        inner := List.tl !inner; "=(" ^ s ^ ")"
      with exn -> inner := []; raise exn
    )
  | RecVar x -> "rec." ^ I32.to_string_u x


and string_of_nullability = function
  | NonNullable -> ""
  | Nullable -> "null "

and string_of_mutability s = function
  | Immutable -> s
  | Mutable -> "(mut " ^ s ^ ")"

and string_of_num_type = function
  | I32Type -> "i32"
  | I64Type -> "i64"
  | F32Type -> "f32"
  | F64Type -> "f64"

and string_of_heap_type = function
  | AnyHeapType -> "any"
  | EqHeapType -> "eq"
  | I31HeapType -> "i31"
  | DataHeapType -> "data"
  | FuncHeapType -> "func"
  | ExternHeapType -> "extern"
  | DefHeapType x -> string_of_var x
  | RttHeapType x -> "(rtt " ^ string_of_var x ^ ")"
  | BotHeapType -> "something"

and string_of_ref_type = function
  | (nul, t) ->
    "(ref " ^ string_of_nullability nul ^ string_of_heap_type t ^ ")"

and string_of_value_type = function
  | NumType t -> string_of_num_type t
  | RefType t -> string_of_ref_type t
  | BotType -> "(something)"

and string_of_result_type ts =
  "[" ^ String.concat " " (List.map string_of_value_type ts) ^ "]"

and string_of_storage_type = function
  | ValueStorageType t -> string_of_value_type t
  | PackedStorageType sz -> "i" ^ string_of_int (8 * packed_size sz)

and string_of_field_type = function
  | FieldType (t, mut) -> string_of_mutability (string_of_storage_type t) mut

and string_of_struct_type = function
  | StructType fts ->
    String.concat " " (List.map (fun ft -> "(field " ^ string_of_field_type ft ^ ")") fts)

and string_of_array_type = function
  | ArrayType ft -> string_of_field_type ft

and string_of_func_type = function
  | FuncType (ins, out) ->
    string_of_result_type ins ^ " -> " ^ string_of_result_type out

and string_of_str_type = function
  | StructDefType st -> "struct " ^ string_of_struct_type st
  | ArrayDefType at -> "array " ^ string_of_array_type at
  | FuncDefType ft -> "func " ^ string_of_func_type ft

and string_of_sub_type = function
  | SubType ([], st) -> string_of_str_type st
  | SubType (xs, st) ->
    String.concat " " ("sub" :: List.map string_of_var xs) ^
    " (" ^ string_of_str_type st ^ ")"

and string_of_def_type = function
  | DefType st -> string_of_sub_type st
  | RecDefType sts ->
    "rec " ^
    String.concat " " (List.map (fun st -> "(" ^ string_of_sub_type st ^ ")") sts)

and equal_var x y =
  match x, y with
  | SynVar x', SynVar y' -> x' = y'
  | SemVar x', SemVar y' -> x' == y'
  | RecVar x', RecVar y' -> x' = y'
  | _, _ -> false
and tie_var_type xs x =
  match Lib.List32.index_where (equal_var x) xs with
  | Some i -> RecVar i
  | None -> x
and tie_rec_types rts =
  let xs, sts = List.split rts in
  List.map (subst_sub_type (tie_var_type xs)) sts

and string_of_ctx_type = function
  | CtxType st -> string_of_sub_type st
  | RecCtxType (rts, i) ->
    "(" ^ string_of_def_type (RecDefType (tie_rec_types rts)) ^ ")." ^
    I32.to_string_u i

let string_of_limits {min; max} =
  I32.to_string_u min ^
  (match max with None -> "" | Some n -> " " ^ I32.to_string_u n)

let string_of_memory_type = function
  | MemoryType lim -> string_of_limits lim

let string_of_table_type = function
  | TableType (lim, t) -> string_of_limits lim ^ " " ^ string_of_ref_type t

let string_of_global_type = function
  | GlobalType (t, mut) -> string_of_mutability (string_of_value_type t) mut

let string_of_extern_type = function
  | ExternFuncType ft -> "func " ^ string_of_func_type ft
  | ExternTableType tt -> "table " ^ string_of_table_type tt
  | ExternMemoryType mt -> "memory " ^ string_of_memory_type mt
  | ExternGlobalType gt -> "global " ^ string_of_global_type gt


let string_of_export_type (ExportType (et, name)) =
  "\"" ^ string_of_name name ^ "\" : " ^ string_of_extern_type et

let string_of_import_type (ImportType (et, module_name, name)) =
  "\"" ^ string_of_name module_name ^ "\" \"" ^
    string_of_name name ^ "\" : " ^ string_of_extern_type et

let string_of_module_type (ModuleType (dts, its, ets)) =
  String.concat "" (
    List.mapi (fun i dt -> "type " ^ string_of_int i ^ " = " ^ string_of_def_type dt ^ "\n") dts @
    List.map (fun it -> "import " ^ string_of_import_type it ^ "\n") its @
    List.map (fun et -> "export " ^ string_of_export_type et ^ "\n") ets
  )
