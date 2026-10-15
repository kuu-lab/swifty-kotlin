#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite
struct CallableReferenceMemberPropertyFunctionOverloadTests {
    @Test(arguments: [false, true])
    func expectedTypeSelectsSameNamedPropertyOrFunction(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KProperty1

        class A {
            val x: Int = 1
            fun x(): String = "OK"
        }

        fun main() {
            val property: KProperty1<A, Int> = A::x
            val propertyFunction: (A) -> Int = A::x
            val function: (A) -> String = A::x
        }
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .callableRef(_, member, _) = expr,
                  ctx.interner.resolve(member) == "x"
            else {
                return nil
            }
            return exprID
        }
        try #require(references.count == 3)

        let targets = try references.map { reference in
            try #require(sema.bindings.identifierSymbol(for: reference))
        }
        let properties = targets.filter { sema.symbols.symbol($0)?.kind == .property }
        let functions = targets.filter { sema.symbols.symbol($0)?.kind == .function }
        #expect(properties.count == 2, "KProperty1 and (A) -> Int should select A.x property.")
        #expect(functions.count == 1, "(A) -> String should select A.x().")

        let function = try #require(functions.first)
        #expect(sema.symbols.functionSignature(for: function)?.returnType == sema.types.stringType)
    }
}
#endif
