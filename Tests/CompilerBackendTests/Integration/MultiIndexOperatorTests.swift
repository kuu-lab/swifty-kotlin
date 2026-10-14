@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct MultiIndexOperatorTests {
    @Test
    func inapplicableSetMemberAllowsMultiIndexExtensions() throws {
        let source = """
        class Slots {
            operator fun set(index: Int, value: Int) {}
        }
        operator fun Slots.set(index: Int, value: Int) {}
        operator fun Slots.set(a: Int, b: Int, value: Int) {}
        operator fun Slots.set(a: Int, b: Int, c: Int, value: Int) {}
        class NumericSlots {
            operator fun set(index: Int, value: Int) {}
        }
        operator fun NumericSlots.set(a: Long, b: UInt, value: Byte) {}
        fun single(slots: Slots) { slots[1] = 7 }
        fun double(slots: Slots) { slots[1, 2] = 7 }
        fun triple(slots: Slots) { slots[1, 2, 3] = 7 }
        fun numeric(slots: NumericSlots) { slots[1, 2u] = 3 }
        """
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = CompilerTestSupport.makeCompilationContext(
            inputs: [input], includeStdlib: false, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: input, contents: Data(source.utf8))
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        for (name, argumentCount) in [("single", 3), ("double", 4), ("triple", 5), ("numeric", 4)] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (SymbolID, [KIRExprID])? in
                guard case let .call(symbol?, callee, arguments, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "set" else { return nil }
                return (symbol, arguments)
            }
            #expect(calls.count == 1)
            let call = try #require(calls.first)
            #expect(call.1.count == argumentCount)
            let callee = try #require(sema.symbols.symbol(call.0))
            // Receiver attachment preserves a top-level extension's FQ name.
            #expect(callee.fqName.map { ctx.interner.resolve($0) }
                == (name == "single" ? ["Slots", "set"] : ["set"]))
            #expect(!extractCallees(from: body, interner: ctx.interner).contains("kk_array_set"))
            if name == "numeric" {
                #expect(call.1.dropFirst().map { module.arena.exprType($0) } == [
                    sema.types.longType, sema.types.uintType, sema.types.byteType,
                ])
            }
        }
    }

    @Test(arguments: [true, false], [0, 2])
    func multiIndexGetSet(fromSource: Bool, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let input = repository.appendingPathComponent("Scripts/diff_cases/multi_index_get_set.kt").path
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("multi-index").path
        let options = CompilerOptions(
            moduleName: "MultiIndexOperators",
            inputs: [input], outputPath: output,
            emit: .executable, target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "fromSource=\(fromSource), O\(optimization): \(result.stderr)")
        #expect(result.stderr.isEmpty, "fromSource=\(fromSource), O\(optimization): \(result.stderr)")
        #expect(result.stdout == "\nc\nB\nB\nC\nf\nE\n30\n21\n",
                "fromSource=\(fromSource), O\(optimization): \(result.stdout)")
    }
}
