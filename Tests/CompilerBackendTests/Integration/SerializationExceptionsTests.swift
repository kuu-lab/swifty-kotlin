@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct SerializationExceptionsTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_exceptions.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func publicExceptionContractsMatchTheJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("exceptions.kt").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("exceptions").path
        let options = CompilerOptions(
            moduleName: "Exceptions", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func aSeparateLibraryPreservesTheExceptionTypePropertiesAndCause(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        func compile(_ source: String, module: String, emit: EmitMode, libraries: [String] = []) throws -> String {
            let input = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            let options = CompilerOptions(moduleName: module, inputs: [input], outputPath: output,
                                          emit: emit, searchPaths: libraries, target: defaultTargetTriple(),
                                          optLevel: level, stdlibLibraryPath: stdlib)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }
        let library = try compile("""
        @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
        package downstream
        import kotlinx.serialization.*
        fun provideMissing(): SerializationException = MissingFieldException(listOf("first"), "Example")
        fun extractFields(error: MissingFieldException): List<String> = error.missingFields
        fun provideException(cause: Throwable): SerializationException = SerializationException("library", cause)
        """, module: "ExceptionsLibrary", emit: .library)
        let consumer = try fixture("kt").replacingOccurrences(of: "fun main() {", with: """
        fun main() {
            val imported = downstream.provideMissing()
            check(imported is MissingFieldException)
            val typed = imported as MissingFieldException
            check(typed.serialName == "Example")
            check(typed.message == "Field 'first' is required for type with serial name 'Example', but it was missing")
            check(downstream.extractFields(typed) == listOf("first"))
            val origin = IllegalStateException("origin")
            val forwarded = downstream.provideException(origin)
            check(forwarded.message == "library")
            check(forwarded.cause === origin)
        """)
        let output = try compile(consumer, module: "ExceptionsConsumer", emit: .executable, libraries: [library])
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == (try fixture("expected")))
    }

    private func analyze(_ source: String, fromSource: Bool) throws -> CompilationContext {
        let input = "/tmp/serialization-exceptions-\(UUID().uuidString).kt"
        let options = CompilerOptions(moduleName: "ExceptionsSema", inputs: [input], outputPath: "/tmp/exceptions-sema",
                                      emit: .executable, target: defaultTargetTriple(),
                                      stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
                                      allowDefaultStdlibLibrary: !fromSource)
        return CompilerDriver().runFrontend(options: options, inMemorySources: [input: Data(source.utf8)]).context
    }

    @Test(arguments: [false, true], [false, true])
    func missingFieldExceptionRetainsTheExperimentalWarning(fromSource: Bool, optedIn: Bool) throws {
        let source = try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_exceptions_no_optin.kt"), encoding: .utf8)
        let context = try analyze(
            (optedIn ? "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\n" : "") + source,
            fromSource: fromSource
        )
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let warnings = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("ExperimentalSerializationApi")
        }
        #expect(warnings.isEmpty == optedIn)
        #expect(warnings.allSatisfy { $0.severity == .warning })
    }

    @Test(arguments: [false, true])
    func deprecatedCompatibilityConstructorRemainsAnError(fromSource: Bool) throws {
        let context = try analyze("""
        @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
        import kotlinx.serialization.MissingFieldException
        fun bad() = MissingFieldException(listOf("field"), "message", null)
        """, fromSource: fromSource)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-DEPRECATED" && $0.severity == .error
                && $0.message.contains("Use constructor which accepts serialName parameter")
        })
    }

    @Test(arguments: [false, true])
    func privateAndHiddenConstructorsAreUnavailable(fromSource: Bool) throws {
        for source in [
            "MissingFieldException(\"message\", null, listOf(\"field\"), \"Example\")",
            "MissingFieldException(\"field\")",
        ] {
            let context = try analyze("""
            @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
            import kotlinx.serialization.MissingFieldException
            fun bad() = \(source)
            """, fromSource: fromSource)
            #expect(context.diagnostics.hasError, "\(source): \(context.diagnostics.diagnostics)")
        }
        let context = try analyze("fun valid() {}", fromSource: fromSource)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let constructors = sema.symbols.lookupAll(fqName:
            ["kotlinx", "serialization", "MissingFieldException", "<init>"].map(context.interner.intern)
        ).filter { sema.symbols.symbol($0)?.kind == .constructor }
        let hidden = try #require(constructors.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == 1
        })
        #expect(sema.symbols.symbol(hidden)?.visibility == .internal)
        #expect(isHiddenByDeprecatedAnnotation(hidden, symbols: sema.symbols))
        #expect(sema.symbols.annotations(for: hidden).contains { $0.annotationFQName == "kotlin.PublishedApi" })
    }
}
