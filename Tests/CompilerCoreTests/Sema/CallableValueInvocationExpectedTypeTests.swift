#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableValueInvocationExpectedTypeTests {
    @Test
    func genericCallArgumentUsesFunctionValueParameterType() throws {
        let source = """
        fun <T> arrayOf(vararg elements: T): Array<T> = null!!

        fun box(): String {
            val f: (Array<Any>) -> String = { "OK" }
            return f(arrayOf("x"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let arrayOfCallID = try #require(arrayOfCall(
                in: ast,
                sourcePath: path,
                sourceManager: ctx.sourceManager,
                interner: ctx.interner
            ))
            let inferredType = try #require(sema.bindings.exprType(for: arrayOfCallID))
            guard case let .classType(arrayType) = sema.types.kind(of: inferredType) else {
                Issue.record("Expected arrayOf to infer an array type, got \(sema.types.renderType(inferredType))")
                return
            }
            #expect(arrayType.args == [.invariant(sema.types.anyType)])
        }
    }

    @Test
    func genericCallArgumentStillRejectsInvariantArrayMismatch() throws {
        let source = """
        fun <T> arrayOf(vararg elements: T): Array<T> = null!!

        fun box(): String {
            val f: (Array<Int>) -> String = { "OK" }
            return f(arrayOf("x"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            #expect(ctx.diagnostics.hasError, "Expected invariant Array<String> to be rejected for Array<Int>")
        }
    }

    private func arrayOfCall(
        in ast: ASTModule,
        sourcePath: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> ExprID? {
        ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == sourcePath,
                  case let .call(calleeID, _, _, _) = ast.arena.expr(exprID),
                  case let .nameRef(name, _) = ast.arena.expr(calleeID),
                  interner.resolve(name) == "arrayOf"
            else {
                return nil
            }
            return exprID
        }.first
    }
}
#endif
