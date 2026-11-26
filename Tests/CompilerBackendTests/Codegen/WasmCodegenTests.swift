@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct WasmCodegenTests {
    let interner = StringInterner()

    @Test
    func targetTripleClassifiesWasm() {
        #expect(TargetTriple.wasmWASI.isWasm)
        #expect(TargetTriple.wasmWASI.isWASI)
        #expect(!TargetTriple.wasmWASI.isWasmJS)
        #expect(TargetTriple.wasmJS.isWasm)
        #expect(TargetTriple.wasmJS.isWasmJS)
        #expect(!TargetTriple.wasmJS.isWASI)
        #expect(!TargetTriple.hostDefault().isWasm)
        #expect(TargetTriple(arch: "wasm32", vendor: "unknown", os: "wasip1", osVersion: nil).isWASI)
        #expect(TargetTriple(arch: "wasm32", vendor: "unknown", os: "wasi-p2", osVersion: nil).isWASI)
    }

    private func makeHelloModule() -> (KIRModule, SymbolID) {
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let s = arena.appendExpr(.unit)
        let strExpr = KIRExprKind.stringLiteral(interner.intern("wasm hello"))
        let call = KIRInstruction.call(callee: interner.intern("__kk_println_raw"), arguments: [s], result: nil, canThrow: false)
        let body: [KIRInstruction] = [
            .constValue(result: s, value: strExpr),
            call,
            .returnUnit,
        ]
        let function = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])],
            arena: arena
        )
        return (module, mainSymbol)
    }

    @Test
    func emitsValidModuleSkeleton() throws {
        let (module, entry) = makeHelloModule()
        let diagnostics = DiagnosticEngine()
        let result = try WasmEmitter().emitModule(
            module: module,
            interner: interner,
            symbols: nil,
            types: nil,
            entrySymbol: entry,
            target: .wasmWASI,
            diagnostics: diagnostics
        )
        #expect(!diagnostics.hasError)
        // Magic + version.
        #expect(Array(result.bytes[0..<8]) == [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00])
        let text = String(decoding: result.bytes, as: UTF8.self)
        #expect(text.contains("_start"))
        #expect(text.contains("main"))
        #expect(text.contains("fd_write"))
        #expect(text.contains("proc_exit"))
        #expect(text.contains("$__kk_println_raw"))
    }

    @Test
    func emitsLoopAndBranchIntervals() throws {
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let i = arena.appendExpr(.unit)
        let one = arena.appendExpr(.unit)
        let sum = arena.appendExpr(.unit)
        let cond = arena.appendExpr(.unit)
        let three = arena.appendExpr(.unit)
        let loop: Int32 = 10
        let done: Int32 = 11
        let body: [KIRInstruction] = [
            .constValue(result: i, value: .intLiteral(0)),
            .constValue(result: sum, value: .intLiteral(0)),
            .label(loop),
            .binary(op: .add, lhs: i, rhs: one, result: i),
            .binary(op: .equal, lhs: i, rhs: three, result: cond),
            .constValue(result: one, value: .intLiteral(1)),
            .constValue(result: three, value: .intLiteral(3)),
            .jumpIfEqual(lhs: cond, rhs: one, target: done),
            .jump(loop),
            .label(done),
            .returnUnit,
        ]
        let function = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])],
            arena: arena
        )
        let diagnostics = DiagnosticEngine()
        let result = try WasmEmitter().emitModule(
            module: module,
            interner: interner,
            symbols: nil,
            types: nil,
            entrySymbol: mainSymbol,
            target: .wasmWASI,
            diagnostics: diagnostics
        )
        #expect(!diagnostics.hasError)
        #expect(Array(result.bytes[0..<8]) == [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00])
    }

    @Test
    func stubsUnresolvedCalleesAndReports() throws {
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let arg = arena.appendExpr(.unit)
        let body: [KIRInstruction] = [
            .constValue(result: arg, value: .intLiteral(1)),
            .call(
                callee: interner.intern("kk_some_missing_runtime_fn"),
                arguments: [arg],
                result: nil,
                canThrow: false
            ),
            .returnUnit,
        ]
        let function = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])],
            arena: arena
        )
        let diagnostics = DiagnosticEngine()
        let result = try WasmEmitter().emitModule(
            module: module,
            interner: interner,
            symbols: nil,
            types: nil,
            entrySymbol: mainSymbol,
            target: .wasmWASI,
            diagnostics: diagnostics
        )
        #expect(!diagnostics.hasError)
        #expect(result.stubbedCallees.contains("kk_some_missing_runtime_fn"))
    }

    private func nodePath() -> String? {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in env.split(separator: ":") {
            let candidate = "\(dir)/node"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    @Test
    func runsHelloUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let (module, entry) = makeHelloModule()
        let bytes = try emit(module, entry: entry)
        let run = try runUnderNode(bytes)
        #expect(run?.status == 0)
        #expect(run?.stdout.contains("wasm hello") == true)
    }

    func emit(_ module: KIRModule, entry: SymbolID) throws -> [UInt8] {
        let diagnostics = DiagnosticEngine()
        let result = try WasmEmitter().emitModule(
            module: module,
            interner: interner,
            symbols: nil,
            types: nil,
            entrySymbol: entry,
            target: .wasmWASI,
            diagnostics: diagnostics
        )
        #expect(!diagnostics.hasError)
        return result.bytes
    }

    func runUnderNode(_ bytes: [UInt8]) throws -> (stdout: String, stderr: String, status: Int32)? {
        guard let node = nodePath() else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wasm-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wasmPath = dir.appendingPathComponent("test.wasm").path
        let runnerPath = dir.appendingPathComponent("run.mjs").path
        try Data(bytes).write(to: URL(fileURLWithPath: wasmPath))
        let runner = """
        import { WASI } from "node:wasi";
        import fs from "node:fs";
        const wasi = new WASI({ version: "preview1", args: [], env: {}, returnOnExit: true });
        const { instance } = await WebAssembly.instantiate(
          fs.readFileSync(process.argv[2]),
          { wasi_snapshot_preview1: wasi.wasiImport }
        );
        process.exit(wasi.start(instance) ?? 0);
        """
        try runner.write(toFile: runnerPath, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [runnerPath, wasmPath]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (stdout, stderr, process.terminationStatus)
    }

    private func makeFunction(
        symbol: SymbolID,
        name: String,
        params: [KIRParameter],
        body: [KIRInstruction]
    ) -> KIRFunction {
        KIRFunction(
            symbol: symbol,
            name: interner.intern(name),
            params: params,
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )
    }

    private func println(_ callee: InternedString, _ arg: KIRExprID) -> KIRInstruction {
        .call(
            symbol: nil,
            callee: callee,
            arguments: [arg],
            result: nil,
            canThrow: false,
            thrownResult: nil
        )
    }

    @Test
    func runsObjectFieldsAndIsCheckUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let words = e(), typeID = e(), obj = e(), slot = e(), value = e()
        let field = e(), s1 = e(), child = e(), parent = e()
        let token = e(), isResult = e(), s2 = e()
        let nominalToken = Int64(200) << 9 | 6
        let body: [KIRInstruction] = [
            .constValue(result: words, value: .intLiteral(3)),
            .constValue(result: typeID, value: .intLiteral(100)),
            .call(symbol: nil, callee: interner.intern("kk_object_new"),
                  arguments: [words, typeID], result: obj,
                  canThrow: false, thrownResult: nil),
            .constValue(result: slot, value: .intLiteral(2)),
            .constValue(result: value, value: .intLiteral(42)),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [obj, slot, value], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_get_inbounds"),
                  arguments: [obj, slot], result: field,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [field], result: s1,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s1),
            .constValue(result: child, value: .intLiteral(100)),
            .constValue(result: parent, value: .intLiteral(200)),
            .call(symbol: nil, callee: interner.intern("kk_type_register_super"),
                  arguments: [child, parent], result: nil,
                  canThrow: false, thrownResult: nil),
            .constValue(result: token, value: .intLiteral(nominalToken)),
            .call(symbol: nil, callee: interner.intern("kk_op_is"),
                  arguments: [obj, token], result: isResult,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [isResult], result: s2,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s2),
            .returnUnit,
        ]
        let function = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout.contains("42") == true)
        #expect(run?.stdout.contains("1") == true)
    }

    @Test
    func runsVirtualDispatchUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let targetSymbol = SymbolID(rawValue: 2)
        let paramSymbol = SymbolID(rawValue: 3)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let seven = e(.intLiteral(7))
        let target = makeFunction(
            symbol: targetSymbol,
            name: "target",
            params: [KIRParameter(symbol: paramSymbol, type: TypeID(rawValue: 0))],
            body: [.constValue(result: seven, value: .intLiteral(7)), .returnValue(seven)]
        )
        let words = e(), typeID = e(), obj = e(), slot = e(), fref = e()
        let r = e(), s = e()
        let body: [KIRInstruction] = [
            .constValue(result: words, value: .intLiteral(3)),
            .constValue(result: typeID, value: .intLiteral(100)),
            .call(symbol: nil, callee: interner.intern("kk_object_new"),
                  arguments: [words, typeID], result: obj,
                  canThrow: false, thrownResult: nil),
            .constValue(result: slot, value: .intLiteral(0)),
            .constValue(result: fref, value: .symbolRef(targetSymbol)),
            .call(symbol: nil, callee: interner.intern("kk_object_register_vtable_method"),
                  arguments: [obj, slot, fref], result: nil,
                  canThrow: false, thrownResult: nil),
            .virtualCall(symbol: nil, callee: interner.intern("target"),
                         receiver: obj, arguments: [], result: r,
                         canThrow: false, thrownResult: nil, dispatch: .vtable(slot: 0)),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [r], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .returnUnit,
        ]
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let d1 = arena.appendDecl(.function(main))
        let d2 = arena.appendDecl(.function(target))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [d1, d2])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout.contains("7") == true)
    }

    @Test
    func runsThrowCatchUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let boomSymbol = SymbolID(rawValue: 2)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let msg = e(), exc = e()
        let boom = makeFunction(
            symbol: boomSymbol,
            name: "boom",
            params: [],
            body: [
                .constValue(result: msg, value: .stringLiteral(interner.intern("x"))),
                .call(symbol: nil, callee: interner.intern("__kk_exception_new_message"),
                      arguments: [msg], result: exc,
                      canThrow: false, thrownResult: nil),
                .rethrow(value: exc),
            ]
        )
        let ret = e(), slot = e(), sMiss = e(), sCaught = e(), sAfter = e()
        let catchLabel: Int32 = 50, doneLabel: Int32 = 51
        let body: [KIRInstruction] = [
            .call(symbol: nil, callee: interner.intern("boom"),
                  arguments: [], result: ret,
                  canThrow: true, thrownResult: slot),
            .jumpIfNotNull(value: slot, target: catchLabel),
            .constValue(result: sMiss, value: .stringLiteral(interner.intern("miss"))),
            println(interner.intern("__kk_println_raw"), sMiss),
            .jump(doneLabel),
            .label(catchLabel),
            .constValue(result: sCaught, value: .stringLiteral(interner.intern("caught"))),
            println(interner.intern("__kk_println_raw"), sCaught),
            .label(doneLabel),
            .constValue(result: sAfter, value: .stringLiteral(interner.intern("after"))),
            println(interner.intern("__kk_println_raw"), sAfter),
            .returnUnit,
        ]
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let d1 = arena.appendDecl(.function(main))
        let d2 = arena.appendDecl(.function(boom))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [d1, d2])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout.contains("caught") == true)
        #expect(run?.stdout.contains("after") == true)
    }

    @Test
    func runsArrayIntrinsicsUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let count = e(), arr = e(), idx = e(), value = e(), packed = e()
        let elem = e(), s1 = e(), size = e(), s2 = e()
        let body: [KIRInstruction] = [
            .constValue(result: count, value: .intLiteral(3)),
            .call(symbol: nil, callee: interner.intern("kk_array_new"),
                  arguments: [count], result: arr,
                  canThrow: false, thrownResult: nil),
            .constValue(result: idx, value: .intLiteral(1)),
            .constValue(result: value, value: .intLiteral(8)),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [arr, idx, value], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_of"),
                  arguments: [arr, count], result: packed,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_get"),
                  arguments: [packed, idx], result: elem,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [elem], result: s1,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s1),
            .call(symbol: nil, callee: interner.intern("__kk_array_size"),
                  arguments: [packed], result: size,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [size], result: s2,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s2),
            .returnUnit,
        ]
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout.contains("8") == true)
        #expect(run?.stdout.contains("3") == true)
    }

    @Test
    func reportsUncaughtExceptionOnStderrUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let msg = e(), exc = e()
        let main = makeFunction(
            symbol: mainSymbol,
            name: "main",
            params: [],
            body: [
                .constValue(result: msg, value: .stringLiteral(interner.intern("kaboom"))),
                .call(symbol: nil, callee: interner.intern("__kk_exception_new_message"),
                      arguments: [msg], result: exc,
                      canThrow: false, thrownResult: nil),
                .rethrow(value: exc),
            ]
        )
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 70)
        #expect(run?.stderr.contains("Uncaught Kotlin exception: kotlin.Exception: kaboom") == true)
    }

    @Test
    func runsListIntrinsicsUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let zero = e(), one = e(), two = e(), three = e(), packed = e()
        let list = e(), addOk = e(), size = e(), s1 = e(), idx = e(), elem = e(), s2 = e()
        let iter = e(), hasNext = e(), falseE = e(), next = e(), s3 = e()
        let loop: Int32 = 60, done: Int32 = 61
        let body: [KIRInstruction] = [
            .constValue(result: two, value: .intLiteral(2)),
            .call(symbol: nil, callee: interner.intern("kk_array_new"),
                  arguments: [two], result: packed,
                  canThrow: false, thrownResult: nil),
            .constValue(result: zero, value: .intLiteral(0)),
            .constValue(result: one, value: .intLiteral(1)),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [packed, zero, one], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [packed, one, two], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_array_list_of"),
                  arguments: [packed, two], result: list,
                  canThrow: false, thrownResult: nil),
            .constValue(result: three, value: .intLiteral(3)),
            .call(symbol: nil, callee: interner.intern("__kk_mutable_list_add"),
                  arguments: [list, three], result: addOk,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_list_size"),
                  arguments: [list], result: size,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [size], result: s1,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s1),
            .constValue(result: idx, value: .intLiteral(1)),
            .call(symbol: nil, callee: interner.intern("__kk_list_get"),
                  arguments: [list, idx], result: elem,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [elem], result: s2,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s2),
            .call(symbol: nil, callee: interner.intern("kk_list_iterator"),
                  arguments: [list], result: iter,
                  canThrow: false, thrownResult: nil),
            .label(loop),
            .call(symbol: nil, callee: interner.intern("kk_list_iterator_hasNext"),
                  arguments: [iter], result: hasNext,
                  canThrow: false, thrownResult: nil),
            .constValue(result: falseE, value: .boolLiteral(false)),
            .jumpIfEqual(lhs: hasNext, rhs: falseE, target: done),
            .call(symbol: nil, callee: interner.intern("kk_list_iterator_next"),
                  arguments: [iter], result: next,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [next], result: s3,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s3),
            .jump(loop),
            .label(done),
            .returnUnit,
        ]
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "3\n2\n1\n2\n3\n")
    }

    @Test
    func runsMapSetIntrinsicsUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let zero = e(), one = e(), two = e(), three = e(), seven = e(), nine = e()
        let keys = e(), vals = e(), map = e(), size = e(), got = e(), s = e()
        let setElems = e(), set = e(), ok = e(), setSize = e(), c1 = e(), c2 = e()
        let iter = e(), hasNext = e(), falseE = e(), entry = e()
        let entK = e(), entV = e(), sk = e(), sv = e(), ss = e(), sc = e()
        let loop: Int32 = 60, done: Int32 = 61
        let body: [KIRInstruction] = [
            .constValue(result: one, value: .intLiteral(1)),
            .call(symbol: nil, callee: interner.intern("kk_array_new"),
                  arguments: [one], result: keys,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_new"),
                  arguments: [one], result: vals,
                  canThrow: false, thrownResult: nil),
            .constValue(result: zero, value: .intLiteral(0)),
            .constValue(result: seven, value: .intLiteral(7)),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [keys, zero, one], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [vals, zero, seven], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_linked_hash_map_of"),
                  arguments: [keys, vals, one], result: map,
                  canThrow: false, thrownResult: nil),
            .constValue(result: two, value: .intLiteral(2)),
            .constValue(result: nine, value: .intLiteral(9)),
            .call(symbol: nil, callee: interner.intern("__kk_mutable_map_put"),
                  arguments: [map, two, nine], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_map_size"),
                  arguments: [map], result: size,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [size], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .call(symbol: nil, callee: interner.intern("__kk_map_get"),
                  arguments: [map, two], result: got,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [got], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .call(symbol: nil, callee: interner.intern("__kk_mutable_map_iterator"),
                  arguments: [map], result: iter,
                  canThrow: false, thrownResult: nil),
            .label(loop),
            .call(symbol: nil, callee: interner.intern("kk_iterator_hasNext"),
                  arguments: [iter], result: hasNext,
                  canThrow: false, thrownResult: nil),
            .constValue(result: falseE, value: .boolLiteral(false)),
            .jumpIfEqual(lhs: hasNext, rhs: falseE, target: done),
            .call(symbol: nil, callee: interner.intern("kk_iterator_next"),
                  arguments: [iter], result: entry,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_pair_first"),
                  arguments: [entry], result: entK,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_pair_second"),
                  arguments: [entry], result: entV,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [entK], result: sk,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), sk),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [entV], result: sv,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), sv),
            .jump(loop),
            .label(done),
            .constValue(result: three, value: .intLiteral(3)),
            .call(symbol: nil, callee: interner.intern("kk_array_new"),
                  arguments: [three], result: setElems,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [setElems, zero, one], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [setElems, one, two], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [setElems, two, two], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_linked_hash_set_of"),
                  arguments: [setElems, three], result: set,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_mutable_set_add"),
                  arguments: [set, three], result: ok,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_set_size"),
                  arguments: [set], result: setSize,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [setSize], result: ss,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), ss),
            .call(symbol: nil, callee: interner.intern("__kk_set_contains"),
                  arguments: [set, two], result: c1,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [c1], result: sc,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), sc),
            .call(symbol: nil, callee: interner.intern("__kk_set_contains"),
                  arguments: [set, nine], result: c2,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [c2], result: sc,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), sc),
            .returnUnit,
        ]
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "2\n9\n1\n7\n2\n9\n3\n1\n0\n")
    }

    @Test
    func runsRangeIntrinsicsUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let zero = e(), one = e(), two = e(), three = e(), four = e(), five = e()
        let charA = e(), charC = e(), tagChar = e()
        let range1 = e(), range2 = e(), range3 = e(), range4 = e(), stepped = e()
        let iter = e(), hasNext = e(), falseE = e(), v = e(), s = e()
        let first = e(), last = e(), list = e(), size = e(), sum = e(), le = e()
        let loop1: Int32 = 70, done1: Int32 = 71
        let loop2: Int32 = 72, done2: Int32 = 73
        let loop3: Int32 = 74, done3: Int32 = 75
        let loop4: Int32 = 76, done4: Int32 = 77
        func rangeLoop(_ rangeExpr: KIRExprID, loop: Int32, done: Int32,
                       taggedChar: Bool = false) -> [KIRInstruction] {
            var ins: [KIRInstruction] = [
                .call(symbol: nil, callee: interner.intern("__kk_range_for_in_iterator"),
                      arguments: [rangeExpr], result: iter,
                      canThrow: false, thrownResult: nil),
                .label(loop),
                .call(symbol: nil, callee: interner.intern("__kk_range_for_in_hasNext"),
                      arguments: [iter], result: hasNext,
                      canThrow: false, thrownResult: nil),
                .constValue(result: falseE, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: hasNext, rhs: falseE, target: done),
                .call(symbol: nil, callee: interner.intern("__kk_range_for_in_next"),
                      arguments: [iter], result: v,
                      canThrow: false, thrownResult: nil),
            ]
            if taggedChar {
                ins.append(contentsOf: [
                    .constValue(result: tagChar, value: .intLiteral(4)),
                    .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                          arguments: [v, tagChar], result: s,
                          canThrow: false, thrownResult: nil),
                ])
            } else {
                ins.append(.call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                                 arguments: [v], result: s,
                                 canThrow: false, thrownResult: nil))
            }
            ins.append(contentsOf: [
                println(interner.intern("__kk_println_raw"), s),
                .jump(loop),
                .label(done),
            ])
            return ins
        }
        var body: [KIRInstruction] = [
            .constValue(result: one, value: .intLiteral(1)),
            .constValue(result: five, value: .intLiteral(5)),
            .call(symbol: nil, callee: interner.intern("__kk_op_rangeTo"),
                  arguments: [one, five], result: range1,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_range_first"),
                  arguments: [range1], result: first,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [first], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .call(symbol: nil, callee: interner.intern("__kk_range_last"),
                  arguments: [range1], result: last,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [last], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
        ]
        body.append(contentsOf: rangeLoop(range1, loop: loop1, done: done1))
        body.append(contentsOf: [
            .constValue(result: two, value: .intLiteral(2)),
            .call(symbol: nil, callee: interner.intern("__kk_op_downTo"),
                  arguments: [five, one], result: range2,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_op_step"),
                  arguments: [range2, two], result: stepped,
                  canThrow: false, thrownResult: nil),
        ])
        body.append(contentsOf: rangeLoop(stepped, loop: loop2, done: done2))
        body.append(contentsOf: [
            .constValue(result: zero, value: .intLiteral(0)),
            .constValue(result: three, value: .intLiteral(3)),
            .call(symbol: nil, callee: interner.intern("__kk_op_rangeUntil"),
                  arguments: [zero, three], result: range3,
                  canThrow: false, thrownResult: nil),
        ])
        body.append(contentsOf: rangeLoop(range3, loop: loop3, done: done3))
        body.append(contentsOf: [
            .constValue(result: charA, value: .charLiteral(97)),
            .constValue(result: charC, value: .charLiteral(99)),
            .call(symbol: nil, callee: interner.intern("__kk_char_rangeTo"),
                  arguments: [charA, charC], result: range4,
                  canThrow: false, thrownResult: nil),
        ])
        body.append(contentsOf: rangeLoop(range4, loop: loop4, done: done4, taggedChar: true))
        body.append(contentsOf: [
            .constValue(result: four, value: .intLiteral(4)),
            .call(symbol: nil, callee: interner.intern("__kk_op_rangeTo"),
                  arguments: [one, four], result: range1,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_range_to_list"),
                  arguments: [range1], result: list,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_list_size"),
                  arguments: [list], result: size,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [size], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .call(symbol: nil, callee: interner.intern("__kk_int_range_induction_add"),
                  arguments: [three, two], result: sum,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [sum], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .call(symbol: nil, callee: interner.intern("__kk_int_range_induction_le"),
                  arguments: [three, five], result: le,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [le], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .returnUnit,
        ])
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "1\n5\n1\n2\n3\n4\n5\n5\n3\n1\n0\n1\n2\na\nb\nc\n4\n5\n1\n")
    }

    @Test
    func runsCollectionHOFIntrinsicsUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let zero = e(), one = e(), two = e(), three = e(), seven = e(), eight = e()
        let arr = e(), list = e(), idx = e(), s = e()
        let sep = e(), prefix = e(), postfix = e(), mask = e(), joined = e()
        let strA = e(), strB = e(), strHi = e(), tag1 = e()
        let setArr = e(), set = e()
        let body: [KIRInstruction] = [
            .constValue(result: three, value: .intLiteral(3)),
            .call(symbol: nil, callee: interner.intern("kk_array_new"),
                  arguments: [three], result: arr,
                  canThrow: false, thrownResult: nil),
            .constValue(result: zero, value: .intLiteral(0)),
            .constValue(result: one, value: .intLiteral(1)),
            .constValue(result: two, value: .intLiteral(2)),
            .constValue(result: seven, value: .intLiteral(7)),
            .constValue(result: eight, value: .intLiteral(8)),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [arr, zero, seven], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [arr, one, eight], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [arr, two, eight], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_list_of"),
                  arguments: [arr, three], result: list,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_list_index_of"),
                  arguments: [list, eight], result: idx,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [idx], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .call(symbol: nil, callee: interner.intern("__kk_list_last_index_of"),
                  arguments: [list, eight], result: idx,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [idx], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .virtualCall(symbol: nil, callee: interner.intern("indexOf"),
                         receiver: list, arguments: [eight], result: idx,
                         canThrow: false, thrownResult: nil,
                         dispatch: .itableDynamic(
                            interfaceTypeID: 21424414924382307, methodSlot: 6)),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [idx], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .constValue(result: sep, value: .stringLiteral(interner.intern("-"))),
            .constValue(result: prefix, value: .stringLiteral(interner.intern("["))),
            .constValue(result: postfix, value: .stringLiteral(interner.intern("]"))),
            .call(symbol: nil, callee: interner.intern("__kk_string_joinToString"),
                  arguments: [list, sep, prefix, postfix], result: joined,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), joined),
            // The symbol-less `$default` forwarder routes by name; the real
            // calling convention is (recv, sep, prefix, postfix, limit,
            // truncated, transform, mask) — mask=63 defaults every param,
            // so zero args pick the Kotlin defaults.
            .constValue(result: mask, value: .intLiteral(63)),
            .call(symbol: nil, callee: interner.intern("joinToString$default"),
                  arguments: [list, zero, zero, zero, zero, zero, zero, mask], result: joined,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), joined),
            .constValue(result: two, value: .intLiteral(2)),
            .call(symbol: nil, callee: interner.intern("kk_array_new"),
                  arguments: [two], result: setArr,
                  canThrow: false, thrownResult: nil),
            .constValue(result: strA, value: .stringLiteral(interner.intern("a"))),
            .constValue(result: strB, value: .stringLiteral(interner.intern("b"))),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [setArr, zero, strA], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("kk_array_set"),
                  arguments: [setArr, one, strB], result: nil,
                  canThrow: false, thrownResult: nil),
            .call(symbol: nil, callee: interner.intern("__kk_set_of"),
                  arguments: [setArr, two], result: set,
                  canThrow: false, thrownResult: nil),
            .constValue(result: sep, value: .stringLiteral(interner.intern("+"))),
            .call(symbol: nil, callee: interner.intern("__kk_string_joinToString"),
                  arguments: [set, sep, zero, zero], result: joined,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), joined),
            .constValue(result: strHi, value: .stringLiteral(interner.intern("hi"))),
            .constValue(result: tag1, value: .intLiteral(1)),
            .call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                  arguments: [strHi, tag1], result: s,
                  canThrow: false, thrownResult: nil),
            println(interner.intern("__kk_println_raw"), s),
            .returnUnit,
        ]
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "1\n2\n1\n[7-8-8]\n7, 8, 8\na+b\nhi\n")
    }

    @Test
    func runsFloatingPointIntrinsicsUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let pi = e(), third = e(), rem = e(), half = e(), negZero = e()
        let negHalf = e(), big = e(), eq = e(), fsum = e(), toInt = e()
        let toDbl = e(), box = e(), tag = e(), tagBool = e()
        var body: [KIRInstruction] = []
        body.append(.constValue(result: tag, value: .intLiteral(1)))
        body.append(.constValue(result: tagBool, value: .intLiteral(2)))
        func printValue(_ v: KIRExprID, _ t: KIRExprID) {
            let s = e()
            body.append(.call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                              arguments: [v, t], result: s,
                              canThrow: false, thrownResult: nil))
            body.append(println(interner.intern("__kk_println_raw"), s))
        }
        body.append(.constValue(result: pi, value: .doubleLiteral(3.14)))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_double_nonnull"),
                          arguments: [pi], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.constValue(result: third, value: .doubleLiteral(3.0)))
        body.append(.call(symbol: nil, callee: interner.intern("kk_op_ddiv"),
                          arguments: [e(.doubleLiteral(1.0)), third], result: rem,
                          canThrow: false, thrownResult: nil))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_double_nonnull"),
                          arguments: [rem], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.call(symbol: nil, callee: interner.intern("kk_op_dmod"),
                          arguments: [e(.doubleLiteral(10.0)), third], result: rem,
                          canThrow: false, thrownResult: nil))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_double_nonnull"),
                          arguments: [rem], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.constValue(result: half, value: .floatLiteral(1.5)))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_float"),
                          arguments: [half], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.constValue(result: negZero, value: .doubleLiteral(-0.0)))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_double_nonnull"),
                          arguments: [negZero], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.call(symbol: nil, callee: interner.intern("kk_op_dmul"),
                          arguments: [e(.doubleLiteral(0.5)), e(.doubleLiteral(-1.0))], result: negHalf,
                          canThrow: false, thrownResult: nil))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_double_nonnull"),
                          arguments: [negHalf], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.constValue(result: big, value: .doubleLiteral(1e10)))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_double_nonnull"),
                          arguments: [big], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.call(symbol: nil, callee: interner.intern("kk_op_deq"),
                          arguments: [e(.doubleLiteral(1.5)), e(.doubleLiteral(1.5))], result: eq,
                          canThrow: false, thrownResult: nil))
        printValue(eq, tagBool)
        body.append(.call(symbol: nil, callee: interner.intern("kk_op_fadd"),
                          arguments: [e(.floatLiteral(2.5)), e(.floatLiteral(0.25))], result: fsum,
                          canThrow: false, thrownResult: nil))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_float"),
                          arguments: [fsum], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.call(symbol: nil, callee: interner.intern("__kk_double_to_int"),
                          arguments: [e(.doubleLiteral(2.7))], result: toInt,
                          canThrow: false, thrownResult: nil))
        printValue(toInt, tag)
        body.append(.call(symbol: nil, callee: interner.intern("kk_int_to_double"),
                          arguments: [e(.intLiteral(3))], result: toDbl,
                          canThrow: false, thrownResult: nil))
        body.append(.call(symbol: nil, callee: interner.intern("kk_box_double_nonnull"),
                          arguments: [toDbl], result: box,
                          canThrow: false, thrownResult: nil))
        printValue(box, tag)
        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "3.14\n0.3333333333333333\n1.0\n1.5\n-0.0\n-0.5\n1.0E10\ntrue\n2.75\n2\n3.0\n")
    }

    @Test
    func runsStringHelpersUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        var body: [KIRInstruction] = []
        func lit(_ s: String) -> KIRExprID { e(.stringLiteral(interner.intern(s))) }
        func int(_ v: Int64) -> KIRExprID { e(.intLiteral(v)) }
        func call(_ name: String, _ args: [KIRExprID]) -> KIRExprID {
            let r = e()
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: args, result: r,
                              canThrow: false, thrownResult: nil))
            return r
        }
        func printStr(_ name: String, _ args: [KIRExprID]) {
            body.append(println(interner.intern("__kk_println_raw"), call(name, args)))
        }
        func printInt(_ v: KIRExprID) {
            let s = e()
            body.append(.call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                              arguments: [v, int(1)], result: s,
                              canThrow: false, thrownResult: nil))
            body.append(println(interner.intern("__kk_println_raw"), s))
        }
        printStr("__kk_wasm_string_upper", [lit("Hello")])
        printStr("__kk_wasm_string_lower", [lit("HeLLo")])
        printStr("__kk_wasm_string_substring_to", [lit("Hello World"), int(0), int(5)])
        printStr("__kk_wasm_string_repeat", [lit("ab"), int(3)])
        printStr("__kk_wasm_string_trim", [lit("  pad  ")])
        printInt(call("__kk_wasm_string_index_of", [lit("Hello"), lit("ll"), int(0), int(0)]))
        printInt(call("__kk_wasm_string_last_index_of_nostart", [lit("Hello"), lit("l")]))
        printInt(call("__kk_wasm_string_contains_ic", [lit("Hello"), lit("ELL"), int(1)]))
        printInt(call("__kk_wasm_string_starts_with", [lit("Hello"), lit("He"), int(0)]))
        printInt(call("__kk_wasm_string_ends_with", [lit("Hello"), lit("lo"), int(0)]))
        printStr("__kk_wasm_string_replace", [lit("Hello"), lit("l"), lit("L"), int(0)])
        printStr("__kk_wasm_string_replace_first", [lit("Hello"), lit("l"), lit("L"), int(0)])
        printStr("__kk_wasm_string_replace_char", [lit("Hello"), int(0x6C), int(0x4C), int(0)])
        printStr("__kk_wasm_string_reversed", [lit("abc")])
        printInt(call("__kk_wasm_string_is_blank", [lit("  ")]))
        let list = call("__kk_wasm_string_split", [lit("a,b,c"), lit(",")])
        printInt(call("__kk_list_size", [list]))
        // substring(0, 10) on "abc" throws StringIndexOutOfBoundsException —
        // declared under `java.lang` in the bundled stdlib, so the catch
        // token's nominal payload must hash that fqName, not `kotlin.*`.
        let slot = e(), isMatch = e(), caught = e(), sMiss = e()
        let catchLabel: Int32 = 60, doneLabel: Int32 = 61
        body.append(.call(symbol: nil, callee: interner.intern("__kk_wasm_string_substring_to"),
                          arguments: [lit("abc"), int(0), int(10)], result: e(),
                          canThrow: true, thrownResult: slot))
        body.append(.jumpIfNotNull(value: slot, target: catchLabel))
        body.append(.constValue(result: sMiss, value: .stringLiteral(interner.intern("miss"))))
        body.append(println(interner.intern("__kk_println_raw"), sMiss))
        body.append(.jump(doneLabel))
        body.append(.label(catchLabel))
        body.append(.call(symbol: nil, callee: interner.intern("kk_op_is"),
                          arguments: [slot, int(7_519_185_036_922_649_094)], result: isMatch,
                          canThrow: false, thrownResult: nil))
        body.append(.constValue(result: caught, value: .stringLiteral(interner.intern("SIOOB"))))
        body.append(println(interner.intern("__kk_println_raw"), caught))
        body.append(.label(doneLabel))
        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "HELLO\nhello\nHello\nababab\npad\n2\n3\n1\n1\n1\nHeLLo\nHeLlo\nHeLLo\ncba\n1\n3\nSIOOB\n")
    }

    @Test
    func runsStructuralEqualityAndTextHelpersUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        var body: [KIRInstruction] = []
        func lit(_ s: String) -> KIRExprID { e(.stringLiteral(interner.intern(s))) }
        func int(_ v: Int64) -> KIRExprID { e(.intLiteral(v)) }
        func call(_ name: String, _ args: [KIRExprID]) -> KIRExprID {
            let r = e()
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: args, result: r,
                              canThrow: false, thrownResult: nil))
            return r
        }
        func printInt(_ v: KIRExprID) {
            let s = e()
            body.append(.call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                              arguments: [v, int(1)], result: s,
                              canThrow: false, thrownResult: nil))
            body.append(println(interner.intern("__kk_println_raw"), s))
        }
        func printStr(_ v: KIRExprID) {
            body.append(println(interner.intern("__kk_println_raw"), v))
        }
        func listOf(_ elems: [KIRExprID]) -> KIRExprID {
            let arr = call("kk_array_new", [int(Int64(elems.count))])
            for (i, v) in elems.enumerated() {
                _ = call("kk_array_set", [arr, int(Int64(i)), v])
            }
            return call("__kk_list_of", [arr, int(Int64(elems.count))])
        }
        func setOf(_ elems: [KIRExprID]) -> KIRExprID {
            let arr = call("kk_array_new", [int(Int64(elems.count))])
            for (i, v) in elems.enumerated() {
                _ = call("kk_array_set", [arr, int(Int64(i)), v])
            }
            return call("__kk_set_of", [arr, int(Int64(elems.count))])
        }
        func boxOf(_ helper: String, _ elems: [KIRExprID]) -> KIRExprID {
            let arr = call("kk_array_new", [int(Int64(elems.count))])
            for (i, v) in elems.enumerated() {
                _ = call("kk_array_set", [arr, int(Int64(i)), v])
            }
            return call(helper, [arr, int(Int64(elems.count))])
        }
        let nullS = int(Int64.min)
        let l12 = listOf([int(1), int(2)])
        let l12b = listOf([int(1), int(2)])
        let l21 = listOf([int(2), int(1)])
        let l123 = listOf([int(1), int(2), int(3)])
        let s12 = setOf([int(1), int(2)])
        let s21 = setOf([int(2), int(1)])
        let s13 = setOf([int(1), int(3)])
        let lAB = listOf([lit("a"), lit("b")])
        let lABb = listOf([lit("a"), lit("b")])
        let lNested = listOf([l12]), lNestedB = listOf([l12b])
        let al12 = boxOf("__kk_array_list_of", [int(1), int(2)])
        let lhs21 = boxOf("__kk_linked_hash_set_of", [int(2), int(1)])
        printInt(call("kk_structural_eq", [l12, l12b]))
        printInt(call("kk_structural_eq", [s12, s21]))
        printInt(call("kk_structural_eq", [s12, s13]))
        printInt(call("kk_structural_eq", [s12, l12]))
        printInt(call("kk_structural_eq", [l12, l21]))
        printInt(call("kk_structural_eq", [lAB, lABb]))
        printInt(call("kk_structural_eq", [lNested, lNestedB]))
        printInt(call("kk_structural_eq", [l12, l123]))
        printInt(call("kk_structural_eq", [nullS, nullS]))
        printInt(call("kk_structural_eq", [l12, nullS]))
        printInt(call("kk_structural_ne", [l12, l12b]))
        printInt(call("kk_structural_eq", [l12, al12]))
        printInt(call("kk_structural_eq", [s12, lhs21]))
        let clobbered = boxOf("__kk_linked_hash_set_of", [int(2), int(1)])
        for slot in [Int64(16), Int64(17)] {
            let symRef = e()
            body.append(.constValue(result: symRef,
                                    value: .symbolRef(SymbolID(rawValue: 999_999))))
            _ = call("kk_object_register_vtable_method", [clobbered, int(slot), symRef])
        }
        printStr(call("kk_any_member_to_string", [clobbered]))
        printInt(call("kk_any_member_hashCode", [clobbered]))
        printInt(call("kk_any_member_equals", [l12, al12]))
        let dbl = call("__kk_string_toDouble_flat", [lit("3.5")])
        let ds = e()
        body.append(.call(symbol: nil, callee: interner.intern("kk_any_to_string"),
                          arguments: [dbl, int(6)], result: ds,
                          canThrow: false, thrownResult: nil))
        printStr(ds)
        printInt(call("kk_structural_eq",
                      [call("__kk_string_toDoubleOrNull_flat", [lit("x")]), nullS]))
        printInt(call("__kk_string_toInt_flat", [lit("42")]))
        printInt(call("__kk_wasm_string_to_boolean", [lit("true")]))
        printStr(call("__kk_wasm_string_substring_after_char",
                      [lit("a=b=c"), int(0x3D)]))
        printStr(call("__kk_wasm_string_substring_before_last_char",
                      [lit("a=b=c"), int(0x3D)]))
        printInt(call("__kk_list_size",
                      [call("__kk_wasm_string_lines", [lit("a\nb\nc")])]))
        let slot = e(), caught = e(), sMiss = e()
        let catchLabel: Int32 = 70, doneLabel: Int32 = 71
        body.append(.call(symbol: nil, callee: interner.intern("__kk_wasm_todo"),
                          arguments: [lit("later")], result: e(),
                          canThrow: true, thrownResult: slot))
        body.append(.jumpIfNotNull(value: slot, target: catchLabel))
        body.append(.constValue(result: sMiss, value: .stringLiteral(interner.intern("miss"))))
        body.append(println(interner.intern("__kk_println_raw"), sMiss))
        body.append(.jump(doneLabel))
        body.append(.label(catchLabel))
        body.append(.call(symbol: nil, callee: interner.intern("__kk_throwable_toString"),
                          arguments: [slot], result: caught,
                          canThrow: false, thrownResult: nil))
        body.append(println(interner.intern("__kk_println_raw"), caught))
        body.append(.label(doneLabel))
        let slot2 = e(), caught2 = e()
        let catch2Label: Int32 = 72, done2Label: Int32 = 73
        body.append(.call(symbol: nil, callee: interner.intern("__kk_wasm_error"),
                          arguments: [lit("boom")], result: e(),
                          canThrow: true, thrownResult: slot2))
        body.append(.jumpIfNotNull(value: slot2, target: catch2Label))
        body.append(.constValue(result: sMiss, value: .stringLiteral(interner.intern("miss"))))
        body.append(println(interner.intern("__kk_println_raw"), sMiss))
        body.append(.jump(done2Label))
        body.append(.label(catch2Label))
        body.append(.call(symbol: nil, callee: interner.intern("__kk_throwable_toString"),
                          arguments: [slot2], result: caught2,
                          canThrow: false, thrownResult: nil))
        body.append(println(interner.intern("__kk_println_raw"), caught2))
        body.append(.label(done2Label))
        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "1\n1\n0\n0\n0\n1\n1\n0\n1\n0\n0\n1\n1\n[2, 1]\n3\n1\n3.5\n1\n42\n1\nb=c\na=b\n3\nkotlin.NotImplementedError: An operation is not implemented: later\nkotlin.IllegalStateException: boom\n")
    }

    @Test
    func runsListViewAndConcurrentModificationChecksUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        var body: [KIRInstruction] = []
        func const(_ v: Int64) -> KIRExprID {
            let id = e()
            body.append(.constValue(result: id, value: .intLiteral(v)))
            return id
        }
        func slit(_ s: String) -> KIRExprID {
            let id = e()
            body.append(.constValue(
                result: id, value: .stringLiteral(interner.intern(s))
            ))
            return id
        }
        func call(_ name: String, _ args: [KIRExprID],
                  result: KIRExprID? = nil,
                  canThrow: Bool = false, thrown: KIRExprID? = nil) {
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: args, result: result,
                              canThrow: canThrow, thrownResult: thrown))
        }
        let arr = e(), list = e(), iter = e(), iter2 = e()
        let view = e(), view2 = e(), got = e(), str = e()
        let cmeSlot = e(), nseeSlot = e(), viewSlot = e(), caught = e()
        let n3 = const(3), n4 = const(4), n9 = const(9)
        let n0 = const(0), n1 = const(1), n2 = const(2)
        call("kk_array_new", [n3], result: arr)
        for i in 0..<3 {
            call("kk_array_set", [arr, const(Int64(i)), const(Int64(i + 1))])
        }
        call("__kk_array_list_of", [arr, n3], result: list)
        call("kk_list_iterator", [list], result: iter)
        call("kk_list_iterator_next", [iter])
        call("__kk_mutable_list_add", [list, n4])
        call("kk_list_iterator_next", [iter], result: e(),
             canThrow: true, thrown: cmeSlot)
        let cmeL: Int32 = 90, cmeDone: Int32 = 91
        body.append(.jumpIfNotNull(value: cmeSlot, target: cmeL))
        call("__kk_println_raw", [slit("miss")])
        body.append(.jump(cmeDone))
        body.append(.label(cmeL))
        call("__kk_throwable_toString", [cmeSlot], result: caught)
        call("__kk_println_raw", [caught])
        body.append(.label(cmeDone))
        call("kk_list_iterator", [list], result: iter2)
        for _ in 0..<4 { call("kk_list_iterator_next", [iter2]) }
        call("kk_list_iterator_next", [iter2], result: e(),
             canThrow: true, thrown: nseeSlot)
        let nseeL: Int32 = 92, nseeDone: Int32 = 93
        body.append(.jumpIfNotNull(value: nseeSlot, target: nseeL))
        call("__kk_println_raw", [slit("miss")])
        body.append(.jump(nseeDone))
        body.append(.label(nseeL))
        call("__kk_throwable_toString", [nseeSlot], result: caught)
        call("__kk_println_raw", [caught])
        body.append(.label(nseeDone))
        call("kk_list_subList", [list, n0, n2], result: view)
        call("__kk_list_get", [view, n0], result: got)
        call("kk_any_to_string", [got], result: str)
        call("__kk_println_raw", [str])
        call("__kk_set_size", [view], result: got)
        call("kk_any_to_string", [got], result: str)
        call("__kk_println_raw", [str])
        call("__kk_mutable_list_add", [list, n9])
        call("__kk_list_check_modification", [view],
             canThrow: true, thrown: viewSlot)
        let vcL: Int32 = 94, vcDone: Int32 = 95
        body.append(.jumpIfNotNull(value: viewSlot, target: vcL))
        call("__kk_println_raw", [slit("miss")])
        body.append(.jump(vcDone))
        body.append(.label(vcL))
        call("__kk_throwable_toString", [viewSlot], result: caught)
        call("__kk_println_raw", [caught])
        body.append(.label(vcDone))
        call("kk_list_subList", [list, n1, n3], result: view2)
        call("__kk_list_get", [view2, n1], result: got)
        call("kk_any_to_string", [got], result: str)
        call("__kk_println_raw", [str])
        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout ==
            "kotlin.ConcurrentModificationException\n"
                + "kotlin.NoSuchElementException\n"
                + "1\n2\n"
                + "kotlin.ConcurrentModificationException\n"
                + "3\n")
    }

    @Test
    func growsItableIfaceMapPastInitialCapacityUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        var body: [KIRInstruction] = []
        func const(_ v: Int64) -> KIRExprID {
            let id = e()
            body.append(.constValue(result: id, value: .intLiteral(v)))
            return id
        }
        func call(_ name: String, _ args: [KIRExprID], result: KIRExprID? = nil) {
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: args, result: result,
                              canThrow: false, thrownResult: nil))
        }
        let obj = e(), got = e(), str = e()
        call("kk_object_new", [const(4), const(4242)], result: obj)
        for i in 0..<Int64(10) {
            call("kk_object_register_itable_iface", [obj, const(5000 + i), const(i)])
            call("kk_object_register_itable_method", [obj, const(i), const(0), const(700 + i)])
        }
        call("__kk_wasm_itable_lookup", [obj, const(5000), const(0)], result: got)
        call("kk_any_to_string", [got], result: str)
        call("__kk_println_raw", [str])
        call("__kk_wasm_itable_lookup", [obj, const(5009), const(0)], result: got)
        call("kk_any_to_string", [got], result: str)
        call("__kk_println_raw", [str])
        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let declID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "700\n709\n")
    }

    @Test
    func dispatchesRegisteredAnyOverridesUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let toStrSymbol = SymbolID(rawValue: 2)
        let eqSymbol = SymbolID(rawValue: 3)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        var toStrBody: [KIRInstruction] = []
        let s = e()
        toStrBody.append(.constValue(result: s, value: .stringLiteral(interner.intern("OVR"))))
        toStrBody.append(.returnValue(s))
        var eqBody: [KIRInstruction] = []
        let one = e()
        eqBody.append(.constValue(result: one, value: .intLiteral(1)))
        eqBody.append(.returnValue(one))
        var body: [KIRInstruction] = []
        func const(_ v: Int64) -> KIRExprID {
            let id = e()
            body.append(.constValue(result: id, value: .intLiteral(v)))
            return id
        }
        func call(_ name: String, _ args: [KIRExprID], result: KIRExprID? = nil) {
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: args, result: result,
                              canThrow: false, thrownResult: nil))
        }
        let obj = e(), str = e(), eqRes = e()
        let toStrRef = e(), eqRef = e()
        call("kk_object_new", [const(4), const(4242)], result: obj)
        body.append(.constValue(result: toStrRef, value: .symbolRef(toStrSymbol)))
        body.append(.constValue(result: eqRef, value: .symbolRef(eqSymbol)))
        call("kk_object_register_any_to_string", [obj, toStrRef])
        call("kk_object_register_equals_override", [obj, eqRef])
        call("kk_any_to_string", [obj], result: str)
        call("__kk_println_raw", [str])
        call("kk_any_member_equals", [obj, const(7)], result: eqRes)
        call("kk_any_to_string", [eqRes], result: str)
        call("__kk_println_raw", [str])
        body.append(.returnUnit)
        let decls = [
            arena.appendDecl(.function(
                makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
            )),
            arena.appendDecl(.function(
                makeFunction(
                    symbol: toStrSymbol, name: "objToString",
                    params: [KIRParameter(symbol: SymbolID(rawValue: 10), type: TypeID(rawValue: 0))],
                    body: toStrBody
                )
            )),
            arena.appendDecl(.function(
                makeFunction(
                    symbol: eqSymbol, name: "objEquals",
                    params: [
                        KIRParameter(symbol: SymbolID(rawValue: 11), type: TypeID(rawValue: 0)),
                        KIRParameter(symbol: SymbolID(rawValue: 12), type: TypeID(rawValue: 0)),
                    ],
                    body: eqBody
                )
            )),
        ]
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: decls)],
            arena: arena
        )
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "OVR\n1\n")
    }

    @Test
    func runsCharSequenceItableAndWidePrimitiveIsUnderNodeWASI() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        func e(_ kind: KIRExprKind = .unit) -> KIRExprID { arena.appendExpr(kind) }
        let str = e(), len = e(), idx = e(), ch = e()
        let isChar = e(), isLong = e()
        let csID = WasmRuntimeHelpers.stableNominalTypeID("kotlin.CharSequence")
        var body: [KIRInstruction] = []
        func const(_ v: Int64) -> KIRExprID {
            let id = e()
            body.append(.constValue(result: id, value: .intLiteral(v)))
            return id
        }
        func call(_ name: String, _ args: [KIRExprID], result: KIRExprID? = nil) {
            body.append(.call(symbol: nil, callee: interner.intern(name),
                              arguments: args, result: result,
                              canThrow: false, thrownResult: nil))
        }
        func printRaw(_ arg: KIRExprID) {
            call("__kk_println_raw", [arg])
        }
        func printViaToString(_ arg: KIRExprID) {
            let s = e()
            call("kk_any_to_string", [arg], result: s)
            printRaw(s)
        }
        body.append(.constValue(result: str, value: .stringLiteral(interner.intern("BC|AD"))))
        // CharSequence.length (itable slot 2) on a flat String → 5.
        body.append(.virtualCall(
            symbol: nil, callee: interner.intern("length"),
            receiver: str, arguments: [], result: len,
            canThrow: false, thrownResult: nil,
            dispatch: .itableDynamic(interfaceTypeID: csID, methodSlot: 2)
        ))
        printViaToString(len)
        // CharSequence.get (itable slot 0) → 'C' = 67.
        body.append(.constValue(result: idx, value: .intLiteral(1)))
        body.append(.virtualCall(
            symbol: nil, callee: interner.intern("get"),
            receiver: str, arguments: [idx], result: ch,
            canThrow: false, thrownResult: nil,
            dispatch: .itableDynamic(interfaceTypeID: csID, methodSlot: 0)
        ))
        printViaToString(ch)
        call("kk_op_is", [const(67), const(14 | 0x100)], result: isChar)
        printViaToString(isChar)
        call("kk_op_is", [const(5), const(11)], result: isLong)
        printViaToString(isLong)
        body.append(.returnUnit)
        let main = makeFunction(symbol: mainSymbol, name: "main", params: [], body: body)
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [arena.appendDecl(.function(main))])],
            arena: arena
        )
        let run = try runUnderNode(try emit(module, entry: mainSymbol))
        #expect(run?.status == 0)
        #expect(run?.stdout == "5\n67\n1\n1\n")
    }
}
