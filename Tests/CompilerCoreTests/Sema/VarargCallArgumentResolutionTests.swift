@testable import CompilerCore
import Testing

@Suite
struct VarargCallArgumentResolutionTests {
    @Test
    func expressionSpreadAndNamedArrayWithTrailingArgumentsResolve() throws {
        let ctx = makeContextFromSource("""
        fun ints(): IntArray = intArrayOf(2)
        fun strings(): Array<String> = arrayOf("a", "b")
        fun g(vararg xs: Int) = xs.size
        fun v(vararg xs: String) = xs.size
        fun h(s: String, vararg xs: Int, t: Int = 0) = xs.size + t
        fun calls() {
            g(*intArrayOf(1, 2))
            g(1, *intArrayOf(2), 3)
            g(*ints())
            v(*arrayOf("a", "b"))
            v(*strings())
            h("s", t = 5)
            h("s", 1, 2, t = 5)
            h("s", xs = intArrayOf(7), t = 1)
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(namedCall(
            "h",
            labels: [nil, "xs", "t"],
            in: ast,
            interner: ctx.interner
        ))
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(binding.parameterMapping == [0: 0, 1: 1, 2: 2])
    }

    @Test
    func spreadAndNamedVarargRejectMismatchedArrayTypes() throws {
        for argument in [
            "*arrayOf(\"wrong\")",
            "xs = arrayOf(\"wrong\")",
            "xs = 7",
        ] {
            let ctx = makeContextFromSource("""
            fun g(vararg xs: Int) = xs.size
            fun invalid() = g(\(argument))
            """)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected \(argument) to be rejected")
        }
    }

    private func namedCall(
        _ name: String,
        labels: [String?],
        in ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, args, _) = ast.arena.expr(exprID),
                  args.map({ $0.label.map(interner.resolve) }) == labels,
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee),
                  interner.resolve(calleeName) == name
            else {
                continue
            }
            return exprID
        }
        return nil
    }
}
