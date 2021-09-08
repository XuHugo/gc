open Emit

let (@@) = W.Source.(@@)


(* Intrinsics *)

let lower_text_type ctxt : int32 =
  let ft = W.(FieldType (PackedStorageType Pack8, Mutable)) in
  emit_type ctxt Prelude.region W.(ArrayDefType (ArrayType ft))


let compile_text_new ctxt : int32 =
  Emit.lookup_intrinsic ctxt "text_new" (fun () ->
    let at = Prelude.region in
    let typeidx = lower_text_type ctxt in
    let t' = W.(RefType (Nullable, DefHeapType (SynVar typeidx))) in
    emit_func ctxt at W.[i32t; i32t] [t'] (fun ctxt _ ->
      let srcidx = emit_param ctxt at in
      let lenidx = emit_param ctxt at in
      let dstidx = emit_local ctxt at t' in
      List.iter (emit_instr ctxt at) W.[
        local_get (lenidx @@ at);
        rtt_canon (typeidx @@ at);
        array_new_default (typeidx @@ at);
        local_set (dstidx @@ at);
        block voidbt (List.map (fun e -> e @@ at) [
          loop voidbt (List.map (fun e -> e @@ at) [
            local_get (lenidx @@ at);
            i32_eqz;
            br_if (1l @@ at);
            local_get (dstidx @@ at);
            local_get (lenidx @@ at);
            i32_const (1l @@ at);
            i32_sub;
            local_tee (lenidx @@ at);
            local_get (lenidx @@ at);
            local_get (srcidx @@ at);
            i32_add;
            i32_load8_u 0 0l;
            array_set;
            br (0l @@ at);
          ])
        ]);
        local_get (dstidx @@ at);
      ]
    )
  )

let compile_text_cpy ctxt : int32 =
  Emit.lookup_intrinsic ctxt "text_cpy" (fun () ->
    let at = Prelude.region in
    let typeidx = lower_text_type ctxt in
    let t' = W.(RefType (Nullable, DefHeapType (SynVar typeidx))) in
    emit_func ctxt at W.[t'; i32t; t'; i32t; i32t] [] (fun ctxt _ ->
      let dstidx = emit_param ctxt at in
      let dstkidx = emit_param ctxt at in
      let srcidx = emit_param ctxt at in
      let srckidx = emit_param ctxt at in
      let lenidx = emit_param ctxt at in
      emit_instr ctxt at W.(
        block voidbt (List.map (fun e -> e @@ at) [
          loop voidbt (List.map (fun e -> e @@ at) [
            local_get (lenidx @@ at);
            i32_eqz;
            br_if (1l @@ at);
            local_get (dstidx @@ at);
            local_get (lenidx @@ at);
            i32_const (1l @@ at);
            i32_sub;
            local_tee (lenidx @@ at);
            local_get (dstkidx @@ at);
            i32_add;
            local_get (srcidx @@ at);
            local_get (lenidx @@ at);
            local_get (srckidx @@ at);
            i32_add;
            array_get_u;
            array_set;
            br (0l @@ at);
          ])
        ])
      )
    )
  )

let compile_text_cat ctxt : int32 =
  Emit.lookup_intrinsic ctxt "text_cat" (fun () ->
    let text_cpy = compile_text_cpy ctxt in
    let at = Prelude.region in
    let typeidx = lower_text_type ctxt in
    let t' = W.(RefType (Nullable, DefHeapType (SynVar typeidx))) in
    emit_func ctxt at [t'; t'] [t'] (fun ctxt _ ->
      let arg1idx = emit_param ctxt at in
      let arg2idx = emit_param ctxt at in
      let tmpidx = emit_local ctxt at t' in
      List.iter (emit_instr ctxt at) W.[
        local_get (arg1idx @@ at);
        array_len;
        local_get (arg2idx @@ at);
        array_len;
        i32_add;
        rtt_canon (typeidx @@ at);
        array_new_default (typeidx @@ at);
        local_tee (tmpidx @@ at);
        i32_const (0l @@ at);
        local_get (arg1idx @@ at);
        i32_const (0l @@ at);
        local_get (arg1idx @@ at);
        array_len;
        call (text_cpy @@ at);
        local_get (tmpidx @@ at);
        local_get (arg1idx @@ at);
        array_len;
        local_get (arg2idx @@ at);
        i32_const (0l @@ at);
        local_get (arg2idx @@ at);
        array_len;
        call (text_cpy @@ at);
        local_get (tmpidx @@ at);
      ]
    )
  )

let compile_text_eq ctxt : int32 =
  Emit.lookup_intrinsic ctxt "text_eq" (fun () ->
    let at = Prelude.region in
    let typeidx = lower_text_type ctxt in
    let t' = W.(RefType (Nullable, DefHeapType (SynVar typeidx))) in
    emit_func ctxt at [t'; t'] W.[i32t] (fun ctxt _ ->
      let arg1idx = emit_param ctxt at in
      let arg2idx = emit_param ctxt at in
      let lenidx = emit_local ctxt at W.i32t in
      List.iter (emit_instr ctxt at) W.[
        block voidbt (List.map (fun e -> e @@ at) [
          local_get (arg1idx @@ at);
          local_get (arg2idx @@ at);
          ref_eq;
          if_ voidbt (List.map (fun e -> e @@ at) [
            i32_const (1l @@ at); return
          ]) [];
          local_get (arg1idx @@ at);
          array_len;
          local_get (arg2idx @@ at);
          array_len;
          local_tee (lenidx @@ at);
          i32_ne;
          br_if (0l @@ at);
          block voidbt (List.map (fun e -> e @@ at) [
            loop voidbt (List.map (fun e -> e @@ at) [
              local_get (lenidx @@ at);
              i32_eqz;
              br_if (1l @@ at);
              local_get (arg1idx @@ at);
              local_get (lenidx @@ at);
              i32_const (1l @@ at);
              i32_sub;
              local_tee (lenidx @@ at);
              array_get_u;
              local_get (arg2idx @@ at);
              local_get (lenidx @@ at);
              array_get_u;
              i32_eq;
              br_if (0l @@ at);
            ])
          ]);
          i32_const (1l @@ at);
          return;
        ]);
        i32_const (0l @@ at);
      ]
    )
  )