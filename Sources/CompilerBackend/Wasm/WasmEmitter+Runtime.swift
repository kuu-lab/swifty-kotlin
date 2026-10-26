// WasmEmitter+Runtime.swift — wasm-side runtime surface.
//
// Two tiers:
//  * `inlineCalleeNames` — arithmetic/bitwise ops, box/unbox, narrowing:
//    emitted as a few instructions at the call site.
//  * `functionCalleeNames` — emitted wasm helper functions (allocation, the
//    uniform box object model, vtable/itable registration, type-edge walking
//    for `is`/`as`, flat-string materialization, WASI console output).
// Anything else falls back to a return-0 stub plus a WASM-0001 diagnostic.

import Foundation
import CompilerCore

enum WasmRuntimeHelpers {
    private typealias L = WasmModuleContext.WasmLayout

    // MARK: - Inline builtins

    static let inlineCalleeNames: Set<String> = [
        "kk_int_narrow",
        "kk_abort_unreachable",
        "kk_lateinit_is_initialized",
    ]

    static func isBoxName(_ name: String) -> Bool {
        name.hasPrefix("kk_box_")
    }

    static func isUnboxName(_ name: String) -> Bool {
        name.hasPrefix("kk_unbox_")
    }

    /// Callees lowered inline at the call site: arithmetic ops, box/unbox
    /// tagging, narrowing, and abort shims.
    static func isInlineCallee(_ name: String) -> Bool {
        inlineCalleeNames.contains(name)
            || arithmeticOpcodes[name] != nil
            || isBoxName(name)
            || isUnboxName(name)
    }

    static func emitInlineCallee(
        name: String,
        code: inout WasmCode,
        ctx: WasmModuleContext,
        emission: WasmFunctionEmission
    ) {
        if isBoxName(name) {
            emitTaggedBox(code: &code, scratch: emission.scratchLocal)
            return
        }
        if isUnboxName(name) {
            emitTaggedUnbox(code: &code, scratch: emission.scratchLocal)
            return
        }
        if let opcode = arithmeticOpcodes[name] {
            if name == "kk_op_div" || name == "kk_op_rem" || name == "kk_op_mod" {
                emitCheckedDivRem(name: name, code: &code, ctx: ctx, emission: emission)
            } else {
                code.op(opcode)
                if comparisonOpcodes.contains(name) {
                    code.i64ExtendFromComparison()
                }
            }
            return
        }
        switch name {
        case "kk_int_narrow":
            code.i64Const(32)
            code.op(WasmOpcode.i64Shl)
            code.i64Const(32)
            code.op(WasmOpcode.i64ShrS)
        case "kk_abort_unreachable":
            code.op(WasmOpcode.unreachable)
            code.i64Const(0)
        case "kk_lateinit_is_initialized":
            code.i64Const(L.nullSentinel)
            code.op(WasmOpcode.i64Ne)
            code.i64ExtendFromComparison()
        default:
            code.i64Const(0)
        }
    }

    /// MVP representation is uniform raw i64 — boxing is the identity until
    /// the tagged object model lands (M2).
    private static func emitTaggedBox(code: inout WasmCode, scratch: Int) {
        _ = scratch
    }

    /// Identity for the same reason as `emitTaggedBox`.
    private static func emitTaggedUnbox(code: inout WasmCode, scratch: Int) {
        _ = scratch
    }

    private static let arithmeticOpcodes: [String: UInt8] = [
        "kk_op_add": WasmOpcode.i64Add,
        "kk_op_sub": WasmOpcode.i64Sub,
        "kk_op_mul": WasmOpcode.i64Mul,
        "kk_op_div": WasmOpcode.i64DivS,
        "kk_op_rem": WasmOpcode.i64RemS,
        "kk_op_mod": WasmOpcode.i64RemS,
        "kk_op_eq": WasmOpcode.i64Eq,
        "kk_op_ne": WasmOpcode.i64Ne,
        "kk_op_lt": WasmOpcode.i64LtS,
        "kk_op_le": WasmOpcode.i64LeS,
        "kk_op_gt": WasmOpcode.i64GtS,
        "kk_op_ge": WasmOpcode.i64GeS,
        "kk_op_and": WasmOpcode.i64And,
        "kk_op_or": WasmOpcode.i64Or,
        "kk_op_xor": WasmOpcode.i64Xor,
        "kk_op_band": WasmOpcode.i64And,
        "kk_op_bor": WasmOpcode.i64Or,
        "kk_op_bxor": WasmOpcode.i64Xor,
        "kk_op_shl": WasmOpcode.i64Shl,
        "kk_op_shr": WasmOpcode.i64ShrS,
        "kk_op_ushr": WasmOpcode.i64ShrU,
    ]

    private static let comparisonOpcodes: Set<String> = [
        "kk_op_eq", "kk_op_ne", "kk_op_lt", "kk_op_le", "kk_op_gt", "kk_op_ge",
    ]

    /// Kotlin throws ArithmeticException on /0 rather than trapping; signal it
    /// through the thrown channel instead of `i64.div_s`'s hardware trap.
    private static func emitCheckedDivRem(
        name: String,
        code: inout WasmCode,
        ctx: WasmModuleContext,
        emission: WasmFunctionEmission
    ) {
        let lhs = emission.scratchLocal
        let rhs = emission.scratchLocal + 1
        code.localSet(rhs)
        code.localSet(lhs)
        code.localGet(rhs)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(lhs)
        code.localGet(rhs)
        code.op(name == "kk_op_div" ? WasmOpcode.i64DivS : WasmOpcode.i64RemS)
    }

    // MARK: - Emitted helper functions

    static let functionCalleeNames: Set<String> = [
        "$__kk_wasm_alloc",
        "$__kk_wasm_vtable",
        "$__kk_wasm_is_assignable",
        "__kk_wasm_itable_lookup",
        "kk_object_new",
        "kk_array_new",
        "kk_array_new_checked",
        "kk_array_of",
        "kk_empty_array",
        "kk_array_of_nulls",
        "kk_array_get_inbounds",
        "kk_array_get",
        "kk_array_set",
        "kk_array_length",
        "kk_array_size",
        "kk_array_is_empty",
        // Source-backed size bridges (`@KsSymbolName` on the `Array`/`IntArray`/
        // `CharArray`/... extension getters in ArrayIntrinsics.kt).
        "__kk_array_size",
        "__kk_intArray_size",
        "__kk_longArray_size",
        "__kk_shortArray_size",
        "__kk_byteArray_size",
        "__kk_charArray_size",
        "__kk_booleanArray_size",
        "__kk_doubleArray_size",
        "__kk_floatArray_size",
        "__kk_uByteArray_size",
        "__kk_uShortArray_size",
        "__kk_uIntArray_size",
        "__kk_uLongArray_size",
        "kk_any_to_string",
        "kk_any_to_string_nullable",
        "kk_throwable_is_cancellation",
        "kk_object_type_id",
        "kk_object_register_vtable_method",
        "kk_object_register_itable_method",
        "kk_object_register_itable_iface",
        "kk_type_register_super",
        "kk_type_register_iface",
        "kk_op_is",
        "kk_op_cast",
        "kk_array_tag_type",
        "__kk_string_literal_from_utf8",
        "__kk_println_raw",
        "__kk_print_raw",
        "__kk_printStderr",
        "kk_string_length",
        "__kk_string_struct_get_length",
        "kk_string_get",
        "__kk_string_concat_flat",
        "__kk_string_equals_flat",
        // List bridges (`RuntimeCollections.swift` equivalents). The box is an
        // object_new(3, typeID): slot2 = backing array (meta = capacity),
        // slot3 = element count, slot4 = flags (bit0 = read-only).
        "__kk_list_of",
        "__kk_array_list_of",
        "__kk_emptyList",
        "__kk_list_size",
        "__kk_list_check_modification",
        "__kk_list_get",
        "__kk_mutable_list_add",
        "__kk_list_to_list",
        "kk_list_iterator",
        "kk_list_iterator_hasNext",
        "kk_list_iterator_next",
        // Element equality shared by Set dedup / Map key lookup / contains.
        "__kk_wasm_elem_eq",
        // Pair / Map.Entry boxes (`RuntimeArrayBasics.swift` equivalents):
        // slot2=first, slot3=second, slot4=mapRef, slot5=mapKey.
        "__kk_pair_new",
        "__kk_pair_first",
        "__kk_pair_second",
        // Set boxes share the list slot layout; Set.iterator maps to
        // `kk_list_iterator`.
        "__kk_set_of",
        "__kk_set_of_not_null",
        "__kk_hash_set_of",
        "__kk_linked_hash_set_of",
        "__kk_hash_set_new_checked",
        "__kk_emptySet",
        "__kk_set_size",
        "__kk_set_contains",
        "__kk_set_is_empty",
        "__kk_mutable_set_add",
        "__kk_mutable_set_remove",
        "__kk_mutable_set_clear",
        // Map boxes: `{keys@16, values@24, count@32, flags@40}`.
        "__kk_map_of",
        "__kk_hash_map_of",
        "__kk_linked_hash_map_of",
        "__kk_map_of_pairs",
        "__kk_hash_map_of_pairs",
        "__kk_linked_hash_map_of_pairs",
        "__kk_emptyMap",
        "__kk_map_size",
        "__kk_map_is_empty",
        "__kk_map_get",
        "__kk_map_contains_key",
        "__kk_map_contains_value",
        "__kk_map_keys",
        "__kk_map_values",
        "__kk_map_entries",
        "__kk_mutable_map_put",
        "__kk_mutable_map_remove",
        "__kk_mutable_map_clear",
        "__kk_mutable_map_entry_setValue",
        "__kk_map_iterator",
        "__kk_map_iterator_hasNext",
        "__kk_map_iterator_next",
        "__kk_mutable_map_iterator",
        "__kk_mutable_map_iterator_hasNext",
        "__kk_mutable_map_iterator_next",
        "__kk_wasm_map_entry",
        "__kk_map_freeze",
        "__kk_set_freeze",
        "__kk_wasm_map_index_of",
        // Generic iterator entry points dispatch on the iterator type ID.
        "kk_iterator_hasNext",
        "kk_iterator_next",
        // Signed range/progression boxes `{first@16, last@24, step@32}` plus
        // the compiler-lowered for-in iterator `{cur@16, last@24, step@32}`
        // (RuntimeRangeAndDispatch.swift equivalents).
        "__kk_op_rangeTo",
        "__kk_long_rangeTo",
        "__kk_char_rangeTo",
        "__kk_op_rangeUntil",
        "__kk_long_rangeUntil",
        "__kk_char_rangeUntil",
        "__kk_op_downTo",
        "__kk_op_step",
        "__kk_char_range_step",
        "__kk_int_progression_fromClosedRange",
        "__kk_long_progression_fromClosedRange",
        "__kk_char_progression_fromClosedRange",
        "__kk_int_range_induction_le",
        "__kk_int_range_induction_add",
        "__kk_range_first",
        "__kk_range_last",
        "__kk_range_for_in_iterator",
        "__kk_range_for_in_hasNext",
        "__kk_range_for_in_next",
        "__kk_range_to_list",
        "__kk_range_count",
        "__kk_range_isEmpty",
        "__kk_range_sum",
        "__kk_range_reversed",
        "__kk_range_contains",
        "__kk_list_index_of",
        "__kk_list_last_index_of",
        "__kk_list_first",
        "__kk_list_last",
        "__kk_list_is_empty",
        "__kk_string_joinToString",
        // Array component-tag intrinsics: component identity is a pass-through
        // on wasm until reflection needs the installed tag.
        "__kk_array_component_type",
        "__kk_array_tag_component",
    ]

    /// True when `name` has an emitted wasm helper body — used by callee
    /// resolution so throwable intrinsics route to helpers rather than stubs.
    static func isEmittedHelperName(_ name: String) -> Bool {
        functionCalleeNames.contains(name) || throwableHelperKind(for: name) != nil
    }

