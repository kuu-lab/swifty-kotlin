#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CompanionCallableReferenceTests {
    @Test
    func classNameCompanionMemberReferenceBindsTheCompanionReceiver() throws {
        let source = """
        open class A {
            fun instance() = true
            companion object : A() {
                fun companion() = true
            }
        }
        fun call(f: () -> Boolean) = f()
        fun main() { call(A::companion) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "companion"
                else {
                    return nil
                }
                return exprID
            }.first)
            let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("A")]))
            let companion = try #require(sema.symbols.companionObjectSymbol(for: owner))
            let target = try #require(sema.bindings.identifierSymbol(for: reference))
            let referenceType = try #require(sema.bindings.exprType(for: reference))
            guard case let .functionType(function) = sema.types.kind(of: referenceType) else {
                Issue.record("Expected a callable reference function type.")
                return
            }

            #expect(sema.symbols.parentSymbol(for: target) == companion)
            #expect(function.receiver == nil)
            #expect(function.params.isEmpty)
            #expect(function.returnType == sema.types.booleanType)
            #expect(!sema.bindings.isUnboundCallableRef(reference))
        }
    }
}
#endif
