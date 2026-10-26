@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableUpperBoundMemberResolutionTests {
    @Test
    func safeCallAndNullCheckUseNonNullUpperBoundView() throws {
        let source = """
        fun <T : Number?> numberToIntSafely(value: T): Int? = value?.toInt()

        fun <T : Number?> numberToIntAfterNullCheck(value: T): Int? =
            if (value == null) null else value.toInt()

        fun <T : Number?> numberToIntAfterElvis(value: T): Int = (value ?: 42).toInt()

        fun numberToIntAfterNullableElvis(value: Number?): Int = (value ?: 42).toInt()

        fun <T : Number> numberToIntAfterNonNullBoundElvis(value: T): Int = (value ?: 42).toInt()

        fun <T : Number?> numberToIntWithoutNullCheck(value: T): Int = value.toInt()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Expected only the unguarded call to fail: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0002")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let toIntName = ctx.interner.intern("toInt")
            let calls = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.path(of: range.start.file) == path
                else {
                    return nil
                }
                switch expr {
                case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _):
                    return name == toIntName ? id : nil
                default:
                    return nil
                }
            }.sorted { left, right in
                ast.arena.exprRange(left)!.start.offset < ast.arena.exprRange(right)!.start.offset
            }
            #expect(calls.count == 6)

            let resolvedCalls = calls.compactMap { id in
                sema.bindings.callBinding(for: id).map { (id, $0.chosenCallee) }
            }
            #expect(resolvedCalls.count == 5, "Only the unguarded nullable type-parameter call should fail")
            for (_, callee) in resolvedCalls {
                let symbol = try #require(sema.symbols.symbol(callee))
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "Number", "toInt"])
            }
            if let safeCall = calls.first,
               let type = sema.bindings.exprType(for: safeCall)
            {
                #expect(type == sema.types.makeNullable(sema.types.intType))
            } else {
                Issue.record("Expected a typed safe-call expression")
            }
        }
    }
}
