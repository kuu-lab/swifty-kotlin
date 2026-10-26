// WasmEmitter.swift — KIR → WebAssembly binary.
//
// Value model: every KIR value is an i64. Heap objects are linear-memory
// addresses; every box stores its nominal type ID at offset -16 and its
// slot count (array length / object layoutWords) at offset -8. For objects,
// slot 0 (base+0) holds the interface-dispatch map and slot 1 (base+8) the
// vtable pointer, leaving user fields at slot 2+ exactly like the native
// kk_array_get_inbounds layout. Primitive boxing is the identity while all
// values are raw i64s, and the thrown channel is a single i64 global instead
// of the trailing outThrown pointer.

import Foundation
import CompilerCore

public enum WasmEmitterError: Error, CustomStringConvertible {
    case nonLaminarControlFlow(String)

    public var description: String {
        switch self {
        case let .nonLaminarControlFlow(name):
            "wasm emitter: non-laminar control flow in '\(name)'"
        }
    }
}

public struct WasmEmissionResult: Sendable {
    public let bytes: [UInt8]
    public let stubbedCallees: [String]
    public let notes: [String]
}

/// Shared emission state for one module. Function bodies are emitted by
/// `WasmFunctionEmission` (see WasmEmitter+Function.swift); runtime helpers
/// are hand-assembled in WasmEmitter+Runtime.swift.
final class WasmModuleContext {
    let module = WasmModule()
    let kir: KIRModule
    let interner: StringInterner
    let symbols: SymbolTable?
    let types: TypeSystem?
    let isWASI: Bool

    // Symbol/name → function index resolution.
    var functionIndexBySymbol: [SymbolID: Int] = [:]
    var functionIndexByNameArity: [String: Int] = [:]
    /// Helpers are keyed by `name/arity`: some runtime names overload by
    /// arity (`__kk_throwable_new` takes 0 or 1 args), and a wasm function's
    /// signature is fixed at creation, so each arity needs its own entry.
    var helperIndexByName: [String: Int] = [:]
    var stubIndexByNameArity: [String: Int] = [:]
    var importIndexByName: [String: Int] = [:]

    var globalIndexBySymbol: [SymbolID: Int] = [:]
    var paramIndexBySymbolByFunction: [SymbolID: [Int32: Int]] = [:]

    // Runtime globals (indices into the module's global section).
    var thrownGlobal = -1
    var heapGlobal = -1
    var edgeHeadGlobal = -1
    var dataEndGlobal = -1

    // Lazily-created WASI imports (only when isWASI).
    var fdWriteImport = -1
    var procExitImport = -1

    // Bump cursor for static data (string literal bytes); heap follows.
    var dataCursor: Int64 = WasmLayout.dataStart
    var stringOffsetByLiteral: [InternedString: Int64] = [:]

    var stubbedCallees: [String] = []
    var notes: [String] = []

    init(kir: KIRModule, interner: StringInterner, symbols: SymbolTable?, types: TypeSystem?, isWASI: Bool) {
        self.kir = kir
        self.interner = interner
        self.symbols = symbols
        self.types = types
        self.isWASI = isWASI
    }

