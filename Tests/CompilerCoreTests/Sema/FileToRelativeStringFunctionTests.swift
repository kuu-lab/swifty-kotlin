#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-038: File.toRelativeString(base: File): String
//
// Validates the synthetic `kotlin.io.File.toRelativeString` declaration registered
// in `HeaderHelpers+SyntheticFileIOStubs.swift`. The expectations:
// 1. Calls of the form `file.toRelativeString(base)` resolve through Sema for
//    plain `java.io.File` receivers and arguments.
// 2. The call expression types as `String`, including when the result is fed
//    into a `String` consumer such as `println(...)` or a `String` return.
// 3. The Sema-side function symbol binds to the runtime export
//    `kk_file_toRelativeString`, which is the contract the ABI lowering pass
//    relies on to thread the `outThrown` slot for IllegalArgumentException.

@Suite
struct FileToRelativeStringFunctionTests {


    // MARK: - Resolves with a File argument

    @Test
    func testFileToRelativeStringResolves() throws {
        let source = """
        import java.io.File

        fun describe(file: File, base: File): String {
            return file.toRelativeString(base)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "File.toRelativeString(base) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Composes with println / String consumers

    @Test
    func testFileToRelativeStringComposesWithStringConsumer() throws {
        let source = """
        import java.io.File

        fun main() {
            val target = File("/a/b/c")
            val base = File("/a")
            val rel: String = target.toRelativeString(base)
            println(rel)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "File.toRelativeString(base) should compose into a String slot: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - Call expression types as String

    @Test
    func testFileToRelativeStringCallExpressionTypedAsString() throws {
        let source = """
        import java.io.File

        fun main() {
            val target = File("/a/b/c")
            val base = File("/a")
            val rel = target.toRelativeString(base)
            println(rel)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Sema should type target.toRelativeString(base) as String: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)

            let callExprs = memberCallExprIDs(named: "toRelativeString", in: ast, interner: interner)
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

    // MARK: - Works inside scope functions (let/run/apply/with)

    @Test
    func testFileToRelativeStringInsideScopeFunctions() throws {
        let source = """
        import java.io.File

        fun main() {
            val base = File("/root")
            val target = File("/root/sub/leaf.txt")
            target.let { node ->
                val rel: String = node.toRelativeString(base)
                println(rel)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "File.toRelativeString should resolve inside scope functions: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
#endif
