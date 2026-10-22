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
        "kk_array_get_inbounds",
        "kk_array_get",
        "kk_array_set",
        "kk_array_length",
        "kk_array_size",
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
        "kk_string_length",
        "__kk_string_struct_get_length",
        "kk_string_get",
    ]

    /// Builds the wasm body for a helper callee. `nil` means no helper exists
    /// and the caller should fall back to a stub.
    static func emittedBody(for name: String, context ctx: WasmModuleContext) -> [UInt8]? {
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
            extraLocals = 1
            emitArrayNewBody(&code, ctx: ctx)
        case "kk_array_get_inbounds":
            extraLocals = 0
            emitArrayGetInboundsBody(&code)
        case "kk_array_get":
            extraLocals = 0
            emitArrayGetBody(&code, ctx: ctx)
        case "kk_array_set":
            extraLocals = 0
            emitArraySetBody(&code, ctx: ctx)
        case "kk_array_length", "kk_array_size":
            extraLocals = 0
            emitLoadMetaBody(&code)
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
        case "kk_string_length", "__kk_string_struct_get_length":
            extraLocals = 0
            emitStringLengthBody(&code)
        case "kk_string_get":
            extraLocals = 0
            emitStringGetBody(&code)
        default:
            return nil
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

    // MARK: Helper bodies

    /// `size -> i64`: lazy-initialized bump allocator.
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
        code.i64Const(7)
        code.op(WasmOpcode.i64Add)
        code.i64Const(-8)
        code.op(WasmOpcode.i64And)
        code.op(WasmOpcode.i64Add)          // old, new
        code.globalSet(ctx.heapGlobal)      // old
        code.i64Const(16)                   // object base sits past the
        code.op(WasmOpcode.i64Add)          // 16-byte header at old
    }

    /// `obj -> i64`: object's vtable pointer (meta slot), allocated lazily.
    private static func emitVtableAccessorBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        emitLoadAt(&code, baseLocal: 0, byteOffset: L.metaOffset)
        code.localTee(1)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        code.i64Const(Int64(L.vtableSlots * 8))
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(1)
        emitStoreAt(&code, baseLocal: 0, byteOffset: L.metaOffset, valueLocal: 1)
        code.end()
        code.localGet(1)
    }

    /// `length, classID -> i64`: header {typeID@-16, meta@-8} + slots at 0...
    private static func emitObjectNewBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.i64Const(8)
        code.op(WasmOpcode.i64Mul)
        code.i64Const(16)
        code.op(WasmOpcode.i64Add)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        emitStoreAt(&code, baseLocal: 2, byteOffset: L.typeIDOffset, valueLocal: 1)
        code.localGet(2)
    }

    /// `count -> i64`: uniform box with ARRAY tag and length in the meta slot.
    private static func emitArrayNewBody(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.localGet(0)
        code.i64Const(8)
        code.op(WasmOpcode.i64Mul)
        code.i64Const(16)
        code.op(WasmOpcode.i64Add)
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
        code.i64Const(16 + 32)
        code.call(ctx.emittedHelperIndex(for: "$__kk_wasm_alloc", argumentCount: 1))
        code.localSet(2)
        emitStoreAtConst(&code, baseLocal: 2, byteOffset: L.typeIDOffset, value: L.stringTypeID)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 0, valueLocal: 0)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 8, valueLocal: 1)
        emitStoreAt(&code, baseLocal: 2, byteOffset: 16, valueLocal: 1)
        code.localGet(2)
    }

    /// `fd_write(1, iovec, 1, nwritten)` — drops the errno result.
    private static func emitFDWrite(_ code: inout WasmCode, ctx: WasmModuleContext) {
        code.i32Const(1)
        code.i32Const(Int32(L.iovecAddress))
        code.i32Const(1)
        code.i32Const(Int32(L.nwrittenAddress))
        code.call(ctx.wasmImportFDWrite())
        code.op(WasmOpcode.drop)
    }

    /// `string -> i64`: WASI fd_write of the flat string's byte payload.
    private static func emitPrintBody(_ code: inout WasmCode, ctx: WasmModuleContext, newline: Bool) {
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
        emitFDWrite(&code, ctx: ctx)
        if newline {
            code.i32Const(Int32(L.iovecAddress))
            code.i32Const(Int32(L.newlineAddress))
            code.i32Store()
            code.i32Const(Int32(L.iovecAddress + 4))
            code.i32Const(1)
            code.i32Store()
            emitFDWrite(&code, ctx: ctx)
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
}
