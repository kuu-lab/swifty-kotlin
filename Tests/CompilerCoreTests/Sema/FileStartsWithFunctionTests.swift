#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-037: `fun java.io.File.startsWith(other: File): Boolean`
///                   `fun java.io.File.startsWith(other: String): Boolean`
///
/// Verifies that the synthetic `startsWith` overloads registered on the
/// `java.io.File` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift`)
/// resolve through Sema for plain File receivers and bind to the runtime
/// helpers `kk_file_startsWith_file` / `kk_file_startsWith_string` listed in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
@Suite
struct FileStartsWithFunctionTests {
    // KSP-483: `startsWith` is now also used internally by the bundled
    // `Stdlib/kotlin/io/Files.kt` (as `String.startsWith`), so member-call
    // scans across the whole AST must exclude bundled-stdlib files or they'll
    // pick up those internal calls alongside the user source's calls.
    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  !sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - File overload resolves cleanly

    @Test func testFileStartsWithFileOverloadResolves() throws {
        let source = """
        import java.io.File

        fun isChild(child: File, parent: File): Boolean {
            return child.startsWith(parent)
        }

        fun main() {
            println(isChild(File("/tmp/sub/file.txt"), File("/tmp")))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "File.startsWith(File) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - String overload resolves cleanly

    @Test func testFileStartsWithStringOverloadResolves() throws {
        let source = """
        import java.io.File

        fun isUnderTmp(file: File): Boolean {
            return file.startsWith("/tmp")
        }

        fun main() {
            println(isUnderTmp(File("/tmp/sub/file.txt")))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "File.startsWith(String) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Both call expressions are typed as Boolean

    @Test func testFileStartsWithCallExpressionsAreTypedAsBoolean() throws {
        let source = """
        import java.io.File

        fun decide(file: File, parent: File): Boolean {
            val a: Boolean = file.startsWith(parent)
            val b: Boolean = file.startsWith("/tmp")
            return a && b
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "File.startsWith call expressions should type cleanly as Boolean: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let booleanType = sema.types.booleanType

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(
                named: "startsWith", in: ast, interner: interner, sourceManager: ctx.sourceManager
            )
            #expect(callExprs.count == 2, "expected two startsWith member calls")
            for callExpr in callExprs {
                #expect(
                    sema.bindings.exprTypes[callExpr] == booleanType,
                    "Each File.startsWith(...) call expression must be typed as Boolean"
                )
            }
        }
    }

}
#endif
