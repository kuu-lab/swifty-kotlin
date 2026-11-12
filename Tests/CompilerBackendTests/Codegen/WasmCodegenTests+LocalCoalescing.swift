@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct WasmLocalCoalescingTests {
    private func parseMaxCodeSectionLocalCount(wasm bytes: [UInt8]) -> UInt64 {
        var idx = 8 // skip \0asm + version
        func readULEB() -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while idx < bytes.count {
                let b = bytes[idx]
                idx += 1
                result |= UInt64(b & 0x7F) << shift
                if (b & 0x80) == 0 { return result }
                shift += 7
            }
            return result
        }

        var maxLocals: UInt64 = 0
        while idx < bytes.count {
            let sectionID = bytes[idx]
            idx += 1
            let sectionSize = Int(readULEB())
            let sectionEnd = idx + sectionSize
            if sectionID == 10 {
                let count = Int(readULEB())
                for _ in 0..<count {
                    let bodySize = Int(readULEB())
                    let bodyStart = idx
                    let declGroups = Int(readULEB())
                    var locals: UInt64 = 0
                    for _ in 0..<declGroups {
                        locals += readULEB()
                        idx += 1 // valtype
                    }
                    maxLocals = max(maxLocals, locals)
                    idx = bodyStart + bodySize
                }
            }
            idx = sectionEnd
        }
        return maxLocals
    }

    @Test
    func straightLineHighExpressionCountCoalescesLocalsBelowWasmLimit() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let helperSymbol = SymbolID(rawValue: 2)

        // Helper: fun id(x: Int): Int = x
        let pSym = SymbolID(rawValue: 3)
        let pExpr = arena.appendExpr(.symbolRef(pSym))
        let helperFn = KIRFunction(
            symbol: helperSymbol,
            name: interner.intern("id"),
            params: [KIRParameter(symbol: pSym, type: TypeID(rawValue: 0))],
            returnType: TypeID(rawValue: 0),
            body: [.returnValue(pExpr)],
            isSuspend: false,
            isInline: false
        )

        // Main: 55,000 sequential const + call steps (110,000 assigned KIRExprIDs),
        // which overflows WebAssembly's 50,000-local limit without local coalescing.
        let one = arena.appendExpr(.intLiteral(1))
        let acc = arena.appendExpr(.unit)
        var body: [KIRInstruction] = [
            .constValue(result: acc, value: .intLiteral(0)),
        ]
        body.reserveCapacity(110_010)
        for _ in 0..<55_000 {
            let step = arena.appendExpr(.unit)
            let tmp = arena.appendExpr(.unit)
            body.append(.constValue(result: step, value: .intLiteral(1)))
            body.append(.call(symbol: helperSymbol, callee: interner.intern("id"), arguments: [step], result: tmp, canThrow: false))
            body.append(.binary(op: .add, lhs: acc, rhs: tmp, result: acc))
        }
        _ = one
        body.append(.call(callee: interner.intern("kk_println_any"), arguments: [acc], result: nil, canThrow: false))
        body.append(.returnUnit)

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )

        let declMain = arena.appendDecl(.function(mainFn))
        let declHelper = arena.appendDecl(.function(helperFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declHelper, declMain])],
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
        let maxLocals = parseMaxCodeSectionLocalCount(wasm: result.bytes)
        #expect(maxLocals < 100)
    }

    @Test
    func loopCarriedAndConditionalLocalsRemainDistinctUnderCoalescing() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)

        // Loop accumulating sum over 0..<4 while keeping a conditional flag
        // defined before and overwritten inside an if-branch within the loop.
        let i = arena.appendExpr(.unit)
        let acc = arena.appendExpr(.unit)
        let bonus = arena.appendExpr(.unit)
        let limit = arena.appendExpr(.intLiteral(4))
        let zero = arena.appendExpr(.intLiteral(0))
        let one = arena.appendExpr(.intLiteral(1))
        let two = arena.appendExpr(.intLiteral(2))
        let cond = arena.appendExpr(.unit)
        let isEqZero = arena.appendExpr(.unit)
        let scratchTmp = arena.appendExpr(.unit)

        let loopStart: Int32 = 10
        let loopExit: Int32 = 20
        let skipSet: Int32 = 30

        let body: [KIRInstruction] = [
            .constValue(result: i, value: .intLiteral(0)),
            .constValue(result: acc, value: .intLiteral(0)),
            .constValue(result: bonus, value: .intLiteral(10)),
            .label(loopStart),
            .binary(op: .lessThan, lhs: i, rhs: limit, result: cond),
            .jumpIfEqual(lhs: cond, rhs: zero, target: loopExit),
            .binary(op: .equal, lhs: i, rhs: two, result: isEqZero),
            .jumpIfEqual(lhs: isEqZero, rhs: zero, target: skipSet),
            .constValue(result: bonus, value: .intLiteral(100)),
            .label(skipSet),
            .binary(op: .add, lhs: acc, rhs: bonus, result: acc),
            .constValue(result: scratchTmp, value: .intLiteral(999)),
            .binary(op: .add, lhs: i, rhs: one, result: i),
            .jump(loopStart),
            .label(loopExit),
            .call(callee: interner.intern("kk_any_to_string"), arguments: [acc], result: scratchTmp, canThrow: false),
            .call(callee: interner.intern("__kk_println_raw"), arguments: [scratchTmp], result: nil, canThrow: false),
            .returnUnit,
        ]
        _ = scratchTmp

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )
        let declMain = arena.appendDecl(.function(mainFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declMain])],
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

        // If node is available, run and verify expected sum: 10 + 10 + 100 + 100 = 220
        let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        if let nodePath = searchDirs.map({ "\($0)/node" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("wasm-coalesce-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let wasmPath = dir.appendingPathComponent("test.wasm").path
            let runnerPath = dir.appendingPathComponent("run.mjs").path
            try Data(result.bytes).write(to: URL(fileURLWithPath: wasmPath))
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
            process.executableURL = URL(fileURLWithPath: nodePath)
            process.arguments = [runnerPath, wasmPath]
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            try process.run()
            process.waitUntilExit()
            let stdout = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            #expect(process.terminationStatus == 0, "stderr: \(stderr)")
            #expect(stdout == "220\n")
        }
    }
}