    enum WasmLayout {
        /// Bytes [0, dataStart) are runtime scratch space (iovecs, newline).
        static let dataStart: Int64 = 1024
        /// iovec base for WASI writes.
        static let iovecAddress: Int64 = 8
        static let nwrittenAddress: Int64 = 24
        static let newlineAddress: Int64 = 32
        /// Byte offset of the nominal type ID relative to a box base.
        static let typeIDOffset: Int64 = -16
        /// Byte offset of the slot count (array length / object layoutWords).
        static let metaOffset: Int64 = -8
        /// Body slot 1: the object's vtable pointer (arrays use it as
        /// element 1 — the two never collide because dispatch never runs on
        /// plain arrays).
        static let vtableSlotOffset: Int64 = 8
        /// Reserved class IDs for runtime-internal box kinds.
        static let arrayTypeID: Int64 = -9_001
        static let stringTypeID: Int64 = -9_002
        /// Kotlin `List` box (read-only views from `listOf`/`toList`).
        static let listTypeID: Int64 = -9_010
        /// Kotlin `MutableList`/`ArrayList` box (`mutableListOf`/`arrayListOf`).
        static let arrayListTypeID: Int64 = -9_011
        /// `kk_list_iterator` result box.
        static let listIteratorTypeID: Int64 = -9_012
        /// List/iterator body slot offsets (object slots 2/3/4): slot2 holds
        /// the backing array (or the list, for iterators), slot3 the element
        /// count (or iterator index), slot4 flags (or expected count).
        static let listArrayOffset: Int64 = 16
        static let listCountOffset: Int64 = 24
        static let listFlagsOffset: Int64 = 32
        /// `kk_map_iterator` result box.
        static let mapIteratorTypeID: Int64 = -9_013
        /// `kk_mutable_map_iterator` result box.
        static let mutableMapIteratorTypeID: Int64 = -9_014
        /// `__kk_range_for_in_iterator` result box: `{cur@16, last@24, step@32}`.
        static let rangeForInIteratorTypeID: Int64 = -9_015
        /// `kk_function_create_N` function-value box:
        /// `{fnTableIdx@16, closure@24, arity@32, description@40}`.
        static let functionValueTypeID: Int64 = -9_016
        /// Function-value box field offsets.
        static let functionFnIdxOffset: Int64 = 16
        static let functionClosureOffset: Int64 = 24
        static let functionArityOffset: Int64 = 32
        static let functionDescOffset: Int64 = 40
        /// Set boxes share the list layout `{array@16, count@24, flags@32}`
        /// so `kk_list_iterator` iterates them unchanged. Concrete nominal
        /// tags come from `stableNominalTypeID` so `is` checks work.
        /// Map box slots: keys@16, values@24, count@32, flags@40.
        static let mapKeysOffset: Int64 = 16
        static let mapValuesOffset: Int64 = 24
        static let mapCountOffset: Int64 = 32
        static let mapFlagsOffset: Int64 = 40
        /// Pair/MapEntry box slots: first@16, second@24, mapRef@32,
        /// mapKey@40. A nonzero mapRef makes `second` a live `map[key]` view.
        static let pairFirstOffset: Int64 = 16
        static let pairSecondOffset: Int64 = 24
        static let pairMapRefOffset: Int64 = 32
        static let pairMapKeyOffset: Int64 = 40
        /// vtable layout: [0, vtableMethods) direct slots, then itable blocks.
        static let vtableDirectSlots = 16
        static let itableStride = 32
        static let vtableSlots = 16 + 32 * 16 // 528 entries
        /// Per-object interface map capacity (typeID, slot) pairs.
        static let ifaceMapCapacity = 8
        /// Tagged small-int sentinels must never look like real pointers.
        static let nullSentinel: Int64 = Int64.min
    }

    func emitFunctions() -> [KIRFunction] {
        var result: [KIRFunction] = []
        for decl in kir.arena.declarations {
            guard case let .function(function) = decl, !function.isInlineOnly else { continue }
            result.append(function)
        }
        return result
    }

