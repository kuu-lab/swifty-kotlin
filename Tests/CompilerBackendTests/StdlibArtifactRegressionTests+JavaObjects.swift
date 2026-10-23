@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3056: core java.util.Objects helpers must be available from bundled source and artifacts.
    @Test(arguments: [false, true])
    func testJavaObjectsCoreHelpersAcrossSourceAndFreshArtifact(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = try diffCaseSource("java_util_objects_basic.kt", file: #filePath)
        let expected = "true\nfalse\ntrue\nfalse\ntrue\n994\n1\n31\n51\n1\nnull\nfallback\n1\nvalue:2\n1\nrequireNonNull:null\nmissing\ntrue\nfalse\nfalse\ntrue\n0\n1\n20\n"
        try withTemporaryFile(contents: source) { path in
            for level in [OptimizationLevel.O0, .O2] {
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: path,
                    moduleName: "JavaObjectsCoreHelpers",
                    outputPath: output,
                    optLevel: level,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: artifactPath
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(useArtifact) \(level): \(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected, "\(useArtifact) \(level): \(result.stdout)")
            }
        }
    }

    /// KUU-2068: the nullable JVM facade and existing array control must survive
    /// serialization and execute with ordinary equals dispatch at both levels.
    @Test(arguments: [false, true])
    func testJavaObjectsDeepEqualsAcrossSourceAndFreshArtifact(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = try diffCaseSource("java_util_objects_deep_equals.kt", file: #filePath)
        // Kotlin/JVM 2.3.10, JRE 27, -Xjdk-release=17 reference output.
        let expected = "true\nfalse\nfalse\ntrue\ntrue\nfalse\ntrue\nfalse\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\nfalse\nfalse\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\nfalse\ntrue\ntrue\ntrue\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nequals\nnested: equals\n"
        try withTemporaryFile(contents: source) { path in
            for level in [OptimizationLevel.O0, .O2] {
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: path,
                    moduleName: "JavaObjectsDeepEquals",
                    outputPath: output,
                    optLevel: level,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: artifactPath
                )
                try assertNoDiagnosticErrors(context)
                let sema = try #require(context.sema)
                let method = try #require(sema.symbols.lookup(fqName:
                    ["java", "util", "Objects", "deepEquals"].map(context.interner.intern)))
                let signature = try #require(sema.symbols.functionSignature(for: method))
                #expect(signature.parameterTypes == [sema.types.nullableAnyType, sema.types.nullableAnyType])
                #expect(signature.returnType == sema.types.booleanType)
                #expect(signature.typeParameterSymbols.isEmpty)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(useArtifact) \(level): \(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected, "\(useArtifact) \(level): \(result.stdout)")
            }
        }
    }

    @Test(arguments: [false, true])
    func testJavaObjectsDeepEqualsRejectsInvalidCalls(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let invalidCalls = """
        import java.util.Objects
        fun typeArgs() { Objects.deepEquals<Int>(null, null) }
        fun missingArgument() { Objects.deepEquals(null) }
        fun extraArgument() { Objects.deepEquals(null, null, null) }
        fun wrongResult(): String = Objects.deepEquals(null, null)
        """
        let missingImport = "fun missingImport(): Boolean = Objects.deepEquals(null, null)"
        // Separate files retain independent import scopes while sharing one
        // source-stdlib analysis; each invalid declaration must have an error.
        try withTemporaryFile(contents: invalidCalls) { importedPath in
            try withTemporaryFile(contents: missingImport) { unimportedPath in
                let context = makeCompilationContext(
                    inputs: [importedPath, unimportedPath],
                    includeStdlib: !useArtifact,
                    stdlibLibraryPath: artifactPath,
                    allowDefaultStdlibLibrary: false
                )
                do {
                    try runSema(context)
                } catch {
                    // Require diagnostics from each call, not only a pipeline error.
                }
                for (path, lines) in [(importedPath, [2, 3, 4, 5]), (unimportedPath, [1])] {
                    let file = try #require(context.sourceManager.fileID(forPath: path))
                    for line in lines {
                        #expect(context.diagnostics.diagnostics.contains { diagnostic in
                            guard diagnostic.severity == .error,
                                  let range = diagnostic.primaryRange,
                                  range.start.file == file else { return false }
                            return context.sourceManager.lineColumn(of: range.start).line == line
                        }, "Expected rejection at \(path):\(line): \(context.diagnostics.diagnostics)")
                    }
                }
            }
        }
    }
}
