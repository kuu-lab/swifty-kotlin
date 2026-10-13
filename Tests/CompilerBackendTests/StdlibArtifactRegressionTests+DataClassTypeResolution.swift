@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-1933: private library classifiers must not replace consumer types
    /// when componentN and copy signatures are synthesized.
    @Test(arguments: [false, true])
    func testConsumerStateDataClassWithSourceAndFreshArtifact(useArtifact: Bool) throws {
        let artifact = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        package demo
        class State(val value: Int)
        data class Work(val state: State)
        fun main() { println(Work(State(10)).state.value) }
        """
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable, outputPath: output,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "10\n")
            #expect(result.stderr.isEmpty)
        }
    }

    @Test(arguments: ["State", "demo.State", "ImportedState", "Nested.State"])
    func testDataClassSyntheticSignaturesPreserveConsumerTypeScope(typeName: String) throws {
        let artifact = try Self.buildStdlibArtifact()
        let source = """
        package demo
        import demo.State as ImportedState
        class State(val value: Int)
        class Nested { class State(val value: Int) }
        data class Work(val state: \(typeName))
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let expectedFQName = typeName == "Nested.State" ? ["demo", "Nested", "State"] : ["demo", "State"]
            let expected = try #require(sema.symbols.lookup(fqName: expectedFQName.map(ctx.interner.intern)))
            for (member, isCopy) in [("component1", false), ("copy", true)] {
                let symbol = try #require(sema.symbols.lookup(fqName: ["demo", "Work", member].map(ctx.interner.intern)))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let type = try #require(isCopy ? signature.parameterTypes.first : signature.returnType)
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    Issue.record("Expected a nominal type for \(member)")
                    continue
                }
                #expect(classType.classSymbol == expected)
            }
        }
    }

    @Test(arguments: [
        "kotlin.collections.State",
        "kotlin.ranges.IntProgressionIterator",
    ])
    func testQualifiedPrivateAndInternalLibraryTypesRemainInaccessible(typeName: String) throws {
        let artifact = try Self.buildStdlibArtifact()
        let source = """
        package demo
        class State(val value: Int)
        private data class Work(val state: \(typeName))
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let code = typeName == "kotlin.collections.State" ? "KSWIFTK-SEMA-0040" : "KSWIFTK-SEMA-0044"
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == code }, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testNestedDataClassResolvesLexicallyEnclosingState() throws {
        let artifact = try Self.buildStdlibArtifact()
        let source = """
        package demo
        class Day17 {
            private class State(val value: Int)
            private data class Work(val state: State)
            fun value(): Int {
                val (state) = Work(State(10)).copy()
                return state.value
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testLocalDataClassTypeShadowsFileImportAlias() throws {
        let artifact = try Self.buildStdlibArtifact()
        let source = """
        package demo
        import demo.Remote as LocalState
        class Remote(val text: String)
        fun main() {
            class LocalState(val value: Int)
            data class Work(val state: LocalState)
            val copied = Work(LocalState(10)).copy(state = LocalState(20))
            val (state) = copied
            println(state.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