    func resolveCallee(name: String, symbol: SymbolID?, argumentCount: Int) -> CalleeResolution {
        // Runtime-lowered names must win over a retained source symbol: the
        // symbol can be stale bookkeeping for inline expansion while the kk_*
        // text is the real target (mirrors NativeEmitter's contract).
        // `kk_lambda_<id>` is the exception — the retained symbol *is* the
        // lowered lambda body (same carve-out as the native emitter).
        let isRuntimeName = (name.hasPrefix("kk_") || name.hasPrefix("__kk_") || name.hasPrefix("$"))
            && !name.hasPrefix("kk_lambda_")
        if !isRuntimeName,
           let symbol,
           let index = functionIndexBySymbol[symbol]
        {
            return .direct(index)
        }
        if !isRuntimeName,
           symbol == nil,
           let index = functionIndexByNameArity["\(name)/\(argumentCount)"]
        {
            return .direct(index)
        }
        if WasmRuntimeHelpers.isEmittedHelperName(name) {
            return .emittedHelper(emittedHelperIndex(for: name, argumentCount: argumentCount))
        }
        if let index = helperIndexByName["\(name)/\(argumentCount)"] {
            return .emittedHelper(index)
        }
        // Stdlib bodies live in the .kklib, not this module — a handful have
        // direct wasm intrinsics (kotlin.io.println forwards to the raw WASI
        // writer, exactly as its bundled body does via __printlnStringRaw).
        if let helper = stdlibIntrinsicName(symbol: symbol, argumentCount: argumentCount) {
            return .emittedHelper(emittedHelperIndex(for: helper, argumentCount: argumentCount))
        }
        // `$default` forwarders and other symbol-less stdlib shims only carry
        // their callee name — route the known ones onto the same helpers the
        // fqName path selects.
        if let helper = stdlibShimName(for: name) {
            return .emittedHelper(emittedHelperIndex(for: helper, argumentCount: argumentCount))
        }
        return .stub(name)
    }

    /// Stdlib shims whose symbol doesn't survive lowering (the
    /// `<fn>$default` forwarders the default-argument expansion emits).
    private func stdlibShimName(for name: String) -> String? {
        switch name {
        case "joinToString", "joinToString$default":
            return "__kk_string_joinToString"
        default:
            return nil
        }
    }

