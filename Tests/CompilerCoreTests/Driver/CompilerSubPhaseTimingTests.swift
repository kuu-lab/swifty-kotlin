@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CompilerSubPhaseTimingTests {
    @Test(arguments: [false, true])
    func testSemaAndLoweringTimingPreservesKIRAndPassOrder(includeStdlib: Bool) throws {
        try withTemporaryFile(contents: "fun twice(x: Int): Int = x * 2\nfun main(): Int = twice(21)") { path in
            let plain = makeCompilationContext(inputs: [path], includeStdlib: includeStdlib)
            let timed = makeCompilationContext(inputs: [path], includeStdlib: includeStdlib)
            let timer = PhaseTimer()
            timed.installPhaseTimer(timer)
            for ctx in [plain, timed] {
                try runFrontend(ctx)
                ctx.phaseTimer?.beginPhase(SemaPhase.name)
                try SemaPhase().run(ctx)
                ctx.phaseTimer?.endPhase()
                try BuildKIRPhase().run(ctx)
                ctx.phaseTimer?.beginPhase(LoweringPhase.name)
                try LoweringPhase().run(ctx)
                ctx.phaseTimer?.endPhase()
                #expect(!ctx.diagnostics.hasError)
            }
            let sema = try #require(timer.phaseRecords.first { $0.name == SemaPhase.name })
            #expect(sema.subRecords.map(\.name) == ["DataFlowSema", "TypeCheckSema"])
            let dataFlow = sema.subRecords[0]
            for name in ["loadImports", "mergeImportedStdlibSymbolsIntoBundledIndex", "registerSyntheticDelegateStubs",
                         "collectAllHeaders", "runValidationPasses", "runBodyAnalysis"] {
                #expect(dataFlow.subRecords.contains { $0.name == name })
            }
            let validations = try #require(dataFlow.subRecords.first { $0.name == "runValidationPasses" })
            #expect(validations.subRecords.contains { $0.name == "validateTypeAliasCycles" })
            #expect(validations.subRecords.contains { $0.name == "synthesizeNominalLayouts" })
            let lowered = try #require(timed.kir)
            let lowerings = try #require(timer.phaseRecords.first { $0.name == LoweringPhase.name })
            #expect(lowerings.subRecords.map(\.name) == LoweringPhase.makeDefaultPasses().map { type(of: $0).name })
            #expect(lowerings.subRecords.map(\.name) == lowered.executedLowerings)
            #expect(lowered.dump(interner: timed.interner, symbols: timed.sema?.symbols) == plain.kir?.dump(interner: plain.interner, symbols: plain.sema?.symbols))
        }
    }

    @Test
    func testIndexedImportTimingKeepsMaterializationLazyAndAttributesItToActivePhase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"{"formatVersion":1,"moduleName":"TimedImport","metadata":"metadata.bin"}"#
            .write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let records = ["first", "second"].map { name in
            MetadataRecord(kind: .function, mangledName: "_KK_" + name, fqName: "timed." + name,
                           arity: 0, typeSignature: "F0<I>")
        }
        try MetadataEncoder().serializeIndexed(records)
            .write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let ctx = makeCompilationContext(inputs: [], searchPaths: [directory.path], includeStdlib: false)
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let timer = PhaseTimer()
        timer.beginPhase("Sema")
        _ = withSubPhaseTiming("loadImports", timer: timer) {
            DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types, diagnostics: ctx.diagnostics,
                interner: ctx.interner, importedInlineFunctions: ImportedInlineFunctionStore(), phaseTimer: timer
            )
        }
        timer.endPhase()
        #expect(!ctx.diagnostics.hasError)
        let imports = timer.phaseRecords[0].subRecords[0]
        #expect(imports.subRecords.map(\.name) == ["indexDecode", "registerShells"])
        #expect(!timer.phaseRecords[0].subRecords.contains { $0.name == "imports.lazyMaterialize" })
        timer.beginPhase("BuildKIR")
        for name in ["first", "second"] {
            let symbol = try #require(symbols.lookup(fqName: ["timed", name].map(ctx.interner.intern)))
            #expect(symbols.functionSignature(for: symbol)?.returnType == types.intType)
        }
        timer.endPhase()
        #expect(timer.phaseRecords[1].subRecords.map(\.name) == ["imports.lazyMaterialize"])
    }

    @Test
    func testKIRDumpIsTimedAsItsOwnPhase() throws {
        try withTemporaryFile(contents: "fun main(): Int = 42") { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output + ".kir") }
            let ctx = makeCompilationContext(inputs: [path], outputPath: output, includeStdlib: false)
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)
            try runFrontend(ctx)
            try SemaPhase().run(ctx)
            try BuildKIRPhase().run(ctx)
            try LoweringPhase().run(ctx)
            CompilerDriver().emitKIRDump(ctx: ctx)
            #expect(!ctx.diagnostics.hasError)
            let dump = try #require(timer.phaseRecords.first { $0.name == "KIRDump" })
            #expect(dump.subRecords.map(\.name) == ["render", "write"])
            #expect(FileManager.default.fileExists(atPath: output + ".kir"))
        }
    }
}
