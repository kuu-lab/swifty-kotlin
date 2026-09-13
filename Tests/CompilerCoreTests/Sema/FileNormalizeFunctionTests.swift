#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-024: `fun java.io.File.normalize(): File`
///
/// Verifies that the synthetic `normalize` member registered on the
/// `java.io.File` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTODOAndIOStubs.swift`)
/// resolves through Sema and binds to the runtime helper `kk_file_normalize`
/// listed in `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
@Suite
struct FileNormalizeFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testFileNormalizeResolves
            """
            package sample0

                    import java.io.File

                    fun normalizedFile(file: File): File {
                        return file.normalize()
                    }

                    fun main() {
                        println(normalizedFile(File("/tmp/./sub/../file.txt")).path)
                    }

            """,
            // testFileNormalizeCallExpressionIsTypedAsFile
            """
            package sample1

                    import java.io.File

                    fun normalized(file: File): File {
                        val result: File = file.normalize()
                        return result
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFileNormalizeResolves ===

            do {

                let sample0Path = paths[0]



                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                // KSP-483: the top-level helper must not be named `normalize` — that
                // now collides with the Kotlin-source `File.normalize()` extension
                // function bundled from Stdlib/kotlin/io/Files.kt.
                    let errors = sample0Diagnostics.filter { $0.severity == .error }
                    #expect(
                        errors.isEmpty,
                        "File.normalize() should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                    )

            }

            // === testFileNormalizeCallExpressionIsTypedAsFile ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "File.normalize() should type-check as File: \(sample1Diagnostics.map(\.message))"
                )

                let fileSymbol = try #require(
                    sema.symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
                )
                let fileType = sema.types.make(
                    .classType(ClassType(classSymbol: fileSymbol, args: [], nullability: .nonNull))
                )

                let normalizeCallExprs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr,
                          interner.resolve(callee) == "normalize"
                    else {
                        return nil
                    }
                    return exprID
                }
                #expect(!normalizeCallExprs.isEmpty, "Expected at least one normalize call expression")
                for callExpr in normalizeCallExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == fileType,
                        "File.normalize() call expression must be typed as File"
                    )
                }

            }

        }
    }

}

#endif