    /// Maps stdlib symbols whose kklib bodies aren't in this module onto wasm
    /// runtime helpers that reproduce the same observable behavior.
    private func stdlibIntrinsicName(symbol: SymbolID?, argumentCount: Int) -> String? {
        // `call get`/`call set` carry synthetic *accessor* symbols that are not
        // in the plain symbol table — decode them to the backing property so
        // `arr.size` reaches the same fqName `Throwable.suppressed` uses.
        let resolvedSymbol = symbol.flatMap { sym -> SymbolID? in
            if symbols?.symbol(sym) != nil { return sym }
            return symbols?.propertySymbol(forAccessor: sym)
                ?? symbols?.accessorOwnerProperty(for: sym)
        }
        guard let resolvedSymbol, let sem = symbols?.symbol(resolvedSymbol) else {
            return nil
        }
        let symbol = resolvedSymbol
        // Accessor/intrinsic declarations carry their runtime symbol through
        // @KsSymbolName — if it matches an emitted helper, route directly.
        if let link = symbols?.externalLinkName(for: symbol),
           !link.isEmpty,
           WasmRuntimeHelpers.isEmittedHelperName(link)
        {
            return link
        }
        let fq = sem.fqName.map { interner.resolve($0) }
        if ProcessInfo.processInfo.environment["KSWIFTK_WASM_TRACE_CALLEES"] != nil {
            FileHandle.standardError.write(
                "wasm-callee /\(argumentCount) fq=\(fq.joined(separator: ".")) link=\(symbols?.externalLinkName(for: symbol) ?? "-")\n".data(using: .utf8)!
            )
        }
        // Throwable members whose bodies live in the kklib map onto the
        // intrinsic accessors backing the boxed storage. Accessor symbols
        // append a `$get`/`$set` component to the property's fqName.
        if fq.count >= 2, fq[0] == "kotlin" {
            var components = fq
            if components.last == "$get" || components.last == "$set" {
                components.removeLast()
            }
            let member = (components.last ?? "")
                .replacingOccurrences(of: ".$get", with: "")
                .replacingOccurrences(of: ".$set", with: "")
            if components.count >= 2, components[1] == "Throwable" {
                switch member {
                case "suppressed":
                    return "__kk_throwable_suppressedRaw"
                case "getStackTrace":
                    return "__kk_throwable_rawStackFrames"
                default: break
                }
            }
            if components.count == 3, components[1] == "Array",
               member == "size", argumentCount == 1
            {
                return "__kk_array_size"
            }
            // `Pair.first` carries @KsSymbolName on the property; `second`
            // and the componentN operators only mark their private
            // component accessors — route them onto the same slot readers.
            if components.count == 3, components[1] == "Pair" {
                switch member {
                case "first", "component1": return "__kk_pair_first"
                case "second", "component2": return "__kk_pair_second"
                default: break
                }
            }
            // `IntArray.size`/`Array<T>.size`/... are top-level extension
            // properties in package `kotlin.collections` — their accessor
            // fqName is `kotlin.collections.size.$get` with no receiver
            // component. Every bundled `kotlin.collections.size` getter
            // forwards to an array-meta load.
            if components == ["kotlin", "collections", "size"], argumentCount == 1 {
                return "__kk_array_size"
            }
            if components.count == 2 {
                switch components[1] {
                case "addSuppressed": return "__kk_throwable_appendSuppressed"
                case "getSuppressed": return "__kk_throwable_suppressedRaw"
                case "suppressedExceptions": return "__kk_throwable_suppressed_list"
                case "initCause": return "__kk_throwable_setCause"
                default: break
                }
            }
            if components.count == 3, components[1] == "collections" {
                switch components[2] {
                case "toList":
                    return argumentCount == 1 ? "__kk_list_to_list" : nil
                default: break
                }
            }
            // `kotlin.ranges` member/extension calls whose kklib bodies can't
            // run forward onto the range-box helpers — every nominal tag
            // shares the `{first@16, last@24, step@32}` layout.
            if components.count >= 2, components[1] == "ranges" {
                switch member {
                case "until": return "__kk_op_rangeUntil"
                case "downTo": return "__kk_op_downTo"
                case "step": return "__kk_op_step"
                case "rangeTo": return "__kk_op_rangeTo"
                case "toList": return "__kk_range_to_list"
                case "contains": return "__kk_range_contains"
                case "isEmpty": return "__kk_range_isEmpty"
                case "first", "start": return "__kk_range_first"
                case "last", "endInclusive": return "__kk_range_last"
                case "iterator": return "__kk_range_for_in_iterator"
                default: break
                }
            }
            // `kotlin.collections` member/extension calls on the shared
            // `{array,count,flags}` box. Owner guard keeps Map-box members
            // (`isEmpty`, `contains`…) from reading the wrong slot layout;
            // extension fns have no owner component (nil = allowed).
            if components.count >= 3, components[1] == "collections" {
                let listBoxOwners: Set<String> = [
                    "Iterable", "MutableIterable", "Collection",
                    "MutableCollection", "List", "MutableList", "ArrayList",
                    "AbstractList", "AbstractCollection", "Set", "MutableSet",
                    "HashSet", "LinkedHashSet",
                ]
                if components.count == 3 || listBoxOwners.contains(components[2]) {
                    switch member {
                    case "indexOf": return "__kk_list_index_of"
                    case "lastIndexOf": return "__kk_list_last_index_of"
                    case "contains": return "__kk_set_contains"
                    case "first": return "__kk_list_first"
                    case "last": return "__kk_list_last"
                    case "isEmpty": return "__kk_list_is_empty"
                    case "joinToString": return "__kk_string_joinToString"
                    default: break
                    }
                }
            }
            // `List`/`MutableList`/`ArrayList` member `size` accessors decode
            // to `kotlin.collections.<Owner>.size`; all read the same slot.
            if components.count == 4,
               components[0] == "kotlin", components[1] == "collections",
               member == "size", argumentCount == 1,
               ["List", "MutableList", "ArrayList", "Collection",
                "MutableCollection", "AbstractList", "AbstractCollection",
                "Iterable"].contains(components[2])
            {
                return "__kk_list_size"
            }
            guard fq.count == 3, fq[1] == "io", argumentCount == 1 else {
                return nil
            }
            switch fq[2] {
            case "println": return "__kk_println_raw"
            case "print": return "__kk_print_raw"
            default: return nil
            }
        }
        return nil
    }

