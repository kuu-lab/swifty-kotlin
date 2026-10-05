#if canImport(Testing)
@testable import CompilerCore
import Testing

/// An expression-body function without a return type annotation starts with the
/// non-null header placeholder `Any`. That placeholder must neither constrain the
/// body (expected type / subtype bound) nor leak into the inferred signature, so a
/// nullable body such as `fun g() = f()` with `f(): Any?` must type-check.
@Suite
struct ExpressionBodyNullableInferredReturnTests {
    private func inferredReturnType(
        of name: String,
        in source: String
    ) throws -> (TypeID, SemaModule, CompilationContext) {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let fqName = [ctx.interner.intern(name)]
        let symbol = try #require(sema.symbols.lookupAll(fqName: fqName).first)
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        return (signature.returnType, sema, ctx)
    }

    @Test
    func testInferredAnyNullableReturnFromCall() throws {
        let (returnType, sema, ctx) = try inferredReturnType(of: "g", in: """
        fun f(): Any? = null
        fun g() = f()
        """)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(returnType == sema.types.nullableAnyType)
    }

    @Test
    func testInferredNullableReturnFromInlineGenericCall() throws {
        let (returnType, sema, ctx) = try inferredReturnType(of: "k", in: """
        inline fun <T> h(x: T): Any? = x
        fun k() = h(1)
        """)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(returnType == sema.types.nullableAnyType)
    }

    @Test
    func testInferredNullableIntReturnFromCall() throws {
        let (returnType, sema, ctx) = try inferredReturnType(of: "g2", in: """
        fun f2(): Int? = null
        fun g2() = f2()
        """)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(returnType == sema.types.make(.primitive(.int, .nullable)))
    }

    @Test
    func testNullableExplicitTypeArgumentsPreserveInferredReturnTypes() throws {
        let (returnType, sema, ctx) = try inferredReturnType(of: "f", in: """
        fun <X> makeIt(x: X): X = x
        fun f() = makeIt<Int?>(null)
        fun inferred() = makeIt(null)
        class P<T : Any> {
            fun g() = makeIt<T?>(null)
        }
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        #expect(returnType == sema.types.makeNullable(sema.types.intType))

        let inferred = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("inferred")]))
        #expect(sema.symbols.functionSignature(for: inferred)?.returnType == sema.types.nullableNothingType)

        let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("P")]))
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: owner).first)
        let member = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("P"), ctx.interner.intern("g")]))
        #expect(sema.symbols.functionSignature(for: member)?.returnType == sema.types.make(.typeParam(
            TypeParamType(symbol: typeParameter, nullability: .nullable)
        )))
    }

    @Test
    func testExplicitNonNullReturnStillRejectsNullableBody() throws {
        let ctx = makeContextFromSource("""
        fun f(): Any? = null
        fun g(): Any = f()
        """)
        try? runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }
}
#endif
