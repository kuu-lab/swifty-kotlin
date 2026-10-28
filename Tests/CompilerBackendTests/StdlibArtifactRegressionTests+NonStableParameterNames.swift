@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testNonStableParameterNamesAcrossBundledSourceAndFreshKklib() throws {
        let declaration = """
        package kotlin.internal

        internal annotation class NonStableParameterNames

        public class JavaShape {
            @NonStableParameterNames
            public fun getChars(srcBegin: Int, srcEnd: Int, dst: Int, dstBegin: Int) {}

            public fun kotlinMethod(srcBegin: Int, srcEnd: Int, dst: Int, dstBegin: Int) {}
        }
        """
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: artifactDirectory) }
        let artifactPath = try buildNonStableParameterNamesArtifact(declaration, in: artifactDirectory)

        let acceptedCalls = """
        import kotlin.internal.JavaShape

        fun positionalJavaShapeCall() {
            JavaShape().getChars(0, 1, 2, 3)
        }

        fun namedKotlinCall() {
            JavaShape().kotlinMethod(srcBegin = 0, srcEnd = 1, dst = 2, dstBegin = 3)
        }
        """
        let rejectedCall = """
        import kotlin.internal.JavaShape

        fun namedJavaShapeCall() {
            JavaShape().getChars(srcBegin = 0, srcEnd = 1, dst = 2, dstBegin = 3)
        }
        """

        for (surface, libraryPath) in [("bundled source", nil), ("fresh .kklib", artifactPath)] {
            try runNonStableParameterNamesSema(
                source: acceptedCalls,
                surface: surface,
                libraryPath: libraryPath,
                declaration: declaration,
                expectErrors: false
            ) { diagnostics in
                #expect(
                    !diagnostics.hasError,
                    "Positional Java-shaped calls and Kotlin named calls should compile with \(surface): \(diagnostics.diagnostics)"
                )
            }
            try runNonStableParameterNamesSema(
                source: rejectedCall,
                surface: surface,
                libraryPath: libraryPath,
                declaration: declaration,
                expectErrors: true
            ) { diagnostics in
                #expect(
                    diagnostics.hasError,
                    "Named arguments to a Java-shaped declaration should be rejected with \(surface)"
                )
            }
        }
    }
}

private func buildNonStableParameterNamesArtifact(_ declaration: String, in directory: URL) throws -> String {
    var artifactPath: String?
    try withTemporaryFile(contents: declaration) { inputPath in
        let outputBase = directory.appendingPathComponent("KUU3634Stdlib").path
        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: "KSwiftKStdlib",
                inputs: [inputPath],
                outputPath: outputBase,
                emit: .library,
                target: defaultTargetTriple(),
                includeStdlib: false,
                stdlibOnly: true,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        _ = context.sourceManager.addFile(
            path: inputPath, contents: Data(declaration.utf8), origin: .bundledStdlib
        )
        try runToKIR(context)
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)
        artifactPath = outputBase + ".kklib"
    }
    return try #require(artifactPath)
}

private func runNonStableParameterNamesSema(
    source: String,
    surface: String,
    libraryPath: String?,
    declaration: String,
    expectErrors: Bool,
    check: (DiagnosticEngine) -> Void
) throws {
    let inputs = libraryPath == nil ? [declaration, source] : [source]
    try withTemporaryFiles(contents: inputs) { paths in
        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: "KUU3634_\(surface.replacingOccurrences(of: " ", with: "_"))",
                inputs: paths,
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple(),
                includeStdlib: false,
                stdlibLibraryPath: libraryPath,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        if libraryPath == nil {
            _ = context.sourceManager.addFile(
                path: paths[0], contents: Data(declaration.utf8), origin: .bundledStdlib
            )
        }
        if expectErrors {
            try? runSema(context)
        } else {
            try runSema(context)
        }
        check(context.diagnostics)
    }
}
