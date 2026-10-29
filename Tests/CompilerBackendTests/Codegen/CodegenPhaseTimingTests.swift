#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenPhaseTimingTests {
    @Test(arguments: [false, true])
    func runtimeProjectionPreservesSerializedMetadata(includeNonPublic: Bool) throws {
        let source = """
        interface Named { fun value(): Int }
        open class Base(val n: Int)
        class Child(n: Int): Base(n), Named { override fun value(): Int = n }
        data class Pair<T>(val first: T, var second: Int)
        sealed class Event
        class Changed: Event()
        @JvmInline value class Count(val value: Int)
        inline fun identity(x: Int): Int = x
        suspend fun suspended(x: Int): Int = x
        fun Int.extension(y: Int): Int = this + y
        internal class Hidden
        private fun secret(): Int = 9
        enum class Mode { FIRST, SECOND }
        object Singleton { val value: Int = 1 }
        annotation class Mark
        @Mark class Marked
        fun overloaded(x: Int): Int = x
        fun overloaded(x: String): String = x
        """
        // Supply the Enum header because this fixture omits bundled stdlib.
        let enumHeader = "package kotlin\nabstract class Enum<T : Enum<T>> protected constructor(name: String, ordinal: Int)"
        try withTemporaryFile(contents: source) { path in
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "ProjectionProbe", inputs: [path], outputPath: "unused",
                    emit: .llvmIR, target: TargetTriple.hostDefault(), includeStdlib: false
                ),
                sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            // Bundled virtual paths permit the nominal shell to be reused.
            // Keep this header in memory so LoadSources need not read it.
            _ = ctx.sourceManager.addFile(
                path: "__bundled_projection_Enum.kt", contents: Data(enumHeader.utf8), origin: .bundledStdlib
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let kir = try #require(ctx.kir)
            let inlineSymbols = Set(kir.arena.declarations.compactMap { declaration -> SymbolID? in
                guard case let .function(function) = declaration, function.isInline else { return nil }
                return function.symbol
            })
            let encoder = MetadataEncoder()
            let projected = encoder.buildRecords(
                symbols: sema.symbols, types: sema.types, moduleName: "ProjectionProbe",
                interner: ctx.interner, functionLinkNames: [:], inlineFunctionSymbols: inlineSymbols,
                includeNonPublic: includeNonPublic, runtimeReflectionOnly: true
            )
            let full = encoder.buildRecords(
                symbols: sema.symbols, types: sema.types, moduleName: "ProjectionProbe",
                interner: ctx.interner, functionLinkNames: [:], inlineFunctionSymbols: inlineSymbols,
                includeNonPublic: includeNonPublic
            )
            #expect(full.count == projected.count)
            #expect(RuntimeReflectionMetadataEmitter.serialize(full) == RuntimeReflectionMetadataEmitter.serialize(projected))
            #expect(full.contains { $0.fqName == "identity" && $0.isInline && $0.typeSignature != nil && !$0.mangledName.isEmpty })
            #expect(projected.contains { $0.fqName == "suspended" && $0.isSuspend && $0.arity == 1 })
            #expect(projected.contains { $0.fqName == "Pair" && $0.isDataClass && $0.declaredFieldCount != nil })
            #expect(projected.contains { $0.fqName == "Event" && $0.isSealedClass })
            #expect(projected.contains { $0.fqName == "Count" && $0.isValueClass })
            #expect(projected.contains { $0.fqName == "Mode" && $0.kind == .enumClass })
            #expect(projected.contains { $0.fqName == "Singleton" && $0.kind == .object })
            #expect(projected.contains { $0.fqName == "Mark" && $0.kind == .annotationClass })
            #expect(projected.filter { $0.fqName == "overloaded" }.count == 2)
            #expect(projected.contains { $0.fqName == "Child" && $0.superFQName?.contains("Base") == true })
            #expect(projected.contains { $0.fqName == "Hidden" } == includeNonPublic)
            #expect(projected.contains { $0.fqName == "secret" } == includeNonPublic)
        }
    }

    @Test(arguments: ["object", "llvmIR", "library"], [0, 2])
    func recordsEmissionStagesWithoutChangingIR(modeName: String, optimizationValue: Int) throws {
        let mode = try #require(EmitMode(rawValue: modeName))
        let optimization = try #require(OptimizationLevel(rawValue: optimizationValue))
        try withTemporaryFile(contents: "fun answer(): Int = 42") { sourcePath in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let outputPath = directory.appendingPathComponent("output").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "TimingProbe", inputs: [sourcePath], outputPath: outputPath,
                    emit: mode, target: TargetTriple.hostDefault(), optLevel: optimization, includeStdlib: false
                ),
                sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)
            timer.beginPhase("Codegen")
            try CodegenPhase().run(ctx)
            timer.endPhase()
            let phase = try #require(timer.phaseRecords.first)
            func namesIn(_ records: [PhaseTimer.PhaseRecord]) -> [String] {
                records.flatMap { [$0.name] + namesIn($0.subRecords) }
            }
            let names = namesIn(phase.subRecords)
            for name in ["init", "linkInfo", "reflectionRecords", "initEmitter", "emit", "IR/reflection globals"] {
                #expect(names.contains(name))
            }
            if mode != .llvmIR {
                #expect(names.contains("initTarget"))
                #expect(names.contains("opt"))
                #expect(names.contains("write"))
                let objectPath = try #require(ctx.generatedObjectPath)
                #expect(FileManager.default.fileExists(atPath: objectPath))
            } else if optimization != .O0 {
                #expect(names.contains("opt"))
            }
            if mode == .library {
                #expect(names.contains("inlineKIRArtifacts"))
            }
            for sub in phase.subRecords {
                #expect(sub.startTime >= phase.startTime)
                #expect(sub.endTime <= phase.endTime)
            }
            if mode == .llvmIR {
                let timedIR = try String(contentsOfFile: outputPath + ".ll", encoding: .utf8)
                // Reuse exactly the same semantic/KIR state without a timer.
                let untimed = CompilationContext(
                    options: ctx.options, sourceManager: ctx.sourceManager,
                    diagnostics: ctx.diagnostics, interner: ctx.interner
                )
                untimed.storeAST(try #require(ctx.ast))
                untimed.storeSema(try #require(ctx.sema))
                untimed.storeKIR(try #require(ctx.kir))
                try CodegenPhase().run(untimed)
                let untimedIR = try String(contentsOfFile: outputPath + ".ll", encoding: .utf8)
                #expect(timedIR == untimedIR)
            }
        }
    }

    @Test
    func runtimeProjectionPreservesImportedLibraryRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func context(source: String, name: String, emit: EmitMode, searchPaths: [String] = []) throws -> CompilationContext {
            let sourcePath = directory.appendingPathComponent(name + ".kt").path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: name, inputs: [sourcePath], outputPath: directory.appendingPathComponent(name).path,
                    emit: emit, searchPaths: searchPaths, target: TargetTriple.hostDefault(), includeStdlib: false
                ),
                sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)
            return ctx
        }
        let library = try context(source: "package library\nclass Box<T>(val value: T)", name: "Library", emit: .library)
        try CodegenPhase().run(library)
        let consumer = try context(
            source: "import library.Box\nfun keep(value: Box<Int>): Box<Int> = value",
            name: "Consumer", emit: .llvmIR, searchPaths: [directory.appendingPathComponent("Library.kklib").path]
        )
        let sema = try #require(consumer.sema)
        #expect(sema.symbols.allSymbols().contains { $0.flags.contains(.importedLibrary) })
        let encoder = MetadataEncoder()
        // Exercise the projection before the reference path can load lazy metadata.
        let projected = encoder.buildRecords(
            symbols: sema.symbols, types: sema.types, moduleName: "Consumer",
            interner: consumer.interner, functionLinkNames: [:], runtimeReflectionOnly: true
        )
        // KUU-2675: pending compact-index shells are not reachable from the
        // compiled program, so the projection omits them instead of decoding
        // their bodies.
        for symbol in sema.symbols.allSymbols()
            where symbol.flags.contains(.importedLibrary) && sema.symbols.hasPendingImportedMetadata(for: symbol.id)
        {
            let fqName = symbol.fqName.map { consumer.interner.resolve($0) }.joined(separator: ".")
            #expect(!projected.contains { $0.fqName == fqName })
        }
        // With every imported body materialized, the projection keeps the
        // whole imported surface field-for-field, byte-for-byte. Both paths
        // must run on the same load state: materialization can register
        // member symbols, so a pre-load export sees a smaller symbol table.
        for symbol in sema.symbols.allSymbols() where symbol.flags.contains(.importedLibrary) {
            sema.symbols.ensureLazyImportedMetadataLoaded(for: symbol.id)
        }
        let full = encoder.buildRecords(
            symbols: sema.symbols, types: sema.types, moduleName: "Consumer",
            interner: consumer.interner, functionLinkNames: [:]
        )
        #expect(full.contains { $0.fqName == "library.Box" && $0.nominalTypeParametersSignature != nil })
        let loadedProjected = encoder.buildRecords(
            symbols: sema.symbols, types: sema.types, moduleName: "Consumer",
            interner: consumer.interner, functionLinkNames: [:], runtimeReflectionOnly: true
        )
        #expect(RuntimeReflectionMetadataEmitter.serialize(full) == RuntimeReflectionMetadataEmitter.serialize(loadedProjected))
    }

    @Test
    func entryWrapperRecordsLLVMWorkWithoutChangingObject() throws {
        let session = LLVMBackendSession()
        let bindings = try #require(session.loadBindings())
        #expect(session.loadBindings() === bindings)
        let independentSession = LLVMBackendSession()
        let independentBindings = try #require(independentSession.loadBindings())
        #expect(independentBindings !== bindings)
        // Sharing the library handle must not share mutable LLVM contexts.
        let firstContext = try #require(bindings.createContext())
        defer { bindings.disposeContext(firstContext) }
        let secondContext = try #require(bindings.createContext())
        defer { bindings.disposeContext(secondContext) }
        #expect(firstContext != secondContext)
        let timer = PhaseTimer()
        timer.beginPhase("Link")
        let timedPath = try LLVMEntryPointObjectEmitter(target: TargetTriple.hostDefault(), phaseTimer: timer, session: session)
            .emit(entrySymbol: "probe_entry")
        timer.endPhase()
        defer { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: timedPath).deletingLastPathComponent().path) }
        let untimedPath = try LLVMEntryPointObjectEmitter(target: TargetTriple.hostDefault())
            .emit(entrySymbol: "probe_entry")
        defer { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: untimedPath).deletingLastPathComponent().path) }
        let names = try #require(timer.phaseRecords.first).subRecords.map(\.name)
        #expect(names.contains("entry/backend init"))
        #expect(names.contains("entry/target machine"))
        #expect(names.contains("entry/object write"))
        #expect(names.contains("entry emission"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: timedPath)) == Data(contentsOf: URL(fileURLWithPath: untimedPath)))
    }
}
#endif
