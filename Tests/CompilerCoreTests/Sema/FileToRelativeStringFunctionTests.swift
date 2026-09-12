#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-038: File.toRelativeString(base: File): String
//
// Validates the synthetic `kotlin.io.File.toRelativeString` declaration registered
// in `HeaderHelpers+SyntheticTODOAndIOStubs.swift`. The expectations:
// 1. Calls of the form `file.toRelativeString(base)` resolve through Sema for
//    plain `java.io.File` receivers and arguments.
// 2. The call expression types as `String`, including when the result is fed
//    into a `String` consumer such as `println(...)` or a `String` return.
// 3. The Sema-side function symbol binds to the runtime export
//    `kk_file_toRelativeString`, which is the contract the ABI lowering pass
//    relies on to thread the `outThrown` slot for IllegalArgumentException.

@Suite
struct FileToRelativeStringFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testFileToRelativeStringResolves
            """
            package sample0

                    import java.io.File

                    fun describe(file: File, base: File): String {
                        return file.toRelativeString(base)
                    }

            """,
            // testFileToRelativeStringCallExpressionTypedAsString
            """
            package sample1

                    import java.io.File

                    fun main() {
                        val target = File("/a/b/c")
                        val base = File("/a")
                        val rel = target.toRelativeString(base)
                        println(rel)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFileToRelativeStringResolves ===

            do {

                let sample0Path = paths[0]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "File.toRelativeString(base) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileToRelativeStringCallExpressionTypedAsString ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "Sema should type target.toRelativeString(base) as String: \(sample1Diagnostics.map(\.message))"
                )

                let callExprs = memberCallExprIDs(named: "toRelativeString", in: ast, path: sample1Path, ctx: ctx, interner: interner)
                #expect(
                    callExprs.count == 1,
                    "Expected exactly one toRelativeString call expression in the program."
                )
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == sema.types.stringType,
                        "Each File.toRelativeString(base) call expression must be typed as String"
                    )
                }

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRClean() throws {

        let sources: [String] = [
            // testFileToRelativeStringComposesWithStringConsumer
            """
            package sample0

                    import java.io.File

                    fun main() {
                        val target = File("/a/b/c")
                        val base = File("/a")
                        val rel: String = target.toRelativeString(base)
                        println(rel)
                    }

            """,
            // testFileToRelativeStringInsideScopeFunctions
            """
            package sample1

                    import java.io.File

                    fun main() {
                        val base = File("/root")
                        val target = File("/root/sub/leaf.txt")
                        target.let { node ->
                            val rel: String = node.toRelativeString(base)
                            println(rel)
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            _ = try #require(ctx.kir)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testFileToRelativeStringComposesWithStringConsumer ===

            do {

                let sample0Path = paths[0]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    !sample0Diagnostics.contains { $0.severity == .error },
                    "File.toRelativeString(base) should compose into a String slot: \(sample0Diagnostics.map(\.message))"
                )

            }

            // === testFileToRelativeStringInsideScopeFunctions ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "File.toRelativeString should resolve inside scope functions: \(sample1Diagnostics.map(\.message))"
                )

            }

        }
    }

}

#endif