    enum CalleeResolution {
        case direct(Int)
        case emittedHelper(Int)
        case stub(String)
    }

    func wasmImportFDWrite() -> Int {
        if fdWriteImport < 0 {
            fdWriteImport = module.addImportFunction(
                module: "wasi_snapshot_preview1",
                name: "fd_write",
                type: WasmFuncType(params: [.i32, .i32, .i32, .i32], results: [.i32])
            )
        }
        return fdWriteImport
    }

    func wasmImportProcExit() -> Int {
        if procExitImport < 0 {
            procExitImport = module.addImportFunction(
                module: "wasi_snapshot_preview1",
                name: "proc_exit",
                type: WasmFuncType(params: [.i32], results: [])
            )
        }
        return procExitImport
    }

    /// Places `bytes` in a data segment and returns its linear-memory offset.
    /// Used by helpers that need compile-time-known payloads (e.g. the
    /// "true"/"false" spellings inside `kk_any_to_string`).
    func dataOffset(for bytes: [UInt8]) -> Int64 {
        let offset = dataCursor
        dataCursor += Int64(bytes.count)
        module.addDataSegment(offset: offset, bytes: bytes)
        return offset
    }

    /// Lazily emits (or returns) the wasm function implementing a runtime
    /// helper callable by KIR name (`kk_object_new`, `__kk_println_raw`, ...).
    func emittedHelperIndex(for name: String, argumentCount: Int) -> Int {
        let key = "\(name)/\(argumentCount)"
        if let existing = helperIndexByName[key] { return existing }
        guard let body = WasmRuntimeHelpers.emittedBody(
            for: name,
            argumentCount: argumentCount,
            context: self
        ) else {
            return stubIndex(for: name, argumentCount: argumentCount)
        }
        let index = module.addFunction(
            type: .i64Signature(argumentCount),
            name: "$\(name)"
        )
        helperIndexByName[key] = index
        module.setBody(body, forFunctionIndex: index)
        return index
    }

    func stubIndex(for name: String, argumentCount: Int) -> Int {
        let key = "\(name)/\(argumentCount)"
        if let existing = stubIndexByNameArity[key] { return existing }
        let index = module.addFunction(type: .i64Signature(argumentCount), name: "$stub_\(name)")
        stubIndexByNameArity[key] = index
        stubbedCallees.append(name)
        var code = WasmCode()
        code.i64Const(0)
        var body = WasmCode()
        body.u(0) // no extra locals
        body.bytes.append(contentsOf: code.bytes)
        body.op(WasmOpcode.end)
        module.setBody(body.bytes, forFunctionIndex: index)
        return index
    }
}

public struct WasmEmitter {
    public init() {}

