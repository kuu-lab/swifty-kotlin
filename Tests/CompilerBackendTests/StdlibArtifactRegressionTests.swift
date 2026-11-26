@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct StdlibArtifactRegressionTests {

    private static let sharedArtifactLock = NSLock()

    nonisolated(unsafe) private static var sharedArtifactPath: String?

    static func buildStdlibArtifact() throws -> String {
        sharedArtifactLock.lock()
        defer { sharedArtifactLock.unlock() }

        if let cached = sharedArtifactPath {
            return cached
        }

        let artifactBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let ctx = CompilerTestSupport.makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: artifactBase,
            includeStdlib: true,
            stdlibOnly: true,
            allowDefaultStdlibLibrary: false
        )
        do {
            try runToKIR(ctx)
            try assertNoDiagnosticErrors(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try assertNoDiagnosticErrors(ctx)
        } catch {
            throw CompilerPipelineError.invalidInput(
                "Fresh stdlib artifact build failed: \(error); diagnostics: \(ctx.diagnostics.diagnostics)"
            )
        }

        let artifactPath = artifactBase + ".kklib"
        #expect(FileManager.default.fileExists(atPath: artifactPath), "stdlib artifact directory should be emitted")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/manifest.json"), "stdlib artifact should contain manifest.json")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/metadata.bin"), "stdlib artifact should contain metadata.bin")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/objects"), "stdlib artifact should contain objects directory")
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/inline-kir"), "stdlib artifact should contain inline-kir directory")

        sharedArtifactPath = artifactPath
        return artifactPath
    }

    @Test
    func testRemovedSystemTimeFunctionsAreUnresolvedThroughStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.system.*
        fun main() { println(getTimeMillis() > 0); println(getTimeNanos() > 0) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            do {
                try runSema(ctx)
            } catch {
            }
            let sema = try #require(ctx.sema)
            for name in ["getTimeMillis", "getTimeNanos"] {
                #expect(ctx.diagnostics.diagnostics.contains {
                    $0.severity == .error && $0.message.contains("Unresolved function '\(name)'")
                }, "Expected unresolved removed API, got: \(ctx.diagnostics.diagnostics)")
                let fq = ["kotlin", "system", name].map { ctx.interner.intern($0) }
                #expect(sema.symbols.lookupAll(fqName: fq).isEmpty)
            }
        }
    }

    @Test
    func testBase64NamedCompanionTypeThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val default: Base64.Default = Base64.Default
            val padding: Base64.PaddingOption = Base64.PaddingOption.ABSENT
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "Base64NestedArtifact",
                emit: .kirDump,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testRegularNestedObjectDoesNotUseParentCompanionInitializerForGlobalLinkage() throws {
        let source = """
        open class Base {
            open fun value(): Int = 0
        }

        class ContainerWithNestedObject {
            companion object {
                val companionMarker: Int = 1
            }

            object Nested : Base() {
                override fun value(): Int = 42
            }
        }
        """
        try withTemporaryFile(contents: source) { sourcePath in
            let ctx = makeCompilationContext(inputs: [sourcePath])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let nestedFQName = [
                "ContainerWithNestedObject", "Nested"
            ].map(ctx.interner.intern)
            let parentFQName = ["ContainerWithNestedObject"].map(ctx.interner.intern)
            let nestedSymbol = try #require(sema.symbols.lookup(fqName: nestedFQName))
            let parentSymbol = try #require(sema.symbols.lookup(fqName: parentFQName))
            let nestedLayout = try #require(sema.symbols.nominalLayout(for: nestedSymbol))
            #expect(nestedLayout.vtableSize > 0)
            #expect(sema.symbols.companionObjectSymbol(for: parentSymbol) != nestedSymbol)

            let initializerName = ctx.interner.intern("__test_companion_init")
            let initializer = sema.symbols.define(
                kind: .function,
                name: initializerName,
                fqName: parentFQName + [initializerName],
                declSite: nil,
                visibility: .public
            )
            sema.symbols.setCompanionObjectInitializerSymbol(initializer, for: parentSymbol)

            #expect(
                NativeEmitter.shouldUseWeakImportedObjectGlobalReference(
                    for: nestedSymbol,
                    symbols: sema.symbols
                )
            )

            let objectInitializerName = ctx.interner.intern("__test_object_init")
            let objectInitializer = sema.symbols.define(
                kind: .function,
                name: objectInitializerName,
                fqName: nestedFQName + [objectInitializerName],
                declSite: nil,
                visibility: .public
            )
            sema.symbols.setObjectInitializerSymbol(objectInitializer, for: nestedSymbol)
            #expect(
                !NativeEmitter.shouldUseWeakImportedObjectGlobalReference(
                    for: nestedSymbol,
                    symbols: sema.symbols
                )
            )

            let companionSymbol = try #require(
                sema.symbols.companionObjectSymbol(for: parentSymbol)
            )
            #expect(
                !NativeEmitter.shouldUseWeakImportedObjectGlobalReference(
                    for: companionSymbol,
                    symbols: sema.symbols
                )
            )
        }
    }

    @Test
    func testUuidBasicSharedPathPrintsOk() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
            val nilStr = "00000000-0000-0000-0000-000000000000"

            val parsed = Uuid.parse(uuidStr)
            println("parse roundtrip: ${parsed.toString() == uuidStr}")

            val nil = Uuid.NIL
            println("nil string: ${nil.toString() == nilStr}")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "parse roundtrip: true\nnil string: true\n")
        }
    }

    @Test
    func testSyntheticSingletonObjectSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = try diffCaseSource("system_current_time_millis.kt", file: #filePath)

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "true\ntrue\ntrue\n")
        }
    }

    @Test
    func testSyntheticEnumEntrySharedPathLinks() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val undispatched = launch(start = CoroutineStart.UNDISPATCHED) {
                println("undispatched1")
                yield()
                println("undispatched2")
            }
            println("after launch")
            undispatched.join()
            val lazy = launch(start = CoroutineStart.LAZY) { println("lazy body") }
            println("before join")
            lazy.join()
            println(LazyThreadSafetyMode.NONE.name)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let symbols = try #require(ctx.sema?.symbols)
            let syntheticEntry = try #require(symbols.lookup(fqName: [
                "kotlinx", "coroutines", "CoroutineStart", "UNDISPATCHED"
            ].map(ctx.interner.intern)))
            #expect(NativeEmitter.shouldUseWeakImportedEnumEntryGlobalReference(
                for: syntheticEntry,
                symbols: symbols
            ))
            let sourceEntry = try #require(symbols.lookup(fqName: [
                "kotlin", "LazyThreadSafetyMode", "NONE"
            ].map(ctx.interner.intern)))
            #expect(!NativeEmitter.shouldUseWeakImportedEnumEntryGlobalReference(
                for: sourceEntry,
                symbols: symbols
            ))

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
            undispatched1
            after launch
            undispatched2
            before join
            lazy body
            NONE

            """)
        }
    }

    @Test
    func testStdlibArtifactImportDoesNotEmitLayoutOrStubOverlapWarnings() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            println("ok")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "CleanArtifactImport",
                emit: .kirDump,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            let codes = ctx.diagnostics.diagnostics.map(\.code)
            #expect(
                !codes.contains("KSWIFTK-LIB-0004"),
                "Imported layout should not warn about backingField entries: \(ctx.diagnostics.diagnostics)"
            )
            #expect(
                !codes.contains("KSWIFTK-SEMA-0102"),
                "Imported enum synthesis should not emit stub-overlap warnings: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func testWithContextBlockThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val n = 41
            println(withContext(Dispatchers.Default) { "plain" })
            println(withContext(Dispatchers.Default) { n + 1 })
            val block: suspend CoroutineScope.() -> Int = { n * 2 }
            println(withContext(Dispatchers.Default, block))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(
                !ctx.diagnostics.diagnostics.map(\.code).contains("KSWIFTK-CORO-0004"),
                "withContext block should lower through the launcher ABI: \(ctx.diagnostics.diagnostics)"
            )
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "plain\n42\n82\n")
        }
    }
}