    /// Builds the wasm body for a helper callee. `nil` means no helper exists
    /// and the caller should fall back to a stub.
    static func emittedBody(
        for name: String,
        argumentCount: Int,
        context ctx: WasmModuleContext
    ) -> [UInt8]? {
        var code = WasmCode()
        let extraLocals: Int
        switch name {
        case "$__kk_wasm_alloc":
            extraLocals = 0
            emitAllocBody(&code, ctx: ctx)
        case "$__kk_wasm_vtable":
            extraLocals = 1
            emitVtableAccessorBody(&code, ctx: ctx)
        case "$__kk_wasm_is_assignable":
            extraLocals = 3
            emitIsAssignableBody(&code, ctx: ctx)
        case "__kk_wasm_itable_lookup":
            extraLocals = 4
            emitItableLookupBody(&code, ctx: ctx)
        case "kk_object_new":
            extraLocals = 1
            emitObjectNewBody(&code, ctx: ctx)
        case "kk_array_new", "kk_array_new_checked":
            extraLocals = 2
            emitArrayNewBody(&code, ctx: ctx)
        case "kk_array_of":
            // Vararg packing already built the array via kk_array_new +
            // kk_array_set; the factory is an identity on that handle.
            extraLocals = 0
            code.localGet(0)
        case "kk_empty_array":
            extraLocals = 0
            code.i64Const(0)
            code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        case "kk_array_of_nulls":
            extraLocals = 0
            code.localGet(0)
            code.i64Const(0)
            code.op(WasmOpcode.i64LtS)
            code.openIf(result: .i64)
            code.i64Const(1)
            code.globalSet(ctx.thrownGlobal)
            code.i64Const(0)
            code.elseBranch()
            code.localGet(0)
            code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
            code.end()
        case "kk_array_get_inbounds":
            extraLocals = 0
            emitArrayGetInboundsBody(&code)
        case "kk_array_get":
            extraLocals = 0
            emitArrayGetBody(&code, ctx: ctx)
        case "kk_array_set":
            extraLocals = 0
            emitArraySetBody(&code, ctx: ctx)
        case "kk_array_length", "kk_array_size",
             "__kk_array_size", "__kk_intArray_size", "__kk_longArray_size",
             "__kk_shortArray_size", "__kk_byteArray_size", "__kk_charArray_size",
             "__kk_booleanArray_size", "__kk_doubleArray_size",
             "__kk_floatArray_size", "__kk_uByteArray_size",
             "__kk_uShortArray_size", "__kk_uIntArray_size",
             "__kk_uLongArray_size":
            extraLocals = 0
            emitLoadMetaBody(&code)
        case "kk_array_is_empty":
            extraLocals = 0
            emitLoadMetaBody(&code)
            code.op(WasmOpcode.i64Eqz)
        case "kk_any_to_string", "kk_any_to_string_nullable":
            // Body uses fixed locals 2...7; extras must cover index 7 for
            // whatever arity was requested first.
            extraLocals = max(0, 8 - argumentCount)
            emitAnyToStringBody(&code, ctx: ctx)
        case "kk_throwable_is_cancellation":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset)
            code.i64Const(Self.stableNominalTypeID("kotlin.coroutines.cancellation.CancellationException"))
            code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_is_assignable", argumentCount: 2))
        case "kk_object_type_id":
            extraLocals = 0
            emitLoadTypeIDBody(&code)
        case "kk_object_register_vtable_method":
            extraLocals = 1
            emitRegisterVtableBody(&code, ctx: ctx)
        case "kk_object_register_itable_method":
            extraLocals = 1
            emitRegisterItableMethodBody(&code, ctx: ctx)
        case "kk_object_register_itable_iface":
            extraLocals = 2
            emitRegisterItableIfaceBody(&code, ctx: ctx)
        case "kk_type_register_super", "kk_type_register_iface":
            extraLocals = 1
            emitRegisterTypeEdgeBody(&code, ctx: ctx)
        case "kk_op_is":
            extraLocals = 3
            emitOpIsBody(&code, ctx: ctx)
        case "kk_op_cast":
            extraLocals = 0
            emitOpCastBody(&code, ctx: ctx)
        case "kk_array_tag_type":
            extraLocals = 0
            emitArrayTagTypeBody(&code)
        case "__kk_string_literal_from_utf8":
            extraLocals = 1
            emitStringLiteralBody(&code, ctx: ctx)
        case "__kk_println_raw":
            guard ctx.isWASI else { return nil }
            ctx.module.addDataSegment(offset: L.newlineAddress, bytes: [0x0A])
            extraLocals = 0
            emitPrintBody(&code, ctx: ctx, newline: true)
        case "__kk_print_raw":
            guard ctx.isWASI else { return nil }
            extraLocals = 0
            emitPrintBody(&code, ctx: ctx, newline: false)
        case "__kk_printStderr":
            guard ctx.isWASI else { return nil }
            extraLocals = 0
            emitPrintBody(&code, ctx: ctx, newline: false, fd: 2)
        case "$__kk_println_stderr":
            guard ctx.isWASI else { return nil }
            ctx.module.addDataSegment(offset: L.newlineAddress, bytes: [0x0A])
            extraLocals = 0
            emitPrintBody(&code, ctx: ctx, newline: true, fd: 2)
        case "kk_string_length", "__kk_string_struct_get_length":
            extraLocals = 0
            emitStringLengthBody(&code)
        case "kk_string_get":
            extraLocals = 0
            emitStringGetBody(&code)
        case "__kk_string_concat_flat":
            extraLocals = 5
            emitConcatFlatBody(&code, ctx: ctx)
        case "__kk_string_equals_flat":
            extraLocals = 4
            emitStringEqualsFlatBody(&code, ctx: ctx)
        case "__kk_list_of", "__kk_array_list_of":
            // (array, count) -> list box adopting the packed array as backing.
            extraLocals = 1
            emitListBoxBody(
                &code, ctx: ctx,
                typeID: name == "__kk_array_list_of" ? L.arrayListTypeID : L.listTypeID,
                readOnly: name == "__kk_list_of",
                arrayLocal: 0, countLocal: 1, objectLocal: argumentCount
            )
            code.localGet(argumentCount)
        case "__kk_emptyList":
            extraLocals = 2
            code.i64Const(0)
            code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
            code.localSet(0)
            emitListBoxBody(
                &code, ctx: ctx,
                typeID: L.listTypeID, readOnly: true,
                arrayLocal: 0, countLocal: nil, objectLocal: 1
            )
            code.localGet(1)
        case "__kk_list_size":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        case "__kk_list_check_modification":
            // View-invalidity tracking doesn't exist yet; accepting silently
            // matches the zero-return ABI.
            extraLocals = 0
            code.i64Const(0)
        case "__kk_list_get":
            extraLocals = 2
            emitListGetBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_mutable_list_add":
            extraLocals = 5
            emitMutableListAddBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_list_to_list":
            extraLocals = 5
            emitListToListBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "kk_list_iterator":
            // Iterator box: slot2 = list, slot3 = index, slot4 = expected
            // element count (concurrent-modification sentinel). Five slots —
            // offsets 16/24/32 must stay inside the allocation.
            extraLocals = 1
            code.i64Const(5)
            code.i64Const(L.listIteratorTypeID)
            code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
            code.localSet(argumentCount)
            emitStoreAt(&code, baseLocal: argumentCount, byteOffset: L.listArrayOffset, valueLocal: 0)
            emitStoreAtConst(&code, baseLocal: argumentCount, byteOffset: L.listCountOffset, value: 0)
            emitAddress(&code, baseLocal: argumentCount, byteOffset: L.listFlagsOffset)
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
            code.i64Store(offset: 0)
            emitIteratorItableRegistration(
                &code, ctx: ctx, objectLocal: argumentCount,
                hasNextHelper: "kk_list_iterator_hasNext",
                nextHelper: "kk_list_iterator_next"
            )
            code.localGet(argumentCount)
        case "kk_list_iterator_hasNext":
            extraLocals = 1
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
            code.localSet(argumentCount)
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
            emitLoadAt(&code, baseLocal: argumentCount, byteOffset: L.listCountOffset)
            code.op(WasmOpcode.i64LtS)
            code.i64ExtendFromComparison()
        case "kk_list_iterator_next":
            extraLocals = 3
            emitListIteratorNextBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_wasm_elem_eq":
            extraLocals = 5
            emitElemEqBody(&code, ctx: ctx)
        case "__kk_pair_new":
            extraLocals = 1
            emitPairNewBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_pair_first":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairFirstOffset)
        case "__kk_pair_second":
            extraLocals = 0
            // Live entry view: mapRef != 0 → map[mapKey], else slot3.
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairMapRefOffset)
            code.op(WasmOpcode.i64Eqz)
            code.openIf(result: .i64)
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairSecondOffset)
            code.elseBranch()
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairMapRefOffset)
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairMapKeyOffset)
            code.call(ctx.emittedHelperIndex(for: "__kk_map_get", argumentCount: 2))
            code.end()
        case "__kk_set_of", "__kk_set_of_not_null", "__kk_hash_set_of",
             "__kk_linked_hash_set_of":
            extraLocals = 7
            emitSetOfBody(&code, ctx: ctx, name: name, argumentCount: argumentCount)
        case "__kk_hash_set_new_checked":
            // Capacity/loadFactor validation is a native-side concern; the
            // wasm path allocates the same empty HashSet box.
            extraLocals = 0
            code.i64Const(0)
            code.i64Const(0)
            code.call(ctx.emittedHelperIndex(for: "__kk_hash_set_of", argumentCount: 2))
        case "__kk_emptySet":
            extraLocals = 0
            code.i64Const(0)
            code.i64Const(0)
            code.call(ctx.emittedHelperIndex(for: "__kk_set_of", argumentCount: 2))
        case "__kk_set_size":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        case "__kk_set_is_empty":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
            code.op(WasmOpcode.i64Eqz)
            code.i64ExtendFromComparison()
        case "__kk_set_contains":
            extraLocals = 3
            emitSetContainsBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_mutable_set_add":
            extraLocals = 6
            emitMutableSetAddBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_mutable_set_remove":
            extraLocals = 5
            emitMutableSetRemoveBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_mutable_set_clear":
            extraLocals = 0
            emitStoreAtConst(&code, baseLocal: 0, byteOffset: L.listCountOffset, value: 0)
            code.i64Const(0)
        case "__kk_map_of", "__kk_hash_map_of", "__kk_linked_hash_map_of",
             "__kk_emptyMap":
            extraLocals = 3
            emitMapOfBody(&code, ctx: ctx, name: name, argumentCount: argumentCount)
        case "__kk_map_of_pairs", "__kk_hash_map_of_pairs",
             "__kk_linked_hash_map_of_pairs":
            extraLocals = 5
            emitMapOfPairsBody(&code, ctx: ctx, name: name, argumentCount: argumentCount)
        case "__kk_map_freeze":
            extraLocals = 0
            emitMapFreezeBody(&code)
        case "__kk_set_freeze":
            extraLocals = 0
            code.localGet(0)
        case "__kk_map_size":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
        case "__kk_map_is_empty":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
            code.op(WasmOpcode.i64Eqz)
            code.i64ExtendFromComparison()
        case "__kk_map_get":
            extraLocals = 1
            emitMapGetBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_map_contains_key":
            extraLocals = 0
            code.localGet(0)
            code.localGet(1)
            code.call(ctx.emittedHelperIndex(for: "__kk_wasm_map_index_of", argumentCount: 2))
            code.i64Const(0)
            code.op(WasmOpcode.i64GeS)
            code.i64ExtendFromComparison()
        case "__kk_map_contains_value":
            extraLocals = 3
            emitMapContainsValueBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_map_keys":
            extraLocals = 4
            emitMapViewBody(&code, ctx: ctx, view: .keys, argumentCount: argumentCount)
        case "__kk_map_values":
            extraLocals = 4
            emitMapViewBody(&code, ctx: ctx, view: .values, argumentCount: argumentCount)
        case "__kk_map_entries":
            extraLocals = 4
            emitMapViewBody(&code, ctx: ctx, view: .entries, argumentCount: argumentCount)
        case "__kk_mutable_map_put":
            extraLocals = 8
            emitMutableMapPutBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_mutable_map_remove":
            extraLocals = 6
            emitMutableMapRemoveBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_mutable_map_clear":
            extraLocals = 0
            emitStoreAtConst(&code, baseLocal: 0, byteOffset: L.mapCountOffset, value: 0)
            code.i64Const(0)
        case "__kk_mutable_map_entry_setValue":
            extraLocals = 2
            emitMutableMapEntrySetValueBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_wasm_map_index_of":
            extraLocals = 5
            emitMapIndexOfBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_map_iterator", "__kk_mutable_map_iterator":
            extraLocals = 1
            emitMapIteratorBody(&code, ctx: ctx, name: name, argumentCount: argumentCount)
        case "__kk_map_iterator_hasNext", "__kk_mutable_map_iterator_hasNext":
            extraLocals = 1
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
            code.localSet(argumentCount)
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
            emitLoadAt(&code, baseLocal: argumentCount, byteOffset: L.mapCountOffset)
            code.op(WasmOpcode.i64LtS)
            code.i64ExtendFromComparison()
        case "__kk_map_iterator_next", "__kk_mutable_map_iterator_next":
            extraLocals = 4
            emitMapIteratorNextBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_wasm_map_entry":
            extraLocals = 1
            emitMapEntryNewBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "kk_iterator_hasNext":
            extraLocals = 1
            emitGenericIteratorDispatch(&code, ctx: ctx, methodSlot: 0)
        case "kk_iterator_next":
            extraLocals = 1
            emitGenericIteratorDispatch(&code, ctx: ctx, methodSlot: 1)
        case "__kk_op_rangeTo", "__kk_long_rangeTo", "__kk_char_rangeTo":
            extraLocals = 1
            emitRangeBoxBody(
                &code, ctx: ctx,
                typeID: Self.rangeBoxTypeID(for: name),
                objectLocal: argumentCount,
                emitFirst: { $0.localGet(0) },
                emitLast: { $0.localGet(1) },
                emitStep: { $0.i64Const(1) }
            )
        case "__kk_op_rangeUntil", "__kk_long_rangeUntil", "__kk_char_rangeUntil":
            extraLocals = 1
            emitRangeBoxBody(
                &code, ctx: ctx,
                typeID: Self.rangeBoxTypeID(for: name),
                objectLocal: argumentCount,
                emitFirst: { $0.localGet(0) },
                emitLast: { code in
                    // `until` end is exclusive: last = rhs - 1. Guard the
                    // Int64.min boundary so the decrement can't wrap into a
                    // non-empty range.
                    code.localGet(1)
                    code.i64Const(Int64.min)
                    code.op(WasmOpcode.i64Eq)
                    code.openIf(result: .i64)
                    code.localGet(0)
                    code.i64Const(1)
                    code.op(WasmOpcode.i64Sub)
                    code.elseBranch()
                    code.localGet(1)
                    code.i64Const(1)
                    code.op(WasmOpcode.i64Sub)
                    code.end()
                },
                emitStep: { $0.i64Const(1) }
            )
        case "__kk_op_downTo":
            extraLocals = 1
            emitRangeBoxBody(
                &code, ctx: ctx,
                typeID: Self.rangeBoxTypeID(for: name),
                objectLocal: argumentCount,
                emitFirst: { $0.localGet(0) },
                emitLast: { $0.localGet(1) },
                emitStep: { $0.i64Const(-1) }
            )
        case "__kk_op_step", "__kk_char_range_step":
            extraLocals = 3
            emitRangeStepBody(&code, ctx: ctx, name: name, argumentCount: argumentCount)
        case "__kk_int_progression_fromClosedRange",
             "__kk_long_progression_fromClosedRange",
             "__kk_char_progression_fromClosedRange":
            extraLocals = 1
            emitRangeBoxBody(
                &code, ctx: ctx,
                typeID: Self.rangeBoxTypeID(for: name),
                objectLocal: argumentCount,
                emitFirst: { $0.localGet(0) },
                emitLast: { $0.localGet(1) },
                emitStep: { $0.localGet(2) }
            )
        case "__kk_int_range_induction_le":
            extraLocals = 0
            code.localGet(0)
            code.localGet(1)
            code.op(WasmOpcode.i64LeS)
            code.i64ExtendFromComparison()
        case "__kk_int_range_induction_add":
            extraLocals = 0
            code.localGet(0)
            code.localGet(1)
            code.op(WasmOpcode.i64Add)
        case "__kk_range_first":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        case "__kk_range_last":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        case "__kk_range_for_in_iterator":
            extraLocals = 1
            emitRangeForInIteratorBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_range_for_in_hasNext":
            extraLocals = 0
            emitRangeHasNextExpr(&code)
            code.i64ExtendFromComparison()
        case "__kk_range_for_in_next":
            extraLocals = 2
            emitRangeForInNextBody(&code, argumentCount: argumentCount)
        case "__kk_range_to_list":
            extraLocals = 6
            emitRangeToListBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_range_count":
            extraLocals = 0
            emitRangeCountBody(&code)
        case "__kk_range_isEmpty":
            extraLocals = 0
            emitRangeIsEmptyBody(&code)
        case "__kk_range_sum":
            extraLocals = 3
            emitRangeSumBody(&code)
        case "__kk_range_reversed":
            extraLocals = 1
            emitRangeReversedBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_range_contains":
            extraLocals = 0
            emitRangeContainsBody(&code)
        case "__kk_list_index_of":
            extraLocals = 4
            emitListIndexOfBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_list_last_index_of":
            extraLocals = 4
            emitListLastIndexOfBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_list_first":
            extraLocals = 0
            code.localGet(0)
            code.i64Const(0)
            code.call(ctx.emittedHelperIndex(for: "__kk_list_get", argumentCount: 2))
        case "__kk_list_last":
            extraLocals = 0
            code.localGet(0)
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
            code.i64Const(1)
            code.op(WasmOpcode.i64Sub)
            code.call(ctx.emittedHelperIndex(for: "__kk_list_get", argumentCount: 2))
        case "__kk_list_is_empty":
            extraLocals = 0
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
            code.op(WasmOpcode.i64Eqz)
            code.i64ExtendFromComparison()
        case "__kk_string_joinToString":
            extraLocals = 6
            emitJoinToStringBody(&code, ctx: ctx, argumentCount: argumentCount)
        case "__kk_array_component_type", "__kk_array_tag_component":
            // Both are pass-throughs: the component descriptor isn't consumed
            // by wasm iteration and arrays carry no installable tag slot yet.
            extraLocals = 0
            code.localGet(0)
        default:
            return emittedThrowableBody(for: name, argumentCount: argumentCount, context: ctx)
        }
        return finish(code: &code, extraLocals: extraLocals)
    }

    private static func finish(code: inout WasmCode, extraLocals: Int) -> [UInt8] {
        var body = WasmCode()
        if extraLocals > 0 {
            body.u(1)
            body.u(UInt64(extraLocals))
            body.op(WasmValType.i64.rawValue)
        } else {
            body.u(0)
        }
        body.append(code)
        body.op(WasmOpcode.end)
        return body.bytes
    }

    // MARK: Address helpers

    /// Pushes `load(baseLocal + byteOffset)`; negative offsets go through i32
    /// math because memarg offsets are unsigned.
    private static func emitLoadAt(
        _ code: inout WasmCode,
        baseLocal: Int,
        byteOffset: Int64
    ) {
        code.localGet(baseLocal)
        code.op(WasmOpcode.i32WrapI64)
        if byteOffset < 0 {
            code.i32Const(Int32(byteOffset))
            code.op(WasmOpcode.i32Add)
            code.i64Load(offset: 0)
        } else {
            code.i64Load(offset: UInt64(byteOffset))
        }
    }

    /// Pushes the i32 address `baseLocal + byteOffset`.
    private static func emitAddress(
        _ code: inout WasmCode,
        baseLocal: Int,
        byteOffset: Int64
    ) {
        code.localGet(baseLocal)
        code.op(WasmOpcode.i32WrapI64)
        if byteOffset != 0 {
            code.i32Const(Int32(byteOffset))
            code.op(WasmOpcode.i32Add)
        }
    }

    private static func emitStoreAt(
        _ code: inout WasmCode,
        baseLocal: Int,
        byteOffset: Int64,
        valueLocal: Int
    ) {
        emitAddress(&code, baseLocal: baseLocal, byteOffset: byteOffset)
        code.localGet(valueLocal)
        code.i64Store(offset: 0)
    }

    private static func emitStoreAtConst(
        _ code: inout WasmCode,
        baseLocal: Int,
        byteOffset: Int64,
        value: Int64
    ) {
        emitAddress(&code, baseLocal: baseLocal, byteOffset: byteOffset)
        code.i64Const(value)
        code.i64Store(offset: 0)
    }

    // MARK: Range helpers

    /// Nominal tag for the `{first@16, last@24, step@32}` box each range
    /// factory produces — `downTo`/`step` yield progressions, `..`/`until`
    /// yield the closed ranges, so `is IntRange`/`is CharProgression` checks
    /// see the same tags the native `RuntimeRangeBox.kind` encodes.
    private static func rangeBoxTypeID(for name: String) -> Int64 {
        switch name {
        case "__kk_op_rangeTo", "__kk_op_rangeUntil":
            return stableNominalTypeID("kotlin.ranges.IntRange")
        case "__kk_long_rangeTo", "__kk_long_rangeUntil":
            return stableNominalTypeID("kotlin.ranges.LongRange")
        case "__kk_char_rangeTo", "__kk_char_rangeUntil":
            return stableNominalTypeID("kotlin.ranges.CharRange")
        case "__kk_op_downTo", "__kk_op_step",
             "__kk_int_progression_fromClosedRange":
            return stableNominalTypeID("kotlin.ranges.IntProgression")
        case "__kk_long_progression_fromClosedRange":
            return stableNominalTypeID("kotlin.ranges.LongProgression")
        case "__kk_char_range_step", "__kk_char_progression_fromClosedRange":
            return stableNominalTypeID("kotlin.ranges.CharProgression")
        default:
            return stableNominalTypeID("kotlin.ranges.IntProgression")
        }
    }

    /// Allocates a 5-slot range box and stores first/last/step into slots
    /// 2/3/4. Leaves the box handle on the stack.
    private static func emitRangeBoxBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        typeID: Int64,
        objectLocal: Int,
        emitFirst: (inout WasmCode) -> Void,
        emitLast: (inout WasmCode) -> Void,
        emitStep: (inout WasmCode) -> Void
    ) {
        code.i64Const(5)
        code.i64Const(typeID)
        code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
        code.localSet(objectLocal)
        emitAddress(&code, baseLocal: objectLocal, byteOffset: 16)
        emitFirst(&code)
        code.i64Store(offset: 0)
        emitAddress(&code, baseLocal: objectLocal, byteOffset: 24)
        emitLast(&code)
        code.i64Store(offset: 0)
        emitAddress(&code, baseLocal: objectLocal, byteOffset: 32)
        emitStep(&code)
        code.i64Store(offset: 0)
        code.localGet(objectLocal)
    }

    /// Pushes the i32 `hasNext` predicate for a `{cur@16,last@24,step@32}`
    /// state: `step>0 ? cur<=last : step<0 ? cur>=last : false`. Shared by
    /// `__kk_range_for_in_hasNext` and the advance path of `..._next`; zeroing
    /// step on overflow makes the recomputation a stable stop.
    private static func emitRangeHasNextExpr(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i32)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LeS)
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i32)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GeS)
        code.elseBranch()
        code.i32Const(0)
        code.end()
        code.end()
    }

    /// `__kk_range_for_in_iterator(range)` — copies `{first,last,step}` off the
    /// range box into a fresh iterator box `{cur,last,step}`.
    private static func emitRangeForInIteratorBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        code.i64Const(5)
        code.i64Const(L.rangeForInIteratorTypeID)
        code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
        code.localSet(argumentCount)
        for offset in [Int64(16), 24, 32] {
            emitAddress(&code, baseLocal: argumentCount, byteOffset: offset)
            emitLoadAt(&code, baseLocal: 0, byteOffset: offset)
            code.i64Store(offset: 0)
        }
        // `range.iterator()` (routed member) returns this box — generic
        // `kk_iterator_hasNext`/`_next` must find the dedicated helpers via
        // the Iterator itable rather than re-dispatching themselves.
        emitIteratorItableRegistration(
            &code, ctx: ctx, objectLocal: argumentCount,
            hasNextHelper: "__kk_range_for_in_hasNext",
            nextHelper: "__kk_range_for_in_next"
        )
        code.localGet(argumentCount)
    }

    /// `__kk_range_for_in_next(it)` — returns `cur` then advances by `step`.
    /// An exhausted iterator returns `cur` unchanged; a wrapped add (the only
    /// way `cur+step` can leave the i64 range, since step's sign is fixed)
    /// zeroes `step` so the next `hasNext` is false — mirroring the native
    /// `RuntimeSignedRangeForInIteratorBox.advance()` overflow stop.
    private static func emitRangeForInNextBody(_ code: inout WasmCode, argumentCount: Int) {
        let cur = argumentCount
        let cand = argumentCount + 1
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(cur)
        emitRangeHasNextExpr(&code)
        code.openIf(result: .i64)
        code.localGet(cur)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.op(WasmOpcode.i64Add)
        code.localSet(cand)
        // Overflow check per direction: step>0 wrapped iff cand<cur, step<0
        // iff cand>cur.
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i32)
        code.localGet(cand)
        code.localGet(cur)
        code.op(WasmOpcode.i64LtS)
        code.elseBranch()
        code.localGet(cand)
        code.localGet(cur)
        code.op(WasmOpcode.i64GtS)
        code.end()
        code.openIf(result: .i64)
        emitStoreAtConst(&code, baseLocal: 0, byteOffset: 32, value: 0)
        code.localGet(cur)
        code.elseBranch()
        emitStoreAt(&code, baseLocal: 0, byteOffset: 16, valueLocal: cand)
        code.localGet(cur)
        code.end()
        code.elseBranch()
        code.localGet(cur)
        code.end()
    }

    /// `__kk_op_step(range, step)` — validates `step > 0` (throws
    /// IllegalArgumentException through `thrownGlobal` otherwise, mirroring
    /// STDLIB-022), keeps the source direction's sign, and aligns `last` down
    /// to the final element the step actually lands on, matching the native
    /// `getProgressionLastElement` adjustment.
    private static func emitRangeStepBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        name: String,
        argumentCount: Int
    ) {
        let obj = argumentCount
        let nextStep = argumentCount + 1
        let aligned = argumentCount + 2
        code.localGet(1)
        code.i64Const(0)
        code.op(WasmOpcode.i64LeS)
        code.openIf(result: .i64)
        emitLiteralString(&code, ctx: ctx, "Step must be positive.")
        code.call(ctx.emittedHelperIndex(
            for: "__kk_illegal_argument_exception_new_message",
            argumentCount: 1
        ))
        code.globalSet(ctx.thrownGlobal)
        code.localGet(0)
        code.elseBranch()
        // nextStep = oldStep < 0 ? -step : step
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i64)
        code.i64Const(0)
        code.localGet(1)
        code.op(WasmOpcode.i64Sub)
        code.elseBranch()
        code.localGet(1)
        code.end()
        code.localSet(nextStep)
        // alignedLast: positive → first<=last ? last - urem(last-first, step)
        //              : last; negative → first>=last ? last + urem(first-last,
        //              -step) : last. Empty progressions keep `last` like the
        //              native path.
        code.localGet(nextStep)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LeS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i64Sub)
        code.localGet(nextStep)
        code.op(WasmOpcode.i64RemU)
        code.op(WasmOpcode.i64Sub)
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.end()
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GeS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64Sub)
        code.i64Const(0)
        code.localGet(nextStep)
        code.op(WasmOpcode.i64Sub)
        code.op(WasmOpcode.i64RemU)
        code.op(WasmOpcode.i64Add)
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.end()
        code.end()
        code.localSet(aligned)
        emitRangeBoxBody(
            &code, ctx: ctx,
            typeID: Self.rangeBoxTypeID(for: name),
            objectLocal: obj,
            emitFirst: { code in emitLoadAt(&code, baseLocal: 0, byteOffset: 16) },
            emitLast: { $0.localGet(aligned) },
            emitStep: { $0.localGet(nextStep) }
        )
        code.end()
    }

    /// `__kk_range_to_list(range)` — materializes `{first,last,step}` into a
    /// read-only list box (`toList()` on a range/progression). Counts first so
    /// the backing array is exact, then fills it with the same boundary
    /// predicate the for-in iterator uses.
    private static func emitRangeToListBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let arr = argumentCount
        let count = argumentCount + 1
        let cur = argumentCount + 2
        let idx = argumentCount + 3
        let listObj = argumentCount + 4
        let step = argumentCount + 5
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.localSet(step)
        // count = step>0 ? (first<=last ? (last-first)/step+1 : 0)
        //        : step<0 ? (first>=last ? (first-last)/(-step)+1 : 0) : 0
        code.localGet(step)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LeS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i64Sub)
        code.localGet(step)
        code.op(WasmOpcode.i64DivS)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.elseBranch()
        code.i64Const(0)
        code.end()
        code.elseBranch()
        code.localGet(step)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GeS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64Sub)
        code.i64Const(0)
        code.localGet(step)
        code.op(WasmOpcode.i64Sub)
        code.op(WasmOpcode.i64DivS)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.elseBranch()
        code.i64Const(0)
        code.end()
        code.elseBranch()
        code.i64Const(0)
        code.end()
        code.end()
        code.localSet(count)
        code.localGet(count)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(arr)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(cur)
        code.i64Const(0)
        code.localSet(idx)
        code.openBlock()
        code.openLoop()
        // hasNext: step>0 ? cur<=last : step<0 ? cur>=last : false
        code.localGet(step)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i32)
        code.localGet(cur)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LeS)
        code.elseBranch()
        code.localGet(step)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i32)
        code.localGet(cur)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GeS)
        code.elseBranch()
        code.i32Const(0)
        code.end()
        code.end()
        code.op(WasmOpcode.i32Eqz)
        code.brIf(1)
        // arr[idx] = cur — elements sit at base + idx*8 (meta is at base-16).
        code.localGet(arr)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(idx)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(cur)
        code.i64Store(offset: 0)
        code.localGet(cur)
        code.localGet(step)
        code.op(WasmOpcode.i64Add)
        code.localSet(cur)
        code.localGet(idx)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(idx)
        code.br(0)
        code.end()
        code.end()
        emitListBoxBody(
            &code, ctx: ctx,
            typeID: L.listTypeID, readOnly: true,
            arrayLocal: arr, countLocal: count, objectLocal: listObj
        )
        code.localGet(listObj)
    }

    /// `__kk_range_count(range)` — element count with the native wrapping
    /// arithmetic: `(last &- first) / step &+ 1` (i64 sub/add wrap naturally).
    private static func emitRangeCountBody(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LeS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i64Sub)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.op(WasmOpcode.i64DivS)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.elseBranch()
        code.i64Const(0)
        code.end()
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GeS)
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64Sub)
        code.i64Const(0)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.op(WasmOpcode.i64Sub)
        code.op(WasmOpcode.i64DivS)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.elseBranch()
        code.i64Const(0)
        code.end()
        code.elseBranch()
        code.i64Const(0)
        code.end()
        code.end()
    }

    /// `__kk_range_isEmpty(range)` — `step>0 ? first>last : step<0 ?
    /// first<last : true`, matching `kk_range_isEmpty`.
    private static func emitRangeIsEmptyBody(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i32)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GtS)
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i32)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LtS)
        code.elseBranch()
        code.i32Const(1)
        code.end()
        code.end()
        code.i64ExtendFromComparison()
    }

    /// `__kk_range_sum(range)` — wraps at i64 (Kotlin's Long-type sum for
    /// Long progressions; the Int 32-bit wrap is an accepted gap until wasm
    /// gains a tagged element type).
    private static func emitRangeSumBody(_ code: inout WasmCode) {
        let cur = 1
        let sum = 2
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(cur)
        code.i64Const(0)
        code.localSet(sum)
        code.openBlock()
        code.openLoop()
        // hasNext on the *advancing* cursor: step>0 ? cur<=last : cur>=last
        // (step==0 falls to false via the i32Const(0) arm).
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i32)
        code.localGet(cur)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LeS)
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i32)
        code.localGet(cur)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GeS)
        code.elseBranch()
        code.i32Const(0)
        code.end()
        code.end()
        code.op(WasmOpcode.i32Eqz)
        code.brIf(1)
        code.localGet(sum)
        code.localGet(cur)
        code.op(WasmOpcode.i64Add)
        code.localSet(sum)
        code.localGet(cur)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.op(WasmOpcode.i64Add)
        code.localSet(cur)
        code.br(0)
        code.end()
        code.end()
        code.localGet(sum)
    }

    /// `__kk_range_reversed(range)` — `{last, first, -step}` progression box.
    /// The tag approximates `IntProgression` for all element kinds until the
    /// helper learns the source nominal (documented gap vs `is CharProgression`).
    private static func emitRangeReversedBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        emitRangeBoxBody(
            &code, ctx: ctx,
            typeID: Self.stableNominalTypeID("kotlin.ranges.IntProgression"),
            objectLocal: argumentCount,
            emitFirst: { code in emitLoadAt(&code, baseLocal: 0, byteOffset: 24) },
            emitLast: { code in emitLoadAt(&code, baseLocal: 0, byteOffset: 16) },
            emitStep: { code in
                code.i64Const(0)
                emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
                code.op(WasmOpcode.i64Sub)
            }
        )
    }

    /// `__kk_range_contains(range, value)` — bounds plus step congruence,
    /// matching `runtimeRangeContains`: step>0 → first<=v<=last &&
    /// (v-first)%step==0; step<0 → last<=v<=first && (first-v)%(-step)==0.
    private static func emitRangeContainsBody(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf(result: .i32)
        // v >= first && v <= last && (v-first) % step == 0
        code.localGet(1)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i64GeS)
        code.localGet(1)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64LeS)
        code.op(WasmOpcode.i32And)
        code.localGet(1)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i64Sub)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.op(WasmOpcode.i64RemS)
        code.op(WasmOpcode.i64Eqz)
        code.op(WasmOpcode.i32And)
        code.elseBranch()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf(result: .i32)
        // v <= first && v >= last && (first-v) % (-step) == 0
        code.localGet(1)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i64LeS)
        code.localGet(1)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.op(WasmOpcode.i64GeS)
        code.op(WasmOpcode.i32And)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localGet(1)
        code.op(WasmOpcode.i64Sub)
        code.i64Const(0)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 32)
        code.op(WasmOpcode.i64Sub)
        code.op(WasmOpcode.i64RemS)
        code.op(WasmOpcode.i64Eqz)
        code.op(WasmOpcode.i32And)
        code.elseBranch()
        code.i32Const(0)
        code.end()
        code.end()
        code.i64ExtendFromComparison()
    }

    /// `__kk_list_index_of(list, elem)` — linear scan with `__kk_wasm_elem_eq`
    /// over the shared `{array@16,count@24}` box; -1 when absent. Source-List
    /// overrides can't dispatch (no kklib bodies), matching the box fast path.
    private static func emitListIndexOfBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let arr = argumentCount
        let count = argumentCount + 1
        let i = argumentCount + 2
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(arr)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.localSet(count)
        code.i64Const(0)
        code.localSet(i)
        code.openBlock()
        code.openLoop()
        code.localGet(i)
        code.localGet(count)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        // elem_eq(arr[i], element)
        code.localGet(arr)
        code.localGet(i)
        code.call(ctx.emittedHelperIndex(for: "kk_array_get_inbounds", argumentCount: 2))
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.localGet(i)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(i)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(i)
        code.br(0)
        code.end()
        code.end()
        code.i64Const(-1)
    }

    /// `__kk_list_last_index_of(list, elem)` — same scan from the tail.
    private static func emitListLastIndexOfBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let arr = argumentCount
        let i = argumentCount + 1
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(arr)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.i64Const(1)
        code.op(WasmOpcode.i64Sub)
        code.localSet(i)
        code.openBlock()
        code.openLoop()
        code.localGet(i)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.brIf(1)
        code.localGet(arr)
        code.localGet(i)
        code.call(ctx.emittedHelperIndex(for: "kk_array_get_inbounds", argumentCount: 2))
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.localGet(i)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(i)
        code.i64Const(1)
        code.op(WasmOpcode.i64Sub)
        code.localSet(i)
        code.br(0)
        code.end()
        code.end()
        code.i64Const(-1)
    }

    /// `__kk_string_joinToString(list, sep, prefix, postfix)` — joins the
    /// shared-layout box into a flat string. Zero args pick the Kotlin
    /// defaults (`", "`, `""`, `""`); `limit`/`truncated`/`transform` params
    /// beyond arity 4 are ignored (documented gap). Elements stringify via
    /// `kk_any_to_string(elem, 1)` — heap objects render as flat strings,
    /// primitives as ints; object `toString` overrides can't dispatch yet.
    private static func emitJoinToStringBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let res = argumentCount
        let i = argumentCount + 1
        let count = argumentCount + 2
        let arr = argumentCount + 3
        let sepObj = argumentCount + 4
        let postObj = argumentCount + 5
        // defaults-for-zero on separator/prefix/postfix
        for (arg, fallback) in [(1, ", "), (2, ""), (3, "")] {
            code.localGet(arg)
            code.op(WasmOpcode.i64Eqz)
            code.openIf(result: .i64)
            emitLiteralString(&code, ctx: ctx, fallback)
            code.elseBranch()
            code.localGet(arg)
            code.end()
            code.localSet(arg == 1 ? sepObj : (arg == 2 ? res : postObj))
        }
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(arr)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 24)
        code.localSet(count)
        code.i64Const(0)
        code.localSet(i)
        code.openBlock()
        code.openLoop()
        code.localGet(i)
        code.localGet(count)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(i)
        code.i64Const(0)
        code.op(WasmOpcode.i64GtS)
        code.openIf()
        code.localGet(res)
        code.localGet(sepObj)
        code.call(ctx.emittedHelperIndex(for: "__kk_string_concat_flat", argumentCount: 2))
        code.localSet(res)
        code.end()
        code.localGet(res)
        code.localGet(arr)
        code.localGet(i)
        code.call(ctx.emittedHelperIndex(for: "kk_array_get_inbounds", argumentCount: 2))
        code.i64Const(1)
        code.call(ctx.emittedHelperIndex(for: "kk_any_to_string", argumentCount: 2))
        code.call(ctx.emittedHelperIndex(for: "__kk_string_concat_flat", argumentCount: 2))
        code.localSet(res)
        code.localGet(i)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(i)
        code.br(0)
        code.end()
        code.end()
        code.localGet(res)
        code.localGet(postObj)
        code.call(ctx.emittedHelperIndex(for: "__kk_string_concat_flat", argumentCount: 2))
    }

    // MARK: Helper bodies

    /// `size -> i64`: lazy-initialized bump allocator. `size` is the number of
    /// body bytes the returned pointer may write; the 16-byte object header at
    /// `ptr-16` is reserved on top of it so the next allocation's header can
    /// never land inside the previous object's body.
    private static func emitAllocBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.globalGet(ctx.heapGlobal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.globalGet(ctx.dataEndGlobal)
        code.globalSet(ctx.heapGlobal)
        code.end()
        code.globalGet(ctx.heapGlobal)      // old
        code.globalGet(ctx.heapGlobal)      // old, old
        code.localGet(0)
        code.i64Const(16 + 7)
        code.op(WasmOpcode.i64Add)
        code.i64Const(-8)
        code.op(WasmOpcode.i64And)
        code.op(WasmOpcode.i64Add)          // old, old + align8(16+size)
        code.globalSet(ctx.heapGlobal)      // old
        code.i64Const(16)                   // object base sits past the
        code.op(WasmOpcode.i64Add)          // 16-byte header at old
    }

    /// `obj -> i64`: object's vtable pointer (body slot 1), allocated lazily.
    private static func emitVtableAccessorBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.vtableSlotOffset)
        code.localTee(1)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(Int64(L.vtableSlots * 8))
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(1)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.vtableSlotOffset, valueLocal: 1)
        code.end()
        code.localGet(1)
    }

    /// `layoutWords, classID -> i64`: header {typeID@-16, layoutWords@-8} +
    /// slots at 0... (slot 0 = iface map, slot 1 = vtable, fields at 2+).
    private static func emitObjectNewBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.i64Const(8)
        code.op(WasmOpcode.i64Mul)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        emitStoreAt(&code, baseLocal: 2, byteOffset: L.typeIDOffset, valueLocal: 1)
        emitStoreAt(&code, baseLocal: 2, byteOffset: L.metaOffset, valueLocal: 0)
        code.localGet(2)
    }

    /// `count -> i64`: uniform box with ARRAY tag and length in the meta slot.
    private static func emitArrayNewBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.i64Const(8)
        code.op(WasmOpcode.i64Mul)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        emitStoreAtConst(&code, baseLocal: 2, byteOffset: L.typeIDOffset, value: L.arrayTypeID)
        emitStoreAt(&code, baseLocal: 2, byteOffset: L.metaOffset, valueLocal: 0)
        code.localGet(2)
    }

    /// `base, slot -> i64`: raw slot load — the native hot path shared by
    /// object fields (slots >= 2) and array elements.
    private static func emitArrayGetInboundsBody(_ code: inout WasmCode) {
        code.localGet(0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(1)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
    }

    /// `array, index -> i64`: bounds-checked element load (length in meta).
    private static func emitArrayGetBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        emitBoundsCheck(&code, ctx: ctx, indexLocal: 1, baseLocal: 0)
        emitArrayGetInboundsBody(&code)
    }

    /// `array, index, value -> i64`: bounds-checked element store.
    private static func emitArraySetBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        emitBoundsCheck(&code, ctx: ctx, indexLocal: 1, baseLocal: 0)
        code.localGet(0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(1)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.i64Store(offset: 0)
        code.localGet(2)
    }

    private static func emitBoundsCheck(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        indexLocal: Int,
        baseLocal: Int
    ) {
        code.localGet(indexLocal)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.localGet(indexLocal)
        emitLoadAt(&code, baseLocal: baseLocal, byteOffset: L.metaOffset)
        code.op(WasmOpcode.i64GeS)
        code.op(WasmOpcode.i32Or)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
    }

    private static func emitLoadMetaBody(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.metaOffset)
    }

    private static func emitLoadTypeIDBody(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset)
    }

    private static func emitRegisterVtableBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_vtable", argumentCount: 1))
        code.localSet(3)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(1)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.i64Store(offset: 0)
        code.i64Const(0)
    }

    private static func emitRegisterItableMethodBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_vtable", argumentCount: 1))
        code.localSet(4)
        code.localGet(4)
        code.op(WasmOpcode.i32WrapI64)
        // slot = vtableDirectSlots + ifaceSlot*itableStride + methodSlot
        code.localGet(1)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(Int32(L.itableStride))
        code.op(WasmOpcode.i32Mul)
        code.i32Const(Int32(L.vtableDirectSlots))
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(3)
        code.i64Store(offset: 0)
        code.i64Const(0)
    }

    /// `obj, interfaceTypeID, ifaceSlot -> 0`: appends a (typeID, slot) pair to
    /// the object's interface map stored in slot 0.
    private static func emitRegisterItableIfaceBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: 0)
        code.localTee(3)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(Int64(8 + 2 * L.ifaceMapCapacity * 8))
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(3)
        emitStoreAt(&code, baseLocal: 0, byteOffset: 0, valueLocal: 3)
        code.end()
        // count = load(map); store pair at map+8+count*16; count++
        emitLoadAt(&code, baseLocal: 3, byteOffset: 0)
        code.localSet(4)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(4)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(16)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(1)
        code.i64Store(offset: 8)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(4)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(16)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.i64Store(offset: 16)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(4)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.i64Store(offset: 0)
        code.i64Const(0)
    }

    /// `obj, interfaceTypeID, methodSlot -> i64`: resolve a dynamic itable
    /// dispatch: find ifaceSlot in the map, then read the vtable entry.
    private static func emitItableLookupBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        // locals: 3=map, 4=count, 5=i, 6=ifaceSlot
        emitLoadAt(&code, baseLocal: 0, byteOffset: 0)
        code.localTee(3)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: 3, byteOffset: 0)
        code.localSet(4)
        code.i64Const(0)
        code.localSet(5)
        code.openLoop()
        code.localGet(5)
        code.localGet(4)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // load(map+8+i*16) == typeID ?
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(5)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(16)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 8)
        code.localGet(1)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        // ifaceSlot = load(map+16+i*16); vtable[vtableDirect + slot*stride + m]
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(5)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(16)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 16)
        code.localSet(6)
        code.localGet(0)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_vtable", argumentCount: 1))
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(6)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(Int32(L.itableStride))
        code.op(WasmOpcode.i32Mul)
        code.i32Const(Int32(L.vtableDirectSlots))
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.op(WasmOpcode.return)
        code.end()
        // i++
        code.localGet(5)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(5)
        code.br(0)
        code.end()
        code.i64Const(0)
    }

    /// `child, parent -> 0`: prepend an edge node {child, parent, next}.
    private static func emitRegisterTypeEdgeBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.i64Const(24)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 0, valueLocal: 0)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 8, valueLocal: 1)
        emitAddress(&code, baseLocal: 2, byteOffset: 16)
        code.globalGet(ctx.edgeHeadGlobal)
        code.i64Store(offset: 0)
        code.localGet(2)
        code.globalSet(ctx.edgeHeadGlobal)
        code.i64Const(0)
    }

    /// `source, target -> i64`: transitive closure over the type-edge list
    /// (iteration-capped fixpoint; edges form a DAG in practice).
    private static func emitIsAssignableBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        // locals: 2=current, 3=node, 4=iters
        code.localGet(0)
        code.localSet(2)
        code.openLoop() // $outer
        code.localGet(2)
        code.localGet(1)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.i64Const(1)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(4)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localTee(4)
        code.i64Const(1024)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.globalGet(ctx.edgeHeadGlobal)
        code.localSet(3)
        code.openLoop() // $scan
        code.localGet(3)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.i64Load(offset: 0)
        code.localGet(2)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.i64Load(offset: 8)
        code.localSet(2)
        code.br(2) // continue $outer
        code.end()
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.i64Load(offset: 16)
        code.localSet(3)
        code.br(0) // continue $scan
        code.end() // $scan
        code.end() // $outer
        code.i64Const(0)
    }

    /// The `is` result for a null input: true iff the token is nullable or
    /// names the null type itself.
    private static func emitNullIsResult(_ code: inout WasmCode) {
        code.localGet(1)
        code.i64Const(0x100)
        code.op(WasmOpcode.i64And)
        code.i64Truthy()
        code.openIf(result: .i64)
        code.i64Const(1)
        code.elseBranch()
        code.localGet(1)
        code.i64Const(0xFF)
        code.op(WasmOpcode.i64And)
        code.i64Const(5) // nullBase
        code.op(WasmOpcode.i64Eq)
        code.i64ExtendFromComparison()
        code.end()
        code.op(WasmOpcode.return)
    }

    /// `value, typeToken -> i64`: token layout mirrors
    /// RuntimeTypeTokenEncoding — base = token & 0xFF, nullable = token & 0x100,
    /// payload = token >> 9.
    private static func emitOpIsBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        // locals: 2=base, 3=payload, 4=isHeapPtr
        code.localGet(0)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        emitNullIsResult(&code)
        code.end()
        code.localGet(0)
        code.i64Const(L.nullSentinel)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        emitNullIsResult(&code)
        code.end()
        // base = token & 0xFF; payload = token >> 9
        code.localGet(1)
        code.i64Const(0xFF)
        code.op(WasmOpcode.i64And)
        code.localSet(2)
        code.localGet(1)
        code.i64Const(9)
        code.op(WasmOpcode.i64ShrU)
        code.localSet(3)
        // isHeapPtr = v >= dataEnd && v < heap (heap==0 → false)
        code.localGet(0)
        code.globalGet(ctx.dataEndGlobal)
        code.op(WasmOpcode.i64GeU)
        code.localGet(0)
        code.globalGet(ctx.heapGlobal)
        code.op(WasmOpcode.i64LtU)
        code.op(WasmOpcode.i32And)
        code.i64ExtendFromComparison()
        code.localSet(4)
        // base == anyBase(1) → 1
        code.localGet(2)
        code.i64Const(1)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.i64Const(1)
        code.op(WasmOpcode.return)
        code.end()
        // base == unitBase(15) or nullBase(5) → 0 (null handled above)
        for base: Int64 in [5, 15] {
            code.localGet(2)
            code.i64Const(base)
            code.op(WasmOpcode.i64Eq)
            code.openIf()
            code.i64Const(0)
            code.op(WasmOpcode.return)
            code.end()
        }
        // base == nominalBase(6): object type ID + edge walk
        code.localGet(2)
        code.i64Const(6)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(4)
        code.i64Truthy()
        code.openIf()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset)
        code.localGet(3)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_is_assignable", argumentCount: 2))
        code.op(WasmOpcode.return)
        code.elseBranch()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.end()
        // base == stringBase(2): heap object tagged string
        code.localGet(2)
        code.i64Const(2)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(4)
        code.i64Truthy()
        code.openIf(result: .i64)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset)
        code.i64Const(L.stringTypeID)
        code.op(WasmOpcode.i64Eq)
        code.i64ExtendFromComparison()
        code.elseBranch()
        code.i64Const(0)
        code.end()
        code.op(WasmOpcode.return)
        code.end()
        // int-family bases {3,4,7,9,10,16,17} → Int(3)/Bool(4) match tagged.
        var intFamilyTest = false
        for base: Int64 in [3, 4, 7, 9, 10, 16, 17] {
            code.localGet(2)
            code.i64Const(base)
            code.op(WasmOpcode.i64Eq)
            if intFamilyTest { code.op(WasmOpcode.i32Or) }
            intFamilyTest = true
        }
        code.openIf()
        // tagged odd value → only Int/Bool; even non-heap → raw (unsound match,
        // mirroring the native fallback for unboxed primitives); heap → 0.
        code.localGet(0)
        code.i64Const(1)
        code.op(WasmOpcode.i64And)
        code.i64Truthy()
        code.openIf(result: .i64)
        code.localGet(2)
        code.i64Const(3)
        code.op(WasmOpcode.i64Eq)
        code.localGet(2)
        code.i64Const(4)
        code.op(WasmOpcode.i64Eq)
        code.op(WasmOpcode.i32Or)
        code.i64ExtendFromComparison()
        code.op(WasmOpcode.return)
        code.elseBranch()
        code.localGet(4)
        code.i64Truthy()
        code.openIf(result: .i64)
        code.i64Const(0)
        code.elseBranch()
        code.i64Const(1)
        code.end()
        code.op(WasmOpcode.return)
        code.end()
        // A result-typed `if` pushes its result at `end` even when both arms
        // returned; swallow it so the enclosing void `if` balances.
        code.op(WasmOpcode.drop)
        code.end()
        // Remaining bases (long/double/float/char/function/...): tagged values
        // can't be distinguished → 0; heap objects → 0; raw evens → 1.
        code.localGet(0)
        code.i64Const(1)
        code.op(WasmOpcode.i64And)
        code.i64Truthy()
        code.openIf(result: .i64)
        code.i64Const(0)
        code.elseBranch()
        code.localGet(4)
        code.i64Truthy()
        code.openIf(result: .i64)
        code.i64Const(0)
        code.elseBranch()
        code.i64Const(1)
        code.end()
        code.end()
    }

    /// `value, typeToken -> i64`: `as` — pass through on match, signal a
    /// thrown exception otherwise.
    private static func emitOpCastBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "kk_op_is", argumentCount: 2))
        code.i64Truthy()
        code.openIf(result: .i64)
        code.localGet(0)
        code.elseBranch()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.end()
    }

    /// `array, typeID -> i64`: retag the box's nominal identity.
    private static func emitArrayTagTypeBody(_ code: inout WasmCode) {
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset, valueLocal: 1)
        code.localGet(0)
    }

    /// `ptr, len -> i64`: flat String {data, length, byteCount, hash} with the
    /// string type tag in the header slot.
    private static func emitStringLiteralBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.i64Const(32) // {data, length, byteCount, hash}
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        emitStoreAtConst(&code, baseLocal: 2, byteOffset: L.typeIDOffset, value: L.stringTypeID)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 0, valueLocal: 0)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 8, valueLocal: 1)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 16, valueLocal: 1)
        code.localGet(2)
    }

    /// `fd_write(fd, iovec, 1, nwritten)` — drops the errno result.
    private static func emitFDWrite(_ code: inout WasmCode, ctx: WasmModuleContext, fd: Int32 = 1) {
        code.i32Const(fd)
        code.i32Const(Int32(L.iovecAddress))
        code.i32Const(1)
        code.i32Const(Int32(L.nwrittenAddress))
        code.call(ctx.wasmImportFDWrite())
        code.op(WasmOpcode.drop)
    }

    /// `string -> i64`: WASI fd_write of the flat string's byte payload.
    private static func emitPrintBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        newline: Bool,
        fd: Int32 = 1
    ) {
        // s == 0 → no-op for now (native prints "null"; M2 will match).
        code.localGet(0)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // iovec = { data, byteCount } — stores pop [addr, val].
        code.i32Const(Int32(L.iovecAddress))
        emitLoadAt(&code, baseLocal: 0, byteOffset: 0)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Store()
        code.i32Const(Int32(L.iovecAddress + 4))
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Store()
        emitFDWrite(&code, ctx: ctx, fd: fd)
        if newline {
            code.i32Const(Int32(L.iovecAddress))
            code.i32Const(Int32(L.newlineAddress))
            code.i32Store()
            code.i32Const(Int32(L.iovecAddress + 4))
            code.i32Const(1)
            code.i32Store()
            emitFDWrite(&code, ctx: ctx, fd: fd)
        }
        code.i64Const(0)
    }

    private static func emitStringLengthBody(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: 8)
    }

    /// `string, index -> i64`: UTF-8 byte widened to a code unit (ASCII-exact;
    /// UTF-16 surrogate handling is a later milestone).
    private static func emitStringGetBody(_ code: inout WasmCode) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: 0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(1)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Load8U()
        code.i64ExtendFromComparison()
    }

    /// Pushes a reference to a compile-time-known string literal, materialized
    /// through `__kk_string_literal_from_utf8`.
    private static func emitLiteralString(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        _ string: String
    ) {
        let offset = ctx.dataOffset(for: Array(string.utf8))
        code.i64Const(offset)
        code.i64Const(Int64(Array(string.utf8).count))
        code.call(ctx.emittedHelperIndex(for: "__kk_string_literal_from_utf8", argumentCount: 2))
    }

    /// `a, b -> i64`: flat-string concatenation. Null operands pass through
    /// unchanged (Kotlin `"x" + null` rendering is a later-stdlib concern).
    /// locals: 2=newData, 3=i, 4=ba, 5=bb, 6=obj — params a=0, b=1.
    private static func emitConcatFlatBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.localGet(1)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(1)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.localGet(0)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(4)
        emitLoadAt(&code, baseLocal: 1, byteOffset: 16)
        code.localSet(5)
        code.localGet(4)
        code.localGet(5)
        code.op(WasmOpcode.i64Add)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        // Copy a's bytes.
        code.i64Const(0)
        code.localSet(3)
        code.openBlock()
        code.openLoop()
        code.localGet(3)
        code.localGet(4)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Load8U()
        code.i32Store8()
        code.localGet(3)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(3)
        code.br(0)
        code.end()
        code.end()
        // Copy b's bytes after a's.
        code.i64Const(0)
        code.localSet(3)
        code.openBlock()
        code.openLoop()
        code.localGet(3)
        code.localGet(5)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(4)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        emitLoadAt(&code, baseLocal: 1, byteOffset: 0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Load8U()
        code.i32Store8()
        code.localGet(3)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(3)
        code.br(0)
        code.end()
        code.end()
        // Build the flat String object {data, length, byteCount, hash}.
        code.i64Const(48)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(6)
        emitStoreAtConst(&code, baseLocal: 6, byteOffset: L.typeIDOffset, value: L.stringTypeID)
        emitStoreAt(&code, baseLocal: 6, byteOffset: 0, valueLocal: 2)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 8)
        emitLoadAt(&code, baseLocal: 1, byteOffset: 8)
        code.op(WasmOpcode.i64Add)
        code.localSet(3)
        emitStoreAt(&code, baseLocal: 6, byteOffset: 8, valueLocal: 3)
        code.localGet(4)
        code.localGet(5)
        code.op(WasmOpcode.i64Add)
        code.localSet(3)
        emitStoreAt(&code, baseLocal: 6, byteOffset: 16, valueLocal: 3)
        emitStoreAtConst(&code, baseLocal: 6, byteOffset: 24, value: 0)
        code.localGet(6)
    }

    /// `(a, b) -> 1|0`: structural flat-string equality. Layout
    /// `{+0:data, +8:charLen, +16:byteLen, +24:hash}` — byte length and the
    /// payload are authoritative; works for data-segment and heap strings
    /// alike (unlike `elem_eq`, which can only compare heap-resident ones).
    /// Locals: argumentCount = i, +1 = aLen, +2 = pa, +3 = pb.
    private static func emitStringEqualsFlatBody(
        _ code: inout WasmCode,
        ctx _: WasmModuleContext
    ) {
        // a == b (identity or equal raw values).
        code.localGet(0)
        code.localGet(1)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.i64Const(1)
        code.op(WasmOpcode.return)
        code.end()
        // Either side null/garbage → not equal. Both args are strings by
        // contract, so only the null sentinel needs guarding.
        code.localGet(0)
        code.i64Const(0)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(1)
        code.i64Const(0)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // byteLen compare.
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        emitLoadAt(&code, baseLocal: 1, byteOffset: 16)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // Byte loop over data pointers.
        code.i64Const(0)
        code.localSet(2)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 0)
        code.localSet(3)
        emitLoadAt(&code, baseLocal: 1, byteOffset: 0)
        code.localSet(4)
        code.openBlock()
        code.openLoop()
        code.localGet(2)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(3)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Load8U()
        code.localGet(4)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Load8U()
        code.op(WasmOpcode.i32Eq)
        code.op(WasmOpcode.i32Eqz)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(2)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(2)
        code.br(0)
        code.end()
        code.end()
        code.i64Const(1)
    }

    /// `value, tag -> i64`: `toString` for boxed scalars. Tag 3 = String
    /// (passthrough), 2 = Bool, 9 = UInt32; every other tag falls back to
    /// signed-decimal rendering of the raw i64 (Float/Double bit patterns
    /// included — full numeric formatting is a stdlib milestone).
    /// locals: 2=mag, 3=tmp, 4=size, 5=data, 6=i, 7=sign — params v=0, tag=1.
    private static func emitAnyToStringBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        // tag == 3 → the value already is the string.
        code.localGet(1)
        code.i64Const(3)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(0)
        code.op(WasmOpcode.return)
        code.end()
        // Heap string object (tag-agnostic): aligned pointers inside
        // [dataEnd, heap) carrying the string typeID are already their own
        // string — covers tag-1 dispatch of collection string elements
        // (`setOf("a","b").joinToString("+")` → "a+b", not raw addresses).
        code.localGet(0)
        code.globalGet(ctx.dataEndGlobal)
        code.op(WasmOpcode.i64GeU)
        code.localGet(0)
        code.globalGet(ctx.heapGlobal)
        code.op(WasmOpcode.i64LtU)
        code.op(WasmOpcode.i32And)
        code.openIf()
        code.localGet(0)
        code.i64Const(7)
        code.op(WasmOpcode.i64And)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset)
        code.i64Const(L.stringTypeID)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(0)
        code.op(WasmOpcode.return)
        code.end()
        code.end()
        code.end()
        // tag == 2 → "true"/"false".
        code.localGet(1)
        code.i64Const(2)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(0)
        code.i64Truthy()
        code.openIf(result: .i64)
        emitLiteralString(&code, ctx: ctx, "true")
        code.elseBranch()
        emitLiteralString(&code, ctx: ctx, "false")
        code.end()
        code.op(WasmOpcode.return)
        code.end()
        // tag == 4 → UTF-8-encode the UTF-16 code unit into a scratch
        // buffer (locals 2 = buffer, 3 = byte length), then box it.
        code.localGet(1)
        code.i64Const(4)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.i64Const(4)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        code.localGet(0)
        code.i64Const(0x80)
        code.op(WasmOpcode.i64LtU)
        code.openIf(result: .i64)
        code.i64Const(1)
        code.elseBranch()
        code.localGet(0)
        code.i64Const(0x800)
        code.op(WasmOpcode.i64LtU)
        code.openIf(result: .i64)
        code.i64Const(2)
        code.elseBranch()
        code.i64Const(3)
        code.end()
        code.end()
        code.localSet(3)
        // byte0 = len==1 ? v : len==2 ? 0xC0|v>>6 : 0xE0|v>>12
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(3)
        code.i64Const(1)
        code.op(WasmOpcode.i64Eq)
        code.openIf(result: .i64)
        code.localGet(0)
        code.elseBranch()
        code.localGet(3)
        code.i64Const(2)
        code.op(WasmOpcode.i64Eq)
        code.openIf(result: .i64)
        code.i64Const(0xC0)
        code.localGet(0)
        code.i64Const(6)
        code.op(WasmOpcode.i64ShrU)
        code.op(WasmOpcode.i64Or)
        code.elseBranch()
        code.i64Const(0xE0)
        code.localGet(0)
        code.i64Const(12)
        code.op(WasmOpcode.i64ShrU)
        code.op(WasmOpcode.i64Or)
        code.end()
        code.end()
        code.op(WasmOpcode.i32WrapI64)
        code.i32Store8()
        // byte1 (len>=2) = 0x80 | ((len==2 ? v : v>>6) & 0x3F)
        code.localGet(3)
        code.i64Const(2)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(1)
        code.op(WasmOpcode.i32Add)
        code.localGet(3)
        code.i64Const(2)
        code.op(WasmOpcode.i64Eq)
        code.openIf(result: .i64)
        code.localGet(0)
        code.elseBranch()
        code.localGet(0)
        code.i64Const(6)
        code.op(WasmOpcode.i64ShrU)
        code.end()
        code.i64Const(0x3F)
        code.op(WasmOpcode.i64And)
        code.i64Const(0x80)
        code.op(WasmOpcode.i64Or)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Store8()
        code.end()
        // byte2 (len==3) = 0x80 | (v & 0x3F)
        code.localGet(3)
        code.i64Const(3)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(2)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(2)
        code.op(WasmOpcode.i32Add)
        code.localGet(0)
        code.i64Const(0x3F)
        code.op(WasmOpcode.i64And)
        code.i64Const(0x80)
        code.op(WasmOpcode.i64Or)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Store8()
        code.end()
        code.localGet(2)
        code.localGet(3)
        code.call(ctx.emittedHelperIndex(for: "__kk_string_literal_from_utf8", argumentCount: 2))
        code.op(WasmOpcode.return)
        code.end()
        // null sentinel → "null".
        code.localGet(0)
        code.i64Const(L.nullSentinel)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        emitLiteralString(&code, ctx: ctx, "null")
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(0)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        emitLiteralString(&code, ctx: ctx, "0")
        code.op(WasmOpcode.return)
        code.end()
        // tag == 9 → zero-extend the low UInt32 before rendering.
        code.localGet(1)
        code.i64Const(9)
        code.op(WasmOpcode.i64Eq)
        code.openIf()
        code.localGet(0)
        code.i64Const(0xFFFF_FFFF)
        code.op(WasmOpcode.i64And)
        code.localSet(0)
        code.end()
        // sign + magnitude (magnitude uses unsigned math so Int64.min is fine).
        code.localGet(0)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.i64ExtendFromComparison()
        code.localSet(7)
        code.localGet(7)
        code.i64Truthy()
        code.openIf()
        code.i64Const(0)
        code.localGet(0)
        code.op(WasmOpcode.i64Sub)
        code.localSet(2)
        code.elseBranch()
        code.localGet(0)
        code.localSet(2)
        code.end()
        // n = digit count.
        code.localGet(2)
        code.localSet(3)
        code.i64Const(0)
        code.localSet(4)
        code.openBlock()
        code.openLoop()
        code.localGet(3)
        code.op(WasmOpcode.i64Eqz)
        code.brIf(1)
        code.localGet(4)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(4)
        code.localGet(3)
        code.i64Const(10)
        code.op(WasmOpcode.i64DivU)
        code.localSet(3)
        code.br(0)
        code.end()
        code.end()
        // size = n + sign; data = alloc(size).
        code.localGet(4)
        code.localGet(7)
        code.op(WasmOpcode.i64Add)
        code.localSet(4)
        code.localGet(4)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(5)
        // Write digits back-to-front.
        code.localGet(4)
        code.localSet(6)
        code.openBlock()
        code.openLoop()
        code.localGet(2)
        code.op(WasmOpcode.i64Eqz)
        code.brIf(1)
        code.localGet(6)
        code.i64Const(1)
        code.op(WasmOpcode.i64Sub)
        code.localSet(6)
        code.localGet(5)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(6)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.i64Const(10)
        code.op(WasmOpcode.i64RemU)
        code.i64Const(48)
        code.op(WasmOpcode.i64Add)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Store8()
        code.localGet(2)
        code.i64Const(10)
        code.op(WasmOpcode.i64DivU)
        code.localSet(2)
        code.br(0)
        code.end()
        code.end()
        code.localGet(7)
        code.i64Truthy()
        code.openIf()
        code.localGet(5)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(0x2D) // '-'
        code.i32Store8()
        code.end()
        code.localGet(5)
        code.localGet(4)
        code.call(ctx.emittedHelperIndex(for: "__kk_string_literal_from_utf8", argumentCount: 2))
    }

    // MARK: - List helpers

    /// Allocates the list box `object_new(3, typeID)` and fills
    /// slot2=backing array, slot3=count, slot4=flags (bit0 = read-only).
    /// The object's local index is `objectLocal`; `countLocal == nil` stores 0.
    private static func emitListBoxBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        typeID: Int64,
        readOnly: Bool,
        arrayLocal: Int,
        countLocal: Int?,
        objectLocal: Int,
        listItables: Bool = true
    ) {
        // Slots 0/1 are object metadata; slots 2/3/4 hold array, count, flags.
        code.i64Const(5)
        code.i64Const(typeID)
        code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
        code.localSet(objectLocal)
        emitStoreAt(&code, baseLocal: objectLocal, byteOffset: L.listArrayOffset, valueLocal: arrayLocal)
        if let countLocal {
            emitStoreAt(&code, baseLocal: objectLocal, byteOffset: L.listCountOffset, valueLocal: countLocal)
        } else {
            emitStoreAtConst(&code, baseLocal: objectLocal, byteOffset: L.listCountOffset, value: 0)
        }
        emitStoreAtConst(
            &code, baseLocal: objectLocal, byteOffset: L.listFlagsOffset,
            value: readOnly ? 1 : 0
        )
        // Iterable(0)/Sequence(1)/MutableIterable(2) all iterate through the
        // shared list-layout iterator — mirrors the native
        // `maybeRegisterCollectionIterableItable` table so interface-typed
        // receivers (`MutableSet.iterator()`, `Iterable.for`) dispatch here.
        emitIterableItableRegistration(&code, ctx: ctx, objectLocal: objectLocal)
        if listItables {
            emitListItableRegistrations(&code, ctx: ctx, objectLocal: objectLocal)
        }
    }

    /// Registers the `kotlin.collections.List` (iface slot 3) and
    /// `kotlin.collections.MutableList` (iface slot 4) itables on a list box.
    /// Method slots follow the pinned source-dispatch table in
    /// `LayoutSynthesis.orderedOwnMethods` — unregistered slots stay 0 so a
    /// miss traps at the call site rather than misdispatching.
    private static func emitListItableRegistrations(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        objectLocal: Int
    ) {
        let regIface = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_iface", argumentCount: 3
        )
        let regMethod = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_method", argumentCount: 4
        )
        func reg(_ fqName: String, slot: Int64) {
            code.localGet(objectLocal)
            code.i64Const(stableNominalTypeID(fqName))
            code.i64Const(slot)
            code.call(regIface)
            code.op(WasmOpcode.drop)
        }
        func method(_ slot: Int64, _ methodSlot: Int64, _ helper: String, arity: Int) {
            code.localGet(objectLocal)
            code.i64Const(slot)
            code.i64Const(methodSlot)
            code.i64Const(Int64(ctx.module.tableSlot(
                forFunction: ctx.emittedHelperIndex(for: helper, argumentCount: arity)
            )))
            code.call(regMethod)
            code.op(WasmOpcode.drop)
        }
        reg("kotlin.collections.List", slot: 3)
        method(3, 0, "__kk_list_get", arity: 2)
        method(3, 3, "kk_list_iterator", arity: 1)
        method(3, 4, "__kk_list_is_empty", arity: 1)
        method(3, 5, "kk_list_iterator", arity: 1)
        method(3, 6, "__kk_list_index_of", arity: 2)
        method(3, 7, "__kk_list_last_index_of", arity: 2)
        // size getter slot = vtableSize (9) + 0 per kirInterfacePropertyGetterSlots.
        method(3, 9, "__kk_list_size", arity: 1)
        reg("kotlin.collections.MutableList", slot: 4)
        method(4, 2, "__kk_mutable_list_add", arity: 2)
    }

    /// Registers `iterator()` (method slot 0) under `kotlin.collections.Iterable`
    /// slot 0, `kotlin.sequences.Sequence` slot 1, and
    /// `kotlin.collections.MutableIterable` slot 2 — all pointing at
    /// `kk_list_iterator`, which understands the shared box layout.
    private static func emitIterableItableRegistration(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        objectLocal: Int
    ) {
        let regIface = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_iface", argumentCount: 3
        )
        let regMethod = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_method", argumentCount: 4
        )
        let iteratorSlot = Int64(ctx.module.tableSlot(
            forFunction: ctx.emittedHelperIndex(for: "kk_list_iterator", argumentCount: 1)
        ))
        for (fqName, ifaceSlot) in [
            ("kotlin.collections.Iterable", Int64(0)),
            ("kotlin.sequences.Sequence", Int64(1)),
            ("kotlin.collections.MutableIterable", Int64(2)),
        ] {
            code.localGet(objectLocal)
            code.i64Const(stableNominalTypeID(fqName))
            code.i64Const(ifaceSlot)
            code.call(regIface)
            code.op(WasmOpcode.drop)
            code.localGet(objectLocal)
            code.i64Const(ifaceSlot)
            code.i64Const(0)
            code.i64Const(iteratorSlot)
            code.call(regMethod)
            code.op(WasmOpcode.drop)
        }
    }

    /// `(list, index) -> elem`: bounds-check against the count slot, then load
    /// the element out of the backing array. OOB marks the thrown channel.
    /// Locals: argumentCount = count, argumentCount+1 = array.
    private static func emitListGetBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localSet(argumentCount)
        code.localGet(1)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.localGet(1)
        code.localGet(argumentCount)
        code.op(WasmOpcode.i64GeS)
        code.op(WasmOpcode.i32Or)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.localSet(argumentCount + 1)
        code.localGet(argumentCount + 1)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(1)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
    }

    /// `(list, elem) -> bool`: append with backing-array growth (capacity is
    /// the array's meta slot; count lives on the list). Read-only lists throw.
    /// Locals: argumentCount = count, +1 = array, +2 = capacity, +3 = newArr,
    /// +4 = copy index.
    private static func emitMutableListAddBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let countLocal = argumentCount
        let arrLocal = argumentCount + 1
        let capLocal = argumentCount + 2
        let newArrLocal = argumentCount + 3
        let iLocal = argumentCount + 4
        // Read-only flag lives in bit0 of slot4.
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listFlagsOffset)
        code.i64Const(1)
        code.op(WasmOpcode.i64And)
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localSet(countLocal)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.localSet(arrLocal)
        emitLoadAt(&code, baseLocal: arrLocal, byteOffset: L.metaOffset)
        code.localSet(capLocal)
        // Grow when full: newCapacity = cap*2, or 8 when empty.
        code.localGet(countLocal)
        code.localGet(capLocal)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        code.localGet(capLocal)
        code.i64Const(2)
        code.op(WasmOpcode.i64Mul)
        code.localGet(capLocal)
        code.op(WasmOpcode.i64Eqz)
        code.i64ExtendFromComparison()
        code.i64Const(8)
        code.op(WasmOpcode.i64Mul)
        code.op(WasmOpcode.i64Add)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(newArrLocal)
        code.i64Const(0)
        code.localSet(iLocal)
        code.openBlock()
        code.openLoop()
        code.localGet(iLocal)
        code.localGet(countLocal)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(newArrLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(arrLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.i64Store(offset: 0)
        code.localGet(iLocal)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iLocal)
        code.br(0)
        code.end()
        code.end()
        code.localGet(newArrLocal)
        code.localSet(arrLocal)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset, valueLocal: newArrLocal)
        code.end()
        // arr[count] = elem; count += 1.
        code.localGet(arrLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(countLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(1)
        code.i64Store(offset: 0)
        code.localGet(countLocal)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(countLocal)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.listCountOffset, valueLocal: countLocal)
        code.i64Const(1)
    }

    /// `(list) -> List`: snapshot copy — new backing array with capacity =
    /// count so later appends can't mutate the view.
    /// Locals: argumentCount = count, +1 = srcArr, +2 = newArr, +3 = i, +4 = obj.
    private static func emitListToListBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let countLocal = argumentCount
        let srcArrLocal = argumentCount + 1
        let newArrLocal = argumentCount + 2
        let iLocal = argumentCount + 3
        let objLocal = argumentCount + 4
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localSet(countLocal)
        code.localGet(countLocal)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(newArrLocal)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.localSet(srcArrLocal)
        code.i64Const(0)
        code.localSet(iLocal)
        code.openBlock()
        code.openLoop()
        code.localGet(iLocal)
        code.localGet(countLocal)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(newArrLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(srcArrLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.i64Store(offset: 0)
        code.localGet(iLocal)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iLocal)
        code.br(0)
        code.end()
        code.end()
        emitListBoxBody(
            &code, ctx: ctx,
            typeID: L.listTypeID, readOnly: true,
            arrayLocal: newArrLocal, countLocal: countLocal, objectLocal: objLocal
        )
        code.localGet(objLocal)
    }

    /// `(iterator) -> elem`: ConcurrentModificationException when the backing
    /// count drifted, NoSuchElementException when exhausted (both thrown
    /// markers for now).
    /// Locals: argumentCount = list, +1 = count, +2 = index.
    private static func emitListIteratorNextBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let listLocal = argumentCount
        let countLocal = argumentCount + 1
        let indexLocal = argumentCount + 2
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.localSet(listLocal)
        emitLoadAt(&code, baseLocal: listLocal, byteOffset: L.listCountOffset)
        code.localSet(countLocal)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listFlagsOffset)
        code.localGet(countLocal)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localTee(indexLocal)
        code.localGet(countLocal)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // elem = list.backing[index]; index += 1.
        emitLoadAt(&code, baseLocal: listLocal, byteOffset: L.listArrayOffset)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(indexLocal)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        emitAddress(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localGet(indexLocal)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.i64Store(offset: 0)
    }

    // MARK: - Pair / Set / Map helpers

    /// `(a, b) -> i64`: value equality for collection storage. Raw i64s compare
    /// by value; two distinct heap pointers fall back to structural comparison
    /// (currently only strings). Mirrors `kk_op_eq`'s boxed path.
    /// Locals: argumentCount = isHeap(a), +1 = isHeap(b), +2 = aLen, +3 = i,
    /// +4 = pa (scratch).
    private static func emitElemEqBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        let aHeap = 2, bHeap = 3, lenL = 4, iL = 5, paL = 6
        // a == b (bitwise): covers identical pointers and equal raw values.
        code.localGet(0)
        code.localGet(1)
        code.op(WasmOpcode.i64Eq)
        code.openIf(result: .i64)
        code.i64Const(1)
        code.elseBranch()
        // isObjectPointer(x) = dataStart <= x < heap — covers data-segment
        // strings (literals) and heap objects alike; raw i64 values are
        // always < dataStart so they can never reach the byte compare.
        // Flags are stored extended to i64 because all locals are i64.
        code.i64Const(L.dataStart)
        code.localGet(0)
        code.op(WasmOpcode.i64LeU)
        code.globalGet(ctx.heapGlobal)
        code.localGet(0)
        code.op(WasmOpcode.i64GtU)
        code.op(WasmOpcode.i32And)
        code.i64ExtendFromComparison()
        code.localSet(aHeap)
        code.i64Const(L.dataStart)
        code.localGet(1)
        code.op(WasmOpcode.i64LeU)
        code.globalGet(ctx.heapGlobal)
        code.localGet(1)
        code.op(WasmOpcode.i64GtU)
        code.op(WasmOpcode.i32And)
        code.i64ExtendFromComparison()
        code.localSet(bHeap)
        // Both must be heap objects with stringTypeID to compare structurally.
        // bHeap is repurposed as the both-strings flag; the else arm clears it
        // so a non-heap operand can never fall through into the byte compare.
        code.localGet(aHeap)
        code.localGet(bHeap)
        code.op(WasmOpcode.i64And)
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset)
        code.localSet(paL)
        emitLoadAt(&code, baseLocal: 1, byteOffset: L.typeIDOffset)
        code.localGet(paL)
        code.op(WasmOpcode.i64Eq)
        code.localGet(paL)
        code.i64Const(L.stringTypeID)
        code.op(WasmOpcode.i64Eq)
        code.op(WasmOpcode.i32And)
        code.i64ExtendFromComparison()
        code.localSet(bHeap)
        code.elseBranch()
        code.i64Const(0)
        code.localSet(bHeap)
        code.end()
        // If both are strings: compare byte length then bytes. Offset +16 is
        // the payload byte count (+8 is the character count — bounding the
        // loop by chars would under-read multi-byte UTF-8).
        code.localGet(bHeap)
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        emitLoadAt(&code, baseLocal: 0, byteOffset: 16)
        code.localSet(lenL)
        emitLoadAt(&code, baseLocal: 1, byteOffset: 16)
        code.localGet(lenL)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // i = 0; pa = a.data
        code.i64Const(0)
        code.localSet(iL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: 0)
        code.localSet(paL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(lenL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        // pa[i] vs b.data[i]
        code.localGet(paL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Load8U()
        emitLoadAt(&code, baseLocal: 1, byteOffset: 0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.op(WasmOpcode.i32Add)
        code.i32Load8U()
        code.op(WasmOpcode.i32Eq)
        code.op(WasmOpcode.i32Eqz)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.i64Const(1)
        code.op(WasmOpcode.return)
        code.end()
        // Different kinds / non-strings / non-heap: not equal.
        code.i64Const(0)
        code.end()
    }

    /// `(first, second) -> Pair box` (slot2=first, slot3=second, mapRef=0).
    /// Locals: argumentCount = pair object.
    private static func emitPairNewBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        code.i64Const(6)
        code.i64Const(stableNominalTypeID("kotlin.Pair"))
        code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
        code.localSet(argumentCount)
        emitStoreAt(&code, baseLocal: argumentCount, byteOffset: L.pairFirstOffset, valueLocal: 0)
        emitStoreAt(&code, baseLocal: argumentCount, byteOffset: L.pairSecondOffset, valueLocal: 1)
        emitStoreAtConst(&code, baseLocal: argumentCount, byteOffset: L.pairMapRefOffset, value: 0)
        emitStoreAtConst(&code, baseLocal: argumentCount, byteOffset: L.pairMapKeyOffset, value: 0)
        code.localGet(argumentCount)
    }

    /// The nominal type-ID the set box should carry for a given factory name.
    private static func setTypeID(for name: String) -> Int64 {
        switch name {
        case "__kk_hash_set_of", "__kk_hash_set_new_checked":
            return stableNominalTypeID("kotlin.collections.HashSet")
        case "__kk_linked_hash_set_of":
            return stableNominalTypeID("kotlin.collections.LinkedHashSet")
        default:
            return stableNominalTypeID("kotlin.collections.Set")
        }
    }

    private static func mapTypeID(for name: String) -> Int64 {
        switch name {
        case "__kk_hash_map_of", "__kk_hash_map_of_pairs":
            return stableNominalTypeID("kotlin.collections.HashMap")
        case "__kk_linked_hash_map_of", "__kk_linked_hash_map_of_pairs":
            return stableNominalTypeID("kotlin.collections.LinkedHashMap")
        default:
            return stableNominalTypeID("kotlin.collections.Map")
        }
    }

    /// Emits `kk_type_register_super(child, parent)` for every edge and the
    /// per-object itable registrations needed for dynamic dispatch on Set/Map
    /// and their iterators. Mirrors the native registration tables in
    /// `RuntimeCollectionHelpers+Iterators.swift`.
    private static func emitCollectionItableRegistrations(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        objectLocal: Int,
        set: Bool,
        entry: Bool
    ) {
        let regIface = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_iface", argumentCount: 3
        )
        let regMethod = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_method", argumentCount: 4
        )
        func reg(_ fqName: String, slot: Int64) {
            code.localGet(objectLocal)
            code.i64Const(stableNominalTypeID(fqName))
            code.i64Const(slot)
            code.call(regIface)
            code.op(WasmOpcode.drop)
        }
        func method(_ slot: Int64, _ methodSlot: Int64, _ helper: String, arity: Int) {
            code.localGet(objectLocal)
            code.i64Const(slot)
            code.i64Const(methodSlot)
            code.i64Const(Int64(ctx.module.tableSlot(
                forFunction: ctx.emittedHelperIndex(for: helper, argumentCount: arity)
            )))
            code.call(regMethod)
            code.op(WasmOpcode.drop)
        }
        if set {
            // Iterable(0)/Sequence(1)/MutableIterable(2) come from
            // `emitListBoxBody` — set boxes share that allocation path.
            // Collection.ifaceSlot=3, m4=size; Set.ifaceSlot=4, m1=contains,
            // m3=size (slot numbering per the native registration table).
            reg("kotlin.collections.Collection", slot: 3)
            method(3, 4, "__kk_set_size", arity: 1)
            reg("kotlin.collections.Set", slot: 4)
            method(4, 1, "__kk_set_contains", arity: 2)
            method(4, 3, "__kk_set_size", arity: 1)
        }
        if entry {
            // Map.Entry.ifaceSlot=0, m0=key, m1=value — the pair getters serve
            // as the accessors (mapRef/mapKey make `second` a live map view).
            reg("kotlin.collections.Map.Entry", slot: 0)
            method(0, 0, "__kk_pair_first", arity: 1)
            method(0, 1, "__kk_pair_second", arity: 1)
            // MutableMap.MutableEntry.ifaceSlot=1, m0=setValue.
            reg("kotlin.collections.MutableMap.MutableEntry", slot: 1)
            method(1, 0, "__kk_mutable_map_entry_setValue", arity: 2)
        }
    }

    /// Type-edge registrations mirroring the native runtime's `is`-assignable
    /// DAG for collection tags.
    private static func emitCollectionTypeEdges(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        edges: [(String, String)]
    ) {
        let edgeHelper = ctx.emittedHelperIndex(
            for: "kk_type_register_super", argumentCount: 2
        )
        for (child, parent) in edges {
            code.i64Const(stableNominalTypeID(child))
            code.i64Const(stableNominalTypeID(parent))
            code.call(edgeHelper)
            code.op(WasmOpcode.drop)
        }
    }

    /// `(array, count) -> Set box`: dedups the packed array into fresh backing
    /// storage, then wraps it in a list-layout box carrying the set's type ID
    /// and itables.
    /// Locals: argumentCount = uniqArr, +1 = uniqCount, +2 = i, +3 = elem,
    /// +4 = dupScan index, +5 = found flag, +6 = box.
    private static func emitSetOfBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        name: String,
        argumentCount: Int
    ) {
        let uniqArr = argumentCount, uniqCount = argumentCount + 1
        let iL = argumentCount + 2, elemL = argumentCount + 3
        let jL = argumentCount + 4, foundL = argumentCount + 5, boxL = argumentCount + 6
        emitCollectionTypeEdges(&code, ctx: ctx, edges: [
            ("kotlin.collections.MutableCollection", "kotlin.collections.Collection"),
            ("kotlin.collections.Collection", "kotlin.collections.Iterable"),
            ("kotlin.collections.MutableSet", "kotlin.collections.MutableCollection"),
            ("kotlin.collections.MutableSet", "kotlin.collections.Set"),
            ("kotlin.collections.Set", "kotlin.collections.Collection"),
            ("kotlin.collections.AbstractMutableSet", "kotlin.collections.MutableSet"),
            ("kotlin.collections.HashSet", "kotlin.collections.AbstractMutableSet"),
            ("kotlin.collections.HashSet", "kotlin.collections.MutableSet"),
            ("kotlin.collections.HashSet", "kotlin.collections.Set"),
            ("kotlin.collections.LinkedHashSet", "kotlin.collections.HashSet"),
            ("kotlin.collections.LinkedHashSet", "kotlin.collections.MutableSet"),
            ("kotlin.collections.LinkedHashSet", "kotlin.collections.Set"),
        ])
        // uniqArr = kk_array_new(count); dedup src into it.
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(uniqArr)
        code.i64Const(0)
        code.localSet(uniqCount)
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(1)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        // elem = src[i]
        code.localGet(0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localSet(elemL)
        // Scan uniqArr[0..uniqCount) for a duplicate.
        code.i64Const(0)
        code.localSet(jL)
        code.i64Const(0)
        code.localSet(foundL)
        code.openBlock()
        code.openLoop()
        code.localGet(jL)
        code.localGet(uniqCount)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(uniqArr)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(jL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localGet(elemL)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.localSet(foundL)
        code.br(2) // out of the scan loop
        code.end()
        code.localGet(jL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(jL)
        code.br(0)
        code.end()
        code.end()
        // If not found: append.
        code.localGet(foundL)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.localGet(uniqArr)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(uniqCount)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(elemL)
        code.i64Store(offset: 0)
        code.localGet(uniqCount)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(uniqCount)
        code.end()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        emitListBoxBody(
            &code, ctx: ctx,
            typeID: setTypeID(for: name), readOnly: false,
            arrayLocal: uniqArr, countLocal: uniqCount, objectLocal: boxL,
            listItables: false
        )
        emitCollectionItableRegistrations(&code, ctx: ctx, objectLocal: boxL, set: true, entry: false)
        code.localGet(boxL)
    }

    /// `(set, elem) -> i64`: linear contains via `__kk_wasm_elem_eq`.
    /// Locals: argumentCount = i.
    private static func emitSetContainsBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let iL = argumentCount
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localSet(iL + 1)
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(iL + 1)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.i64Const(0)
    }

    /// `(set, elem) -> i64`: dedup check + append/grow, mirroring the mutable
    /// list add path. Returns 1 when the element was newly inserted.
    /// Locals: argumentCount = count, +1 = arr, +2 = cap, +3 = i (scan),
    /// +4 = dup flag, +5 = newArr.
    private static func emitMutableSetAddBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let countL = argumentCount, arrL = argumentCount + 1, capL = argumentCount + 2
        let iL = argumentCount + 3, dupL = argumentCount + 4, newArrL = argumentCount + 5
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localSet(countL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.localSet(arrL)
        // Dedup scan: contains(elem) → return 0.
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(arrL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.localSet(dupL)
        code.end()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.localGet(dupL)
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // Grow when full (same policy as mutable list add).
        emitLoadAt(&code, baseLocal: arrL, byteOffset: L.metaOffset)
        code.localSet(capL)
        code.localGet(countL)
        code.localGet(capL)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        code.localGet(capL)
        code.i64Const(2)
        code.op(WasmOpcode.i64Mul)
        code.localGet(capL)
        code.op(WasmOpcode.i64Eqz)
        code.i64ExtendFromComparison()
        code.i64Const(8)
        code.op(WasmOpcode.i64Mul)
        code.op(WasmOpcode.i64Add)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(newArrL)
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(newArrL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(arrL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.i64Store(offset: 0)
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.localGet(newArrL)
        code.localSet(arrL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset, valueLocal: newArrL)
        code.end()
        // arr[count] = elem; count++.
        code.localGet(arrL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(countL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(1)
        code.i64Store(offset: 0)
        code.localGet(countL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(countL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.listCountOffset, valueLocal: countL)
        code.i64Const(1)
    }

    /// `(set, elem) -> i64`: shift-remove on a hit, 0 otherwise.
    /// Locals: argumentCount = count, +1 = arr, +2 = i, +3 = j, +4 = matched.
    private static func emitMutableSetRemoveBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let countL = argumentCount, arrL = argumentCount + 1
        let iL = argumentCount + 2, jL = argumentCount + 3, hitL = argumentCount + 4
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localSet(countL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.localSet(arrL)
        code.i64Const(0)
        code.localSet(iL)
        code.i64Const(0)
        code.localSet(hitL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(arrL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.localSet(hitL)
        // Shift tail left: for j in i..<count-1 { arr[j] = arr[j+1] }
        code.localGet(iL)
        code.localSet(jL)
        code.openBlock()
        code.openLoop()
        code.localGet(jL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(arrL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(jL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(arrL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(jL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.i64Store(offset: 0)
        code.localGet(jL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(jL)
        code.br(0)
        code.end()
        code.end()
        code.localGet(countL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Sub)
        code.localSet(countL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.listCountOffset, valueLocal: countL)
        code.br(2) // break out of the scan loop's enclosing block
        code.end()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.localGet(hitL)
    }

    /// Emits the map-box slot stores `{keys, values, count, flags}` into the
    /// object in `objectLocal`. `keys`/`values` are adopted directly.
    private static func emitMapBoxBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        typeID: Int64,
        readOnly: Bool,
        keysLocal: Int,
        valuesLocal: Int,
        countLocal: Int?,
        objectLocal: Int
    ) {
        code.i64Const(6)
        code.i64Const(typeID)
        code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
        code.localSet(objectLocal)
        emitStoreAt(&code, baseLocal: objectLocal, byteOffset: L.mapKeysOffset, valueLocal: keysLocal)
        emitStoreAt(&code, baseLocal: objectLocal, byteOffset: L.mapValuesOffset, valueLocal: valuesLocal)
        if let countLocal {
            emitStoreAt(&code, baseLocal: objectLocal, byteOffset: L.mapCountOffset, valueLocal: countLocal)
        } else {
            emitStoreAtConst(&code, baseLocal: objectLocal, byteOffset: L.mapCountOffset, value: 0)
        }
        emitStoreAtConst(
            &code, baseLocal: objectLocal, byteOffset: L.mapFlagsOffset,
            value: readOnly ? 1 : 0
        )
        emitMapItableRegistrations(&code, ctx: ctx, objectLocal: objectLocal)
    }

    /// Registers the `Map`/`MutableMap` itables on a runtime map box so
    /// interface-typed receivers (`m.entries` on a `MutableMap<K,V>`-typed
    /// value dispatches `itableDynamic[MutableMap:getterSlot]`) resolve to
    /// the runtime helpers instead of missing the table and calling an
    /// arbitrary funcref. Method slots follow the bundled declaration order
    /// (functions in declaration order, then property getters sorted by
    /// name starting at vtableSize) — the same numbering the frontend's
    /// `itableDynamic` emission computes.
    ///   Map:          isEmpty=0 get=1 containsKey=2 containsValue=3,
    ///                 getters entries=4 keys=5 size=6 values=7
    ///   MutableMap:   put=0 putAll=1 remove=2 clear=3 asJsMapView=4(no impl),
    ///                 getters entries=5 keys=6 values=7
    private static func emitMapItableRegistrations(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        objectLocal: Int
    ) {
        let regIface = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_iface", argumentCount: 3
        )
        let regMethod = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_method", argumentCount: 4
        )
        func reg(_ fqName: String, slot: Int64) {
            code.localGet(objectLocal)
            code.i64Const(stableNominalTypeID(fqName))
            code.i64Const(slot)
            code.call(regIface)
            code.op(WasmOpcode.drop)
        }
        func method(_ slot: Int64, _ methodSlot: Int64, _ helper: String, arity: Int) {
            code.localGet(objectLocal)
            code.i64Const(slot)
            code.i64Const(methodSlot)
            code.i64Const(Int64(ctx.module.tableSlot(
                forFunction: ctx.emittedHelperIndex(for: helper, argumentCount: arity)
            )))
            code.call(regMethod)
            code.op(WasmOpcode.drop)
        }
        reg("kotlin.collections.Map", slot: 0)
        method(0, 0, "__kk_map_is_empty", arity: 1)
        method(0, 1, "__kk_map_get", arity: 2)
        method(0, 2, "__kk_map_contains_key", arity: 2)
        method(0, 3, "__kk_map_contains_value", arity: 2)
        method(0, 4, "__kk_map_entries", arity: 1)
        method(0, 5, "__kk_map_keys", arity: 1)
        method(0, 6, "__kk_map_size", arity: 1)
        method(0, 7, "__kk_map_values", arity: 1)
        reg("kotlin.collections.MutableMap", slot: 1)
        method(1, 0, "__kk_mutable_map_put", arity: 3)
        method(1, 1, "__kk_mutable_map_putAll", arity: 2)
        method(1, 2, "__kk_mutable_map_remove", arity: 2)
        method(1, 3, "__kk_mutable_map_clear", arity: 1)
        // slot 4 (asJsMapView) is JS-only — left unregistered; the null
        // funcref guard at the call site traps instead of misdispatching.
        method(1, 5, "__kk_map_entries", arity: 1)
        method(1, 6, "__kk_map_keys", arity: 1)
        method(1, 7, "__kk_map_values", arity: 1)
    }

    /// `(keys, values, count) -> Map box`. `__kk_emptyMap` (arity 0) builds an
    /// empty read-only map; the `_of` factories adopt their packed arrays
    /// (a `0`/null slot becomes a fresh empty array).
    /// Locals: argumentCount = keysArr, +1 = valuesArr, +2 = box.
    private static func emitMapOfBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        name: String,
        argumentCount: Int
    ) {
        let keysL = argumentCount, valuesL = argumentCount + 1, boxL = argumentCount + 2
        emitCollectionTypeEdges(&code, ctx: ctx, edges: [
            ("kotlin.collections.MutableMap", "kotlin.collections.Map"),
            ("kotlin.collections.AbstractMutableMap", "kotlin.collections.MutableMap"),
            ("kotlin.collections.HashMap", "kotlin.collections.MutableMap"),
            ("kotlin.collections.HashMap", "kotlin.collections.AbstractMutableMap"),
            ("kotlin.collections.LinkedHashMap", "kotlin.collections.HashMap"),
            ("kotlin.collections.LinkedHashMap", "kotlin.collections.MutableMap"),
            ("kotlin.collections.MutableMap.MutableEntry", "kotlin.collections.Map.Entry"),
        ])
        let readOnly = name == "__kk_map_of" || name == "__kk_emptyMap"
        let arrNew = ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1)
        for (param, target) in [(0, keysL), (1, valuesL)] {
            if argumentCount >= 3 {
                code.localGet(param)
                code.i64Const(0)
                code.op(WasmOpcode.i64Ne)
                code.openIf(result: .i64)
                code.localGet(param)
                code.elseBranch()
                code.i64Const(0)
                code.call(arrNew)
                code.end()
                code.localSet(target)
            } else {
                code.i64Const(0)
                code.call(arrNew)
                code.localSet(target)
            }
        }
        emitMapBoxBody(
            &code, ctx: ctx,
            typeID: mapTypeID(for: name), readOnly: readOnly,
            keysLocal: keysL,
            valuesLocal: valuesL,
            countLocal: argumentCount >= 3 ? 2 : nil,
            objectLocal: boxL
        )
        code.localGet(boxL)
    }

    /// `(pairs, count) -> Map box`: unpacks `Pair` elements into parallel
    /// keys/values arrays, then delegates to the plain factory's boxing.
    /// Locals: argumentCount = keys, +1 = values, +2 = i, +3 = pair, +4 = box.
    private static func emitMapOfPairsBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        name: String,
        argumentCount: Int
    ) {
        let keysL = argumentCount, valuesL = argumentCount + 1
        let iL = argumentCount + 2, pairL = argumentCount + 3, boxL = argumentCount + 4
        let arrNew = ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1)
        code.localGet(1)
        code.call(arrNew)
        code.localSet(keysL)
        code.localGet(1)
        code.call(arrNew)
        code.localSet(valuesL)
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(1)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        // pair = pairs[i]
        code.localGet(0)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localSet(pairL)
        // keys[i] = pair.first
        code.localGet(keysL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        emitLoadAt(&code, baseLocal: pairL, byteOffset: L.pairFirstOffset)
        code.i64Store(offset: 0)
        // values[i] = pair.second
        code.localGet(valuesL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        emitLoadAt(&code, baseLocal: pairL, byteOffset: L.pairSecondOffset)
        code.i64Store(offset: 0)
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        emitCollectionTypeEdges(&code, ctx: ctx, edges: [
            ("kotlin.collections.MutableMap", "kotlin.collections.Map"),
            ("kotlin.collections.AbstractMutableMap", "kotlin.collections.MutableMap"),
            ("kotlin.collections.HashMap", "kotlin.collections.MutableMap"),
            ("kotlin.collections.HashMap", "kotlin.collections.AbstractMutableMap"),
            ("kotlin.collections.LinkedHashMap", "kotlin.collections.HashMap"),
            ("kotlin.collections.LinkedHashMap", "kotlin.collections.MutableMap"),
            ("kotlin.collections.MutableMap.MutableEntry", "kotlin.collections.Map.Entry"),
        ])
        emitMapBoxBody(
            &code, ctx: ctx,
            typeID: mapTypeID(for: name), readOnly: name == "__kk_map_of_pairs",
            keysLocal: keysL, valuesLocal: valuesL,
            countLocal: 1, objectLocal: boxL
        )
        code.localGet(boxL)
    }

    /// `(map) -> map`: `map_freeze` retags the box to the read-only `Map`
    /// identity and sets the read-only flag, mirroring `runtimeMapBox.freeze`.
    private static func emitMapFreezeBody(_ code: inout WasmCode) {
        emitStoreAtConst(
            &code, baseLocal: 0, byteOffset: L.typeIDOffset,
            value: stableNominalTypeID("kotlin.collections.Map")
        )
        emitStoreAtConst(&code, baseLocal: 0, byteOffset: L.mapFlagsOffset, value: 1)
        code.localGet(0)
    }

    /// `(map, key) -> i64`: index of `key` in the keys array, or `-1`.
    /// Locals: argumentCount = keys, +1 = count, +2 = i, +3 = cur.
    private static func emitMapIndexOfBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let keysL = argumentCount, countL = argumentCount + 1
        let iL = argumentCount + 2, curL = argumentCount + 3
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapKeysOffset)
        code.localSet(keysL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
        code.localSet(countL)
        code.localGet(keysL)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(-1)
        code.op(WasmOpcode.return)
        code.end()
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(keysL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localSet(curL)
        code.localGet(curL)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.localGet(iL)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.i64Const(-1)
    }

    /// `(map, key) -> value`: linear probe over keys; miss returns the null
    /// sentinel (Kotlin `null`).
    /// Locals: argumentCount = idx.
    private static func emitMapGetBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let idxL = argumentCount
        code.localGet(0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_map_index_of", argumentCount: 2))
        code.localTee(idxL)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf()
        code.i64Const(L.nullSentinel)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapValuesOffset)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(idxL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
    }

    /// `(map, value) -> i64`: linear contains over the values array.
    /// Locals: argumentCount = vals, +1 = count, +2 = i.
    private static func emitMapContainsValueBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let valsL = argumentCount, countL = argumentCount + 1, iL = argumentCount + 2
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapValuesOffset)
        code.localSet(valsL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
        code.localSet(countL)
        code.localGet(valsL)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(valsL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_elem_eq", argumentCount: 2))
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.i64Const(0)
    }

    /// Which `Map` view `emitMapViewBody` materializes.
    private enum MapViewKind {
        /// `map.keys` — Set view over the keys array.
        case keys
        /// `map.values` — List view over the values array.
        case values
        /// `map.entries` — Set of live `MutableEntry` boxes.
        case entries
    }

    /// `(map) -> Set|List box`: snapshots the view into a fresh array and wraps
    /// it via the existing `__kk_set_of`/`__kk_list_of` factories.
    /// Locals: argumentCount = count, +1 = src, +2 = dst, +3 = i.
    private static func emitMapViewBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        view: MapViewKind,
        argumentCount: Int
    ) {
        let countL = argumentCount, srcL = argumentCount + 1
        let dstL = argumentCount + 2, iL = argumentCount + 3
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
        code.localSet(countL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapKeysOffset)
        code.localSet(srcL)
        code.localGet(countL)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(dstL)
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        code.localGet(dstL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(iL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        switch view {
        case .keys:
            code.localGet(srcL)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(iL)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.i64Load(offset: 0)
        case .values:
            emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapValuesOffset)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(iL)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.i64Load(offset: 0)
        case .entries:
            code.localGet(0)
            code.localGet(srcL)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(iL)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.i64Load(offset: 0)
            code.call(ctx.emittedHelperIndex(for: "__kk_wasm_map_entry", argumentCount: 2))
        }
        code.i64Store(offset: 0)
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.localGet(dstL)
        code.localGet(countL)
        switch view {
        case .values:
            code.call(ctx.emittedHelperIndex(for: "__kk_list_of", argumentCount: 2))
        case .keys, .entries:
            code.call(ctx.emittedHelperIndex(for: "__kk_set_of", argumentCount: 2))
        }
    }

    /// `(map, key, value) -> old value|nullSentinel`: put with growth. Read-only
    /// maps (mapOf/freeze results) mark the thrown channel.
    /// Locals: argumentCount = keys, +1 = values, +2 = count, +3 = cap,
    /// +4 = idx, +5 = i, +6 = newKeys, +7 = newValues.
    private static func emitMutableMapPutBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let keysL = argumentCount, valsL = argumentCount + 1
        let countL = argumentCount + 2, capL = argumentCount + 3
        let idxL = argumentCount + 4, iL = argumentCount + 5
        let newKeysL = argumentCount + 6, newValsL = argumentCount + 7
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapFlagsOffset)
        code.i64Const(1)
        code.op(WasmOpcode.i64And)
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // Update path: idx = indexOf(key)
        code.localGet(0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_map_index_of", argumentCount: 2))
        code.localSet(idxL)
        code.localGet(idxL)
        code.i64Const(0)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapValuesOffset)
        code.localSet(valsL)
        // old = vals[idx]; vals[idx] = v; return old
        code.localGet(valsL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(idxL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localSet(iL) // reuse iL as `old`
        code.localGet(valsL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(idxL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.i64Store(offset: 0)
        code.localGet(iL)
        code.op(WasmOpcode.return)
        code.end()
        // Insert path.
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapKeysOffset)
        code.localSet(keysL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapValuesOffset)
        code.localSet(valsL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
        code.localSet(countL)
        emitLoadAt(&code, baseLocal: keysL, byteOffset: L.metaOffset)
        code.localSet(capL)
        code.localGet(countL)
        code.localGet(capL)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        // newCap = cap*2 or 8
        code.localGet(capL)
        code.i64Const(2)
        code.op(WasmOpcode.i64Mul)
        code.localGet(capL)
        code.op(WasmOpcode.i64Eqz)
        code.i64ExtendFromComparison()
        code.i64Const(8)
        code.op(WasmOpcode.i64Mul)
        code.op(WasmOpcode.i64Add)
        code.localSet(capL)
        code.localGet(capL)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(newKeysL)
        code.localGet(capL)
        code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        code.localSet(newValsL)
        code.i64Const(0)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        for dst in [newKeysL, newValsL] {
            code.localGet(dst)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(iL)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.localGet(dst == newKeysL ? keysL : valsL)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(iL)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.i64Load(offset: 0)
            code.i64Store(offset: 0)
        }
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.localGet(newKeysL)
        code.localSet(keysL)
        code.localGet(newValsL)
        code.localSet(valsL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.mapKeysOffset, valueLocal: keysL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.mapValuesOffset, valueLocal: valsL)
        code.end()
        code.localGet(keysL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(countL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(1)
        code.i64Store(offset: 0)
        code.localGet(valsL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(countL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.localGet(2)
        code.i64Store(offset: 0)
        code.localGet(countL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(countL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset, valueLocal: countL)
        code.i64Const(L.nullSentinel)
    }

    /// `(map, key) -> old value|nullSentinel`: shift-remove on hit.
    /// Locals: argumentCount = keys, +1 = values, +2 = count, +3 = idx,
    /// +4 = i, +5 = old.
    private static func emitMutableMapRemoveBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let keysL = argumentCount, valsL = argumentCount + 1
        let countL = argumentCount + 2, idxL = argumentCount + 3
        let iL = argumentCount + 4, oldL = argumentCount + 5
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapFlagsOffset)
        code.i64Const(1)
        code.op(WasmOpcode.i64And)
        code.i64Const(0)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        code.localGet(0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_map_index_of", argumentCount: 2))
        code.localSet(idxL)
        code.localGet(idxL)
        code.i64Const(0)
        code.op(WasmOpcode.i64LtS)
        code.openIf()
        code.i64Const(L.nullSentinel)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapKeysOffset)
        code.localSet(keysL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapValuesOffset)
        code.localSet(valsL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
        code.localSet(countL)
        code.localGet(valsL)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(idxL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localSet(oldL)
        // Shift tail left for both arrays.
        code.localGet(idxL)
        code.localSet(iL)
        code.openBlock()
        code.openLoop()
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.brIf(1)
        for arr in [keysL, valsL] {
            code.localGet(arr)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(iL)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.localGet(arr)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(iL)
            code.i64Const(1)
            code.op(WasmOpcode.i64Add)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.i64Load(offset: 0)
            code.i64Store(offset: 0)
        }
        code.localGet(iL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.localSet(iL)
        code.br(0)
        code.end()
        code.end()
        code.localGet(countL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Sub)
        code.localSet(countL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset, valueLocal: countL)
        code.localGet(oldL)
    }

    /// `(entry, value) -> old value`: `MutableEntry.setValue` thunk — updates
    /// the pair slot and, for live map entries, writes through to the map.
    /// Locals: argumentCount = old, +1 = map.
    private static func emitMutableMapEntrySetValueBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let oldL = argumentCount, mapL = argumentCount + 1
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairMapRefOffset)
        code.localSet(mapL)
        code.localGet(mapL)
        code.i64Const(0)
        code.op(WasmOpcode.i64Eq)
        code.openIf(result: .i64)
        // Standalone entry: old = slot.second; slot.second = value.
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairSecondOffset)
        code.localSet(oldL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.pairSecondOffset, valueLocal: 1)
        code.localGet(oldL)
        code.elseBranch()
        // Live entry: put() writes through and returns the previous value;
        // keep the pair slot in sync.
        code.localGet(mapL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.pairMapKeyOffset)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_mutable_map_put", argumentCount: 3))
        code.localSet(oldL)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.pairSecondOffset, valueLocal: 1)
        code.localGet(oldL)
        code.end()
    }

    /// `(map) -> iterator box` {container@16, index@24, expected@32} — the
    /// iterator shares the list-iterator layout; the type ID decides whether
    /// `next` yields keys (`__kk_map_iterator`) or entry boxes (`__kk_mutable_*`).
    /// Locals: argumentCount = iter object.
    private static func emitMapIteratorBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        name: String,
        argumentCount: Int
    ) {
        let objL = argumentCount
        code.i64Const(5)
        code.i64Const(
            name == "__kk_mutable_map_iterator"
                ? L.mutableMapIteratorTypeID : L.mapIteratorTypeID
        )
        code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
        code.localSet(objL)
        emitStoreAt(&code, baseLocal: objL, byteOffset: L.listArrayOffset, valueLocal: 0)
        emitStoreAtConst(&code, baseLocal: objL, byteOffset: L.listCountOffset, value: 0)
        // expected = map.count (CME sentinel).
        emitAddress(&code, baseLocal: objL, byteOffset: L.listFlagsOffset)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.mapCountOffset)
        code.i64Store(offset: 0)
        // Register Iterator itable so interface-typed receivers dispatch.
        emitIteratorItableRegistration(
            &code, ctx: ctx, objectLocal: objL,
            hasNextHelper: name == "__kk_mutable_map_iterator"
                ? "__kk_mutable_map_iterator_hasNext" : "__kk_map_iterator_hasNext",
            nextHelper: name == "__kk_mutable_map_iterator"
                ? "__kk_mutable_map_iterator_next" : "__kk_map_iterator_next"
        )
        code.localGet(objL)
    }

    /// Registers the `kotlin.collections.Iterator` itable (ifaceSlot 0:
    /// `hasNext`/`next` bound to the iterator's *specialized* helpers — the
    /// generic `kk_iterator_*` dispatchers resolve through this table and
    /// would recurse if registered here) on the object in `objectLocal`.
    private static func emitIteratorItableRegistration(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        objectLocal: Int,
        hasNextHelper: String,
        nextHelper: String
    ) {
        let regIface = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_iface", argumentCount: 3
        )
        let regMethod = ctx.emittedHelperIndex(
            for: "kk_object_register_itable_method", argumentCount: 4
        )
        code.localGet(objectLocal)
        code.i64Const(stableNominalTypeID("kotlin.collections.Iterator"))
        code.i64Const(0)
        code.call(regIface)
        code.op(WasmOpcode.drop)
        for (slot, helper) in [(0, hasNextHelper), (1, nextHelper)] {
            code.localGet(objectLocal)
            code.i64Const(0)
            code.i64Const(Int64(slot))
            code.i64Const(Int64(ctx.module.tableSlot(
                forFunction: ctx.emittedHelperIndex(for: helper, argumentCount: 1)
            )))
            code.call(regMethod)
            code.op(WasmOpcode.drop)
        }
    }

    /// `(iterator) -> i64`: generic `hasNext`/`next` — pure itable dispatch.
    /// The receiver may be ANY Iterator implementation: raw list/set/map
    /// iterator boxes (whose itables point at the specialized helpers) or a
    /// Kotlin-defined iterator object (anonymous `object : MutableIterator`
    /// like the `keys`/`values` view adapters). Probing the raw layout here
    /// would read past foreign objects, so always route through the object's
    /// registered `kotlin.collections.Iterator` itable entry instead.
    private static func emitGenericIteratorDispatch(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        methodSlot: Int64
    ) {
        // call_indirect args first (the receiver), then the funcref index.
        // A lookup miss yields table index 0 — trap rather than invoke an
        // unrelated funcref (native's kk_dispatch_error equivalent).
        code.localGet(0)
        code.localGet(0)
        code.i64Const(stableNominalTypeID("kotlin.collections.Iterator"))
        code.i64Const(methodSlot)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_itable_lookup", argumentCount: 3))
        code.localTee(1)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.op(WasmOpcode.unreachable)
        code.end()
        code.localGet(1)
        code.op(WasmOpcode.i32WrapI64)
        code.callIndirect(ctx.module.funcTypeIndex(.i64Signature(1)))
    }

    /// `(iterator) -> i64`: shared map-iterator `next` — CME check, bounds,
    /// then key-or-entry depending on the iterator's type ID.
    /// Locals: argumentCount = container, +1 = index, +2 = key, +3 = count.
    private static func emitMapIteratorNextBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let containerL = argumentCount, indexL = argumentCount + 1
        let keyL = argumentCount + 2, countL = argumentCount + 3
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listArrayOffset)
        code.localSet(containerL)
        // CME: expected (@32) vs live count.
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listFlagsOffset)
        emitLoadAt(&code, baseLocal: containerL, byteOffset: L.mapCountOffset)
        code.op(WasmOpcode.i64Ne)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        emitLoadAt(&code, baseLocal: containerL, byteOffset: L.mapCountOffset)
        code.localSet(countL)
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localTee(indexL)
        code.localGet(countL)
        code.op(WasmOpcode.i64GeS)
        code.openIf()
        code.i64Const(1)
        code.globalSet(ctx.thrownGlobal)
        code.i64Const(0)
        code.op(WasmOpcode.return)
        code.end()
        // key = map.keys[index]; index += 1.
        emitLoadAt(&code, baseLocal: containerL, byteOffset: L.mapKeysOffset)
        code.op(WasmOpcode.i32WrapI64)
        code.localGet(indexL)
        code.op(WasmOpcode.i32WrapI64)
        code.i32Const(8)
        code.op(WasmOpcode.i32Mul)
        code.op(WasmOpcode.i32Add)
        code.i64Load(offset: 0)
        code.localSet(keyL)
        emitAddress(&code, baseLocal: 0, byteOffset: L.listCountOffset)
        code.localGet(indexL)
        code.i64Const(1)
        code.op(WasmOpcode.i64Add)
        code.i64Store(offset: 0)
        // Mutable iterator returns a live entry; read-only returns the key.
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.typeIDOffset)
        code.i64Const(L.mutableMapIteratorTypeID)
        code.op(WasmOpcode.i64Eq)
        code.openIf(result: .i64)
        code.localGet(containerL)
        code.localGet(keyL)
        code.call(ctx.emittedHelperIndex(for: "__kk_wasm_map_entry", argumentCount: 2))
        code.elseBranch()
        code.localGet(keyL)
        code.end()
    }

    /// `(map, key) -> MutableEntry box`: live entry view used by map iterators
    /// and `entries`. Shares the pair layout; nonzero mapRef keeps
    /// `second`/`setValue` backed by `map[key]`.
    /// Locals: argumentCount = entry object.
    private static func emitMapEntryNewBody(
        _ code: inout WasmCode,
        ctx: WasmModuleContext,
        argumentCount: Int
    ) {
        let objL = argumentCount
        code.i64Const(6)
        code.i64Const(stableNominalTypeID("kotlin.collections.MutableMap.MutableEntry"))
        code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
        code.localSet(objL)
        emitStoreAt(&code, baseLocal: objL, byteOffset: L.pairFirstOffset, valueLocal: 1)
        emitStoreAt(&code, baseLocal: objL, byteOffset: L.pairMapRefOffset, valueLocal: 0)
        emitStoreAt(&code, baseLocal: objL, byteOffset: L.pairMapKeyOffset, valueLocal: 1)
        // second = map[key] (snapshot for pair-like use; mapRef keeps it live).
        emitAddress(&code, baseLocal: objL, byteOffset: L.pairSecondOffset)
        code.localGet(0)
        code.localGet(1)
        code.call(ctx.emittedHelperIndex(for: "__kk_map_get", argumentCount: 2))
        code.i64Store(offset: 0)
        emitCollectionItableRegistrations(&code, ctx: ctx, objectLocal: objL, set: false, entry: true)
        emitCollectionTypeEdges(&code, ctx: ctx, edges: [
            ("kotlin.collections.MutableMap.MutableEntry", "kotlin.collections.Map.Entry")
        ])
        code.localGet(objL)
    }

    // MARK: - Throwable intrinsics

    /// Nominal type IDs are the frontend's stable hash: FNV-1a over the fqName
    /// masked to 55 bits (mirrors `runtimeStableNominalTypeID`).
    static func stableNominalTypeID(_ fqName: String) -> Int64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in fqName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        let payload = Int64(bitPattern: hash) & ((Int64(1) << 55) - 1)
        return payload == 0 ? 1 : payload
    }

    /// What a `__kk_*`/ `kk_*` throwable intrinsic lowers to on wasm.
    private enum ThrowableHelperKind {
        /// Constructor: allocate the throwable box and store message/cause.
        /// `messageArg`/`causeArg` are parameter indices, `nil` when absent.
        case ctor(fqName: String, messageArg: Int?, causeArg: Int?)
        /// `__kk_throwable_message(obj)` — read the message slot.
        case message
        /// `__kk_throwable_setMessage(obj, message)` — write the message slot.
        case setMessage
        /// `__kk_throwable_cause(obj)` — read the cause slot.
        case cause
        /// `__kk_throwable_setCause(obj, cause)` — write the cause slot.
        case setCause
        /// `__kk_throwable_toString(obj)` — `"fqName"` or `"fqName: message"`.
        case toString
        /// `__kk_throwable_suppressedRaw(obj)` — lazily-allocated array slot.
        case suppressedRaw
        /// `kotlin.suppressedExceptions` getter — the raw array wrapped in a
        /// read-only List box.
        case suppressedList
        /// `__kk_throwable_appendSuppressed(obj, suppressed)` — bounded append.
        case appendSuppressed
        /// `__kk_throwable_rawStackFrames(obj)` — empty array (no frames yet).
        case rawStackFrames
        /// `__kk_throwable_set_options(...)` — accepted and ignored for now.
        case setOptions
    }

    /// Field slot layout on the throwable box:
    /// slot 2 = message, 3 = cause, 4 = fqName string, 5 = suppressed array.
    private static let throwableMessageSlotOffset: Int64 = 16
    private static let throwableCauseSlotOffset: Int64 = 24
    private static let throwableFqNameSlotOffset: Int64 = 32
    private static let throwableSuppressedSlotOffset: Int64 = 40
    /// Fixed suppressed-list capacity for the MVP (K/N semantics allow up to
    /// an arbitrary list; overflow is dropped and diagnosed nowhere — noted in
    /// the plan's limitations).
    private static let throwableSuppressedCapacity: Int64 = 8

    /// Callee-name prefix → fqName for `@KsSymbolName` throwable ctors.
    private static let throwableTypeByCalleePrefix: [(prefix: String, fqName: String)] = [
        ("__kk_throwable", "kotlin.Throwable"),
        ("kk_throwable", "kotlin.Throwable"),
        ("__kk_error", "kotlin.Error"),
        ("__kk_exception", "kotlin.Exception"),
        ("__kk_runtime_exception", "kotlin.RuntimeException"),
        ("__kk_illegal_argument_exception", "kotlin.IllegalArgumentException"),
        ("__kk_illegal_state_exception", "kotlin.IllegalStateException"),
        ("__kk_index_out_of_bounds_exception", "kotlin.IndexOutOfBoundsException"),
        ("__kk_array_index_out_of_bounds_exception", "kotlin.ArrayIndexOutOfBoundsException"),
        ("__kk_string_index_out_of_bounds_exception", "kotlin.StringIndexOutOfBoundsException"),
        ("__kk_null_pointer_exception", "kotlin.NullPointerException"),
        ("__kk_class_cast_exception", "kotlin.ClassCastException"),
        ("__kk_type_cast_exception", "kotlin.TypeCastException"),
        ("__kk_arithmetic_exception", "kotlin.ArithmeticException"),
        ("__kk_number_format_exception", "kotlin.NumberFormatException"),
        ("__kk_no_when_branch_matched_exception", "kotlin.NoWhenBranchMatchedException"),
        ("__kk_uninitialized_property_access_exception", "kotlin.UninitializedPropertyAccessException"),
        ("__kk_assertion_error", "kotlin.AssertionError"),
        ("__kk_concurrent_modification_exception", "kotlin.ConcurrentModificationException"),
        ("__kk_unsupported_operation_exception", "kotlin.UnsupportedOperationException"),
        ("__kk_no_such_element_exception", "kotlin.NoSuchElementException"),
        ("kk_negative_array_size_exception", "kotlin.NegativeArraySizeException"),
        ("__kk_negative_array_size_exception", "kotlin.NegativeArraySizeException"),
        ("__kk_not_implemented_error", "kotlin.NotImplementedError"),
        ("__kk_out_of_memory_error", "kotlin.OutOfMemoryError"),
        ("__kk_stack_overflow_error", "kotlin.StackOverflowError"),
        ("__kk_cancellation_exception", "kotlin.coroutines.cancellation.CancellationException"),
        ("__kk_closed_receive_channel_exception", "kotlinx.coroutines.channels.ClosedReceiveChannelException"),
        ("__kk_closed_send_channel_exception", "kotlinx.coroutines.channels.ClosedSendChannelException"),
        ("__kk_invalid_mutability_exception", "kotlin.native.concurrent.InvalidMutabilityException"),
        ("__kk_invalid_parameter_exception", "kotlin.InvalidParameterException"),
        ("__kk_kotlin_nothing_value_exception", "kotlin.KotlinNothingValueException"),
    ]

    /// Registered inside every throwable ctor so `catch`/`is` walks the same
    /// superclass DAG user classes build via `kk_type_register_super`.
    private static let throwableHierarchyEdges: [(child: String, parent: String)] = [
        ("kotlin.Error", "kotlin.Throwable"),
        ("kotlin.Exception", "kotlin.Throwable"),
        ("kotlin.RuntimeException", "kotlin.Exception"),
        ("kotlin.AssertionError", "kotlin.Error"),
        ("kotlin.NotImplementedError", "kotlin.Error"),
        ("kotlin.OutOfMemoryError", "kotlin.Error"),
        ("kotlin.StackOverflowError", "kotlin.Error"),
        ("kotlin.IllegalArgumentException", "kotlin.RuntimeException"),
        ("kotlin.IllegalStateException", "kotlin.RuntimeException"),
        ("kotlin.IndexOutOfBoundsException", "kotlin.RuntimeException"),
        ("kotlin.ArrayIndexOutOfBoundsException", "kotlin.IndexOutOfBoundsException"),
        ("kotlin.StringIndexOutOfBoundsException", "kotlin.IndexOutOfBoundsException"),
        ("kotlin.NullPointerException", "kotlin.RuntimeException"),
        ("kotlin.ClassCastException", "kotlin.RuntimeException"),
        ("kotlin.TypeCastException", "kotlin.ClassCastException"),
        ("kotlin.ArithmeticException", "kotlin.RuntimeException"),
        ("kotlin.NumberFormatException", "kotlin.IllegalArgumentException"),
        ("kotlin.NoWhenBranchMatchedException", "kotlin.RuntimeException"),
        ("kotlin.UninitializedPropertyAccessException", "kotlin.RuntimeException"),
        ("kotlin.ConcurrentModificationException", "kotlin.RuntimeException"),
        ("kotlin.UnsupportedOperationException", "kotlin.RuntimeException"),
        ("kotlin.NoSuchElementException", "kotlin.RuntimeException"),
        ("kotlin.NegativeArraySizeException", "kotlin.RuntimeException"),
        ("kotlin.coroutines.cancellation.CancellationException", "kotlin.IllegalStateException"),
        ("kotlin.native.concurrent.InvalidMutabilityException", "kotlin.RuntimeException"),
        ("kotlin.InvalidParameterException", "kotlin.IllegalArgumentException"),
        ("kotlin.KotlinNothingValueException", "kotlin.RuntimeException"),
    ]

    private static func throwableHelperKind(for name: String) -> ThrowableHelperKind? {
        switch name {
        case "__kk_throwable_message", "__kkThrowableMessage": return .message
        case "__kk_throwable_setMessage", "__kkThrowableSetMessage": return .setMessage
        case "__kk_throwable_cause", "__kkThrowableCause": return .cause
        case "__kk_throwable_setCause", "__kkThrowableSetCause": return .setCause
        case "__kk_throwable_toString", "__kkThrowableToString": return .toString
        case "__kk_throwable_suppressedRaw", "__kkThrowableSuppressedRaw": return .suppressedRaw
        case "__kk_throwable_suppressed_list": return .suppressedList
        case "__kk_throwable_appendSuppressed", "__kkThrowableAppendSuppressed": return .appendSuppressed
        case "__kk_throwable_rawStackFrames", "__kkThrowableRawStackFrames": return .rawStackFrames
        case "__kk_throwable_set_options", "__kkThrowableSetOptions": return .setOptions
        default: break
        }
        // Suffixes carry the argument layout; check longest first.
        let suffixes: [(String, message: Int?, cause: Int?)] = [
            ("_new_message_cause", 0, 1),
            ("_new_with_cause", 0, 1),
            ("_new_cause", nil, 0),
            ("_new_message", 0, nil),
            // `Throwable()`/`Throwable(message)` share `__kk_throwable_new`;
            // the arity guard in the ctor body decides whether arg0 exists.
            ("_new", 0, nil),
        ]
        for (suffix, message, cause) in suffixes where name.hasSuffix(suffix) {
            let prefix = String(name.dropLast(suffix.count))
            guard let pair = throwableTypeByCalleePrefix.first(where: { $0.prefix == prefix }) else {
                return nil
            }
            return .ctor(fqName: pair.fqName, messageArg: message, causeArg: cause)
        }
        return nil
    }

    /// Emits the body for throwable ctor/accessor helpers, or `nil` when the
    /// name isn't a throwable intrinsic.
    private static func emittedThrowableBody(
        for name: String,
        argumentCount: Int,
        context ctx: WasmModuleContext
    ) -> [UInt8]? {
        guard let kind = throwableHelperKind(for: name) else { return nil }
        var code = WasmCode()
        var extraLocals = 1
        switch kind {
        case let .ctor(fqName, messageArg, causeArg):
            // Materialize the superclass edges this type can be checked
            // against — user classes do this in their ctor callables, but an
            // intrinsic ctor has no lowered body to carry the registrations.
            let edgeHelper = ctx.emittedHelperIndex(
                for: "kk_type_register_super",
                argumentCount: 2
            )
            for (child, parent) in throwableHierarchyEdges {
                code.i64Const(stableNominalTypeID(child))
                code.i64Const(stableNominalTypeID(parent))
                code.call(edgeHelper)
                code.op(WasmOpcode.drop)
            }
            code.i64Const(6) // slots: iface, vtable, message, cause, fqName, suppressed
            code.i64Const(stableNominalTypeID(fqName))
            code.call(ctx.emittedHelperIndex(for: "kk_object_new", argumentCount: 2))
            // The single extra local sits right after the declared params.
            code.localSet(argumentCount)
            // fqName string object → slot 4 (drives `toString`/`printStackTrace`).
            emitAddress(&code, baseLocal: argumentCount, byteOffset: throwableFqNameSlotOffset)
            emitLiteralString(&code, ctx: ctx, fqName)
            code.i64Store(offset: 0)
            // `getStackTrace`/`toString`/`message`/`cause` dispatch through the
            // vtable, and intrinsic throwables would otherwise trap on an empty
            // slot. The stdlib Throwable layout puts `getStackTrace` at
            // vtable[0], `toString` at vtable[1], `message` at vtable[2],
            // `cause` at vtable[3]; point all at the accessor helpers
            // (receiver-in-arg0 matches call shape).
            let registerVtable = ctx.emittedHelperIndex(
                for: "kk_object_register_vtable_method",
                argumentCount: 3
            )
            for (slot, helper) in [
                (0, "__kk_throwable_rawStackFrames"),
                (1, "__kk_throwable_toString"),
                (2, "__kk_throwable_message"),
                (3, "__kk_throwable_cause"),
            ] {
                code.localGet(argumentCount)
                code.i64Const(Int64(slot))
                code.i64Const(Int64(ctx.module.tableSlot(
                    forFunction: ctx.emittedHelperIndex(for: helper, argumentCount: 1)
                )))
                code.call(registerVtable)
                code.op(WasmOpcode.drop)
            }
            if let messageArg, messageArg < argumentCount {
                emitStoreAt(
                    &code,
                    baseLocal: argumentCount,
                    byteOffset: throwableMessageSlotOffset,
                    valueLocal: messageArg
                )
            }
            if let causeArg, causeArg < argumentCount {
                emitStoreAt(
                    &code,
                    baseLocal: argumentCount,
                    byteOffset: throwableCauseSlotOffset,
                    valueLocal: causeArg
                )
            }
            code.localGet(argumentCount)
        case .message:
            emitLoadAt(&code, baseLocal: 0, byteOffset: throwableMessageSlotOffset)
        case .setMessage:
            emitStoreAt(&code, baseLocal: 0, byteOffset: throwableMessageSlotOffset, valueLocal: 1)
            code.i64Const(0)
        case .cause:
            emitLoadAt(&code, baseLocal: 0, byteOffset: throwableCauseSlotOffset)
        case .setCause:
            emitStoreAt(&code, baseLocal: 0, byteOffset: throwableCauseSlotOffset, valueLocal: 1)
            code.i64Const(0)
        case .toString:
            extraLocals = 2
            // fq = slot 4, msg = slot 2; result = msg ? fq + ": " + msg : fq
            emitLoadAt(&code, baseLocal: 0, byteOffset: throwableFqNameSlotOffset)
            code.localSet(1)
            emitLoadAt(&code, baseLocal: 0, byteOffset: throwableMessageSlotOffset)
            code.localTee(2)
            code.op(WasmOpcode.i64Eqz)
            code.openIf(result: .i64)
            code.localGet(1)
            code.elseBranch()
            code.localGet(1)
            emitLiteralString(&code, ctx: ctx, ": ")
            code.call(ctx.emittedHelperIndex(for: "__kk_string_concat_flat", argumentCount: 2))
            code.localGet(2)
            code.call(ctx.emittedHelperIndex(for: "__kk_string_concat_flat", argumentCount: 2))
            code.end()
        case .suppressedRaw, .appendSuppressed, .suppressedList:
            // Lazily allocate the suppressed array into slot 5; its meta slot
            // is the logical count (capacity stays hidden).
            extraLocals = 3
            emitLoadAt(&code, baseLocal: 0, byteOffset: throwableSuppressedSlotOffset)
            code.localTee(argumentCount)
            code.op(WasmOpcode.i64Eqz)
            code.openIf()
            code.i64Const(throwableSuppressedCapacity)
            code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
            code.localSet(argumentCount)
            emitStoreAt(
                &code,
                baseLocal: 0,
                byteOffset: throwableSuppressedSlotOffset,
                valueLocal: argumentCount
            )
            emitAddress(&code, baseLocal: argumentCount, byteOffset: L.metaOffset)
            code.i64Const(0)
            code.i64Store(offset: 0)
            code.end()
            if case .suppressedRaw = kind {
                code.localGet(argumentCount)
                break
            }
            if case .suppressedList = kind {
                // Wrap the raw array in a read-only List box; meta is already
                // the logical count.
                emitLoadAt(&code, baseLocal: argumentCount, byteOffset: L.metaOffset)
                code.localSet(argumentCount + 1)
                emitListBoxBody(
                    &code, ctx: ctx,
                    typeID: L.listTypeID, readOnly: true,
                    arrayLocal: argumentCount,
                    countLocal: argumentCount + 1,
                    objectLocal: argumentCount + 2
                )
                code.localGet(argumentCount + 2)
                break
            }
            // count = arr.meta; bail at capacity, else store + count++.
            emitLoadAt(&code, baseLocal: argumentCount, byteOffset: L.metaOffset)
            code.localTee(argumentCount + 1)
            code.i64Const(throwableSuppressedCapacity)
            code.op(WasmOpcode.i64GeS)
            code.openIf()
            code.i64Const(0)
            code.op(WasmOpcode.return)
            code.end()
            code.localGet(argumentCount)
            code.op(WasmOpcode.i32WrapI64)
            code.localGet(argumentCount + 1)
            code.op(WasmOpcode.i32WrapI64)
            code.i32Const(8)
            code.op(WasmOpcode.i32Mul)
            code.op(WasmOpcode.i32Add)
            code.localGet(1)
            code.i64Store(offset: 0)
            emitAddress(&code, baseLocal: argumentCount, byteOffset: L.metaOffset)
            code.localGet(argumentCount + 1)
            code.i64Const(1)
            code.op(WasmOpcode.i64Add)
            code.i64Store(offset: 0)
            code.i64Const(0)
        case .rawStackFrames:
            code.i64Const(0)
            code.call(ctx.emittedHelperIndex(for: "kk_array_new", argumentCount: 1))
        case .setOptions:
            code.i64Const(0)
        }
        return finish(code: &code, extraLocals: extraLocals)
    }
}