    public func emitModule(
        module kir: KIRModule,
        interner: StringInterner,
        symbols: SymbolTable?,
        types: TypeSystem?,
        entrySymbol: SymbolID?,
        target: TargetTriple,
        diagnostics: DiagnosticEngine?
    ) throws -> WasmEmissionResult {
        let ctx = WasmModuleContext(
            kir: kir,
            interner: interner,
            symbols: symbols,
            types: types,
            isWASI: target.isWASI || (!target.isWasmJS && target.isWasm)
        )

        // Pre-register WASI imports so they occupy the leading function indices.
        if ctx.isWASI {
            _ = ctx.wasmImportFDWrite()
            _ = ctx.wasmImportProcExit()
        }

        // Reserve funcref table slot 0 for a dispatch-error thunk. Vtable and
        // itable memory is zero-initialised, so an unwritten slot reads back
        // as 0 — without a real occupant here `call_indirect` would alias
        // whatever function landed at slot 0 (the native equivalent is
        // `kk_dispatch_error`). Every genuine registration gets a slot >= 1.
        let dispatchErrorIndex = ctx.module.addFunction(
            type: .i64Signature(0), name: "$__kk_wasm_dispatch_error"
        )
        var dispatchErrorBody = WasmCode()
        dispatchErrorBody.u(0)
        dispatchErrorBody.op(WasmOpcode.unreachable)
        dispatchErrorBody.op(WasmOpcode.end)
        ctx.module.setBody(dispatchErrorBody.bytes, forFunctionIndex: dispatchErrorIndex)
        _ = ctx.module.tableSlot(forFunction: dispatchErrorIndex)

        // Register internal functions, then KIR globals, then runtime globals.
        let functions = ctx.emitFunctions()
        var ambiguous: Set<String> = []
        var aritySeen: Set<String> = []
        for function in functions {
            let index = ctx.module.addFunction(
                type: .i64Signature(function.params.count),
                name: interner.resolve(function.name)
            )
            ctx.functionIndexBySymbol[function.symbol] = index
            let name = interner.resolve(function.name)
            let key = "\(name)/\(function.params.count)"
            if aritySeen.contains(key) {
                ambiguous.insert(key)
            } else {
                aritySeen.insert(key)
                ctx.functionIndexByNameArity[key] = index
            }
            var paramLocals: [Int32: Int] = [:]
            for (index, param) in function.params.enumerated() {
                paramLocals[param.symbol.rawValue] = index
            }
            ctx.paramIndexBySymbolByFunction[function.symbol] = paramLocals
        }
        for key in ambiguous {
            ctx.functionIndexByNameArity.removeValue(forKey: key)
        }

        for decl in kir.arena.declarations {
            guard case let .global(global) = decl else { continue }
            ctx.globalIndexBySymbol[global.symbol] = ctx.module.addGlobal(
                initialValue: 0,
                name: "$g\(global.symbol.rawValue)"
            )
        }
        ctx.thrownGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_thrown")
        ctx.heapGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_heap")
        ctx.edgeHeadGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_type_edges")
        // Filled in after all bodies are emitted: the data segments grow as
        // string literals are discovered, so the heap base is only known then.
        ctx.dataEndGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_data_end")

        // Emit function bodies.
        var emissionErrors: [Error] = []
        for function in functions {
            do {
                let emission = WasmFunctionEmission(ctx: ctx, function: function)
                let body = try emission.emitBody()
                guard let index = ctx.functionIndexBySymbol[function.symbol] else { continue }
                ctx.module.setBody(body, forFunctionIndex: index)
            } catch {
                emissionErrors.append(error)
            }
        }
        if let first = emissionErrors.first {
            diagnostics?.error(
                "KSWIFTK-WASM-0003",
                "wasm emission failed: \(first)",
                range: nil
            )
            throw first
        }

        // Export user-visible functions and the entry wrapper.
        var exportedNames: Set<String> = []
        for function in functions {
            let rawName = ctx.symbols?.externalLinkName(for: function.symbol)
                ?? interner.resolve(function.name)
            let exportName = sanitizeExportName(rawName)
            guard !exportName.isEmpty, exportedNames.insert(exportName).inserted,
                  let index = ctx.functionIndexBySymbol[function.symbol] else { continue }
            ctx.module.addExport(name: exportName, kind: .function, index: index)
        }

        if let entrySymbol, let entryIndex = ctx.functionIndexBySymbol[entrySymbol] {
            emitEntryWrapper(ctx: ctx, entryIndex: entryIndex)
        }

        // Memory sizing: data segments are placed as they are discovered, so
        // the heap base is fixed now that all bodies are emitted. `$__kk_alloc`
        // lazily seeds the bump pointer from this global on first use, which
        // also covers direct calls to exported functions that skip `_start`.
        let dataEnd = align(ctx.dataCursor, to: 16)
        ctx.module.setGlobalInitialValue(index: ctx.dataEndGlobal, value: dataEnd)
        ctx.module.memoryMinPages = Int((dataEnd + 16 * 65_536) / 65_536)
        ctx.module.exportMemoryName = "memory"

        if !ctx.stubbedCallees.isEmpty {
            let preview = ctx.stubbedCallees.prefix(8).joined(separator: ", ")
            diagnostics?.warning(
                "KSWIFTK-WASM-0001",
                "\(ctx.stubbedCallees.count) runtime callee(s) have no wasm implementation yet and were stubbed to return 0: \(preview)\(ctx.stubbedCallees.count > 8 ? ", ..." : "")",
                range: nil
            )
        }
        for note in ctx.notes {
            diagnostics?.warning("KSWIFTK-WASM-0002", note, range: nil)
        }

        return WasmEmissionResult(
            bytes: ctx.module.encode(),
            stubbedCallees: ctx.stubbedCallees.sorted(),
            notes: ctx.notes
        )
    }

