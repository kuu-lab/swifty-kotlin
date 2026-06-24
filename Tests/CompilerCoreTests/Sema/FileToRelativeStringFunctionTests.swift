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

    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

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

    // MARK: - Signature and runtime link binding

    @Test
    func testFileToRelativeStringSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let fileSymbol = try #require(
                symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let fileType = types.make(
                .classType(ClassType(classSymbol: fileSymbol, args: [], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["java", "io", "File", "toRelativeString"].map(interner.intern)
            )
            let toRelativeString = try #require(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == fileType
                    && signature.parameterTypes == [fileType]
                    && signature.returnType == types.stringType
            }, "Expected to find File.toRelativeString(File): String")

            #expect(
                symbols.externalLinkName(for: toRelativeString) == "kk_file_toRelativeString",
                "File.toRelativeString should bind to runtime helper kk_file_toRelativeString"
            )

            let signature = try #require(symbols.functionSignature(for: toRelativeString))
            #expect(signature.returnType == types.stringType)
            #expect(signature.receiverType == fileType)
            #expect(signature.parameterTypes == [fileType])
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
