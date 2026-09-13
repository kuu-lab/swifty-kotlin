#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-036: `fun java.io.File.resolveSibling(relative: File): File`
///                   `fun java.io.File.resolveSibling(relative: String): File`
///
/// Verifies that the synthetic `resolveSibling` overloads registered on the
/// `java.io.File` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTODOAndIOStubs.swift`)
/// resolve through Sema for plain File receivers and bind to the runtime
/// helpers `kk_file_resolveSibling_file` / `kk_file_resolveSibling_string` listed
/// in `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
@Suite
struct FileResolveSiblingFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testFileResolveSiblingFileOverloadResolves
            """
            package sample0

                    import java.io.File

                    fun getSibling(file: File, sibling: File): File {
                        return file.resolveSibling(sibling)
                    }

                    fun main() {
                        val f = File("/tmp/a/b.txt")
                        val sibling = File("c.txt")
                        println(getSibling(f, sibling).path)
                    }

            """,
            // testFileResolveSiblingStringOverloadResolves
            """
            package sample1

                    import java.io.File

                    fun getSiblingByName(file: File): File {
                        return file.resolveSibling("other.txt")
                    }

                    fun main() {
                        println(getSiblingByName(File("/tmp/a/b.txt")).path)
                    }

            """,
            // testFileResolveSiblingCallExpressionsAreTypedAsFile
            """
            package sample2

                    import java.io.File

                    fun decide(file: File, other: File): File {
                        val a: File = file.resolveSibling(other)
                        val b: File = file.resolveSibling("sibling.txt")
                        return a
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFileResolveSiblingFileOverloadResolves ===

            do {

                let sample0Path = paths[0]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "File.resolveSibling(File) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileResolveSiblingStringOverloadResolves ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "File.resolveSibling(String) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileResolveSiblingCallExpressionsAreTypedAsFile ===

            do {

                let sample2Path = paths[2]


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(
                    !sample2Diagnostics.contains { $0.severity == .error },
                    "File.resolveSibling call expressions should type cleanly as File: \(sample2Diagnostics.map(\.message))"
                )

                let fileSymbol = try #require(
                    sema.symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
                )
                let fileType = sema.types.make(
                    .classType(ClassType(classSymbol: fileSymbol, args: [], nullability: .nonNull))
                )

                let callExprs = memberCallExprIDs(named: "resolveSibling", in: ast, path: sample2Path, ctx: ctx, interner: interner)
                #expect(callExprs.count == 2, "expected two resolveSibling member calls")
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == fileType,
                        "Each File.resolveSibling(...) call expression must be typed as File"
                    )
                }

            }

        }
    }

}

#endif
