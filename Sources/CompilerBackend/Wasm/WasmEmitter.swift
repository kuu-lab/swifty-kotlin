// WasmEmitter.swift — KIR → WebAssembly binary.
//
// Value model: every KIR value is an i64. Heap objects are linear-memory
// addresses; every box stores its nominal type ID at offset -16 and a
// metadata word at -8 (array length for arrays, vtable pointer for objects).
// Slots are addressed as `base + index*8`, matching the native runtime's
// kk_array_get_inbounds convention where object fields start at slot 2.
// Primitive boxing uses odd tagged integers (`(v << 1) | 1`), and the thrown
// channel is a single i64 global instead of the trailing outThrown pointer.

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
        /// Byte offset of the metadata word (array length / vtable ptr).
        static let metaOffset: Int64 = -8
        /// Reserved class IDs for runtime-internal box kinds.
        static let arrayTypeID: Int64 = -9_001
        static let stringTypeID: Int64 = -9_002
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
        if WasmRuntimeHelpers.functionCalleeNames.contains(name) {
            return .emittedHelper(emittedHelperIndex(for: name, argumentCount: argumentCount))
        }
        if let index = helperIndexByName[name] {
            return .emittedHelper(index)
        }
        // Stdlib bodies live in the .kklib, not this module — a handful have
        // direct wasm intrinsics (kotlin.io.println forwards to the raw WASI
        // writer, exactly as its bundled body does via __printlnStringRaw).
        if let helper = stdlibIntrinsicName(symbol: symbol, argumentCount: argumentCount) {
            return .emittedHelper(emittedHelperIndex(for: helper, argumentCount: argumentCount))
        }
        return .stub(name)
    }

    /// Maps stdlib symbols whose kklib bodies aren't in this module onto wasm
    /// runtime helpers that reproduce the same observable behavior.
    private func stdlibIntrinsicName(symbol: SymbolID?, argumentCount: Int) -> String? {
        guard let symbol, let sem = symbols?.symbol(symbol) else { return nil }
        let fq = sem.fqName.map { interner.resolve($0) }
        guard fq.count == 3, fq[0] == "kotlin", fq[1] == "io", argumentCount == 1 else {
            return nil
        }
        switch fq[2] {
        case "println": return "__kk_println_raw"
        case "print": return "__kk_print_raw"
        default: return nil
        }
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

    /// Lazily emits (or returns) the wasm function implementing a runtime
    /// helper callable by KIR name (`kk_object_new`, `__kk_println_raw`, ...).
    func emittedHelperIndex(for name: String, argumentCount: Int) -> Int {
        if let existing = helperIndexByName[name] { return existing }
        guard let body = WasmRuntimeHelpers.emittedBody(for: name, context: self) else {
            return stubIndex(for: name, argumentCount: argumentCount)
        }
        let index = module.addFunction(
            type: .i64Signature(argumentCount),
            name: "$\(name)"
        )
        helperIndexByName[name] = index
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
    /// a non-zero thrown channel into `proc_exit(70)` (WASI) or a trap.
    private func emitEntryWrapper(ctx: WasmModuleContext, entryIndex: Int) {
        var code = WasmCode()
        code.call(entryIndex)
        code.op(WasmOpcode.drop)
        code.globalGet(ctx.thrownGlobal)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        // thrown == 0 → normal exit
        code.elseBranch()
        if ctx.isWASI {
            code.i32Const(70) // EX_SOFTWARE
            code.call(ctx.wasmImportProcExit())
        }
        code.op(WasmOpcode.unreachable)
        code.end()
        var body = WasmCode()
        body.u(0)
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