    /// `_start` (WASI) / `main` (wasm-js) calls the Kotlin entry, then converts
    /// a non-zero thrown channel into an stderr diagnostic + `proc_exit(70)`
    /// (WASI) or a trap (wasm-js). Mirrors Kotlin/Native's uncaught-throwable
    /// reporting (`Uncaught Kotlin exception: <toString>`).
    private func emitEntryWrapper(ctx: WasmModuleContext, entryIndex: Int) {
        var code = WasmCode()
        code.call(entryIndex)
        code.op(WasmOpcode.drop)
        code.globalGet(ctx.thrownGlobal)
        code.localSet(0)
        code.localGet(0)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        // thrown == 0 → normal exit
        code.elseBranch()
        if ctx.isWASI {
            // stderr: "Uncaught Kotlin exception: " + toString(thrown) + "\n"
            let prefix = "Uncaught Kotlin exception: "
            let prefixOffset = ctx.dataOffset(for: Array(prefix.utf8))
            code.i64Const(prefixOffset)
            code.i64Const(Int64(prefix.utf8.count))
            code.call(ctx.emittedHelperIndex(
                for: "__kk_string_literal_from_utf8",
                argumentCount: 2
            ))
            code.call(ctx.emittedHelperIndex(for: "__kk_printStderr", argumentCount: 1))
            code.op(WasmOpcode.drop)
            code.localGet(0)
            code.call(ctx.emittedHelperIndex(for: "__kk_throwable_toString", argumentCount: 1))
            code.call(ctx.emittedHelperIndex(for: "$__kk_println_stderr", argumentCount: 1))
            code.op(WasmOpcode.drop)
            code.i32Const(70) // EX_SOFTWARE
            code.call(ctx.wasmImportProcExit())
        }
        code.op(WasmOpcode.unreachable)
        code.end()
        var body = WasmCode()
        body.u(1)
        body.u(1)
        body.op(WasmValType.i64.rawValue)
        body.bytes.append(contentsOf: code.bytes)
        body.op(WasmOpcode.end)
        let index = ctx.module.addFunction(
            type: WasmFuncType(params: [], results: []),
            name: "$__kk_wasm_start"
        )
        ctx.module.setBody(body.bytes, forFunctionIndex: index)
        ctx.module.addExport(
            name: ctx.isWASI ? "_start" : "main",
            kind: .function,
            index: index
        )
    }

    private func sanitizeExportName(_ name: String) -> String {
        var out = ""
        for character in name {
            if character.isLetter || character.isNumber || character == "_" || character == "$" {
                out.append(character)
            } else {
                out.append("_")
            }
        }
        return out
    }

    private func align(_ value: Int64, to alignment: Int64) -> Int64 {
        (value + alignment - 1) / alignment * alignment
    }
}
