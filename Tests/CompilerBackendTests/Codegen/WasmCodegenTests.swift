@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

/// Tests for the custom KIR → WebAssembly emitter (wasm32-wasi MVP):
/// module encoding, function-body lowering, WASI imports, and — when a
/// `node` binary with `node:wasi` is available — real execution.
@Suite(.serialized)
struct WasmCodegenTests {
    private let interner = StringInterner()

    // MARK: - Target classification

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

    // MARK: - Module encoding

    private func makeHelloModule() -> (KIRModule, SymbolID) {
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let s = arena.appendExpr(.unit)
        let strExpr = KIRExprKind.stringLiteral(interner.intern("wasm hello"))
        let call = KIRInstruction.call(
            symbol: nil,
            callee: interner.intern("__kk_println_raw"),
            arguments: [s],
            result: nil,
            canThrow: false,
            thrownResult: nil
        )
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
        // sum = 0; i = 0; loop { i += 1; if i == 3 break } ; return
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
                symbol: nil,
                callee: interner.intern("kk_some_missing_runtime_fn"),
                arguments: [arg],
                result: nil,
                canThrow: false,
                thrownResult: nil
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

    // MARK: - End-to-end via node:wasi (conditional)

    /// Locates a `node` binary on PATH; returns nil when unavailable so the
    /// test vacuously passes on machines without Node.
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
        guard let node = nodePath() else { return }
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

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wasm-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wasmPath = dir.appendingPathComponent("test.wasm").path
        let runnerPath = dir.appendingPathComponent("run.mjs").path
        try Data(result.bytes).write(to: URL(fileURLWithPath: wasmPath))
        let runner = """
        import { WASI } from "node:wasi";
        import fs from "node:fs";
        const wasi = new WASI({ version: "preview1", args: [], env: {} });
        const { instance } = await WebAssembly.instantiate(
          fs.readFileSync(process.argv[2]),
          { wasi_snapshot_preview1: wasi.wasiImport }
        );
        wasi.start(instance);
        """
        try runner.write(toFile: runnerPath, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [runnerPath, wasmPath]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        #expect(stdout.contains("wasm hello"))
    }
}
