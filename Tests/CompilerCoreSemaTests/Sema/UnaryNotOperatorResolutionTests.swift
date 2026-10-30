#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct UnaryNotOperatorResolutionTests {
    @Test
    func customNotUsesReceiverTypeAndPreservesItsReturnType() throws {
        let source = """
        class BooleanNotReceiver
        operator fun BooleanNotReceiver.not(): Boolean = true
        fun boxMin(): String = if (!BooleanNotReceiver()) "OK" else "FAIL"
        fun explicitNotControl(): Boolean = BooleanNotReceiver().not()

        class SameNotReceiver
        operator fun SameNotReceiver.not(): SameNotReceiver = this
        fun discardedRepeatedNot() { !!!!!SameNotReceiver() }

        class IntNotReceiver
        operator fun IntNotReceiver.not(): Int = 1
        fun intResult(): Int = !IntNotReceiver()

        fun builtinNot(value: Boolean): Boolean = !value
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expressions = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
                guard case .unaryExpr(.not, _, let range) = expression,
                      ctx.sourceManager.path(of: range.start.file) == path
                else { return nil }
                return ExprID(rawValue: Int32(index))
            }

            #expect(expressions.count == 8)
            #expect(expressions.filter { sema.bindings.callBindings[$0] != nil }.count == 7)

            let booleanSymbol = try #require(sema.symbols.lookup(fqName: ["BooleanNotReceiver"].map(ctx.interner.intern)))
            let sameSymbol = try #require(sema.symbols.lookup(fqName: ["SameNotReceiver"].map(ctx.interner.intern)))
            let booleanReceiverType = sema.types.make(.classType(ClassType(
                classSymbol: booleanSymbol,
                args: [],
                nullability: .nonNull
            )))
            let sameReceiverType = sema.types.make(.classType(ClassType(
                classSymbol: sameSymbol,
                args: [],
                nullability: .nonNull
            )))
            let resultTypes = expressions.compactMap { sema.bindings.exprType(for: $0) }
            #expect(resultTypes.filter { $0 == sema.types.booleanType }.count == 2)
            #expect(resultTypes.filter { $0 == sameReceiverType }.count == 5)
            #expect(resultTypes.filter { $0 == sema.types.intType }.count == 1)
            #expect(expressions.contains { id in
                sema.bindings.callBindings[id].map { binding in
                    sema.symbols.functionSignature(for: binding.chosenCallee)?.receiverType == booleanReceiverType
                } ?? false
            })
        }
    }

    @Test
    func nonBooleanWithoutNotOperatorIsRejected() throws {
        let source = """
        class UnsupportedReceiver
        fun rejected() = !UnsupportedReceiver()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(diagnosticsForPath(path, in: ctx).contains {
                $0.code == "KSWIFTK-SEMA-0002" && $0.severity == .error
            })
        }
    }
}
#endif
