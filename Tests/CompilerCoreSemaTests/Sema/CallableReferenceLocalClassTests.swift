#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableReferenceLocalClassTests {
    @Test
    func boundOuterMutablePropertyReferenceResolvesFromLocalClass() throws {
        let ctx = makeContextFromSource("""
        class C {
            var value: String = "fail"
                private set

            fun bar(): String {
                class D { fun foo() = this@C::value }
                val r = D().foo()
                r.set("OK")
                return r.get()
            }
        }
        fun main() { println(C().bar()) }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reference = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let referenceType = try #require(sema.bindings.exprType(for: reference))
        try #require(
            errors.isEmpty,
            "Unexpected diagnostics: \(errors); property reference type: \(sema.types.kind(of: referenceType))"
        )
        #expect(!sema.bindings.isUnboundCallableRef(reference))
        guard case let .classType(classType) = sema.types.kind(of: referenceType) else {
            Issue.record("Expected a KMutableProperty0 class type, got \(sema.types.kind(of: referenceType))")
            return
        }
        let propertyReferenceType = try #require(sema.symbols.symbol(classType.classSymbol))
        #expect(
            propertyReferenceType.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KMutableProperty0"]
        )
    }

    @Test
    func classifierAndValueReceiversKeepTheirCallableReferenceKinds() throws {
        let source = """
        class Outer { fun foo(): Int = 1 }
        fun read(): Int {
            class Local { fun foo(): Int = 2 }
            val inferred = Local::foo
            val typed: (Local) -> Int = Local::foo
            val local = Local()
            val bound: () -> Int = local::foo
            val direct: Int = local.foo()
            val external: (Outer) -> Int = Outer::foo
            return inferred(local) + typed(local) + bound() + direct + external(Outer())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expression = ast.arena.expr(exprID),
                      case .callableRef = expression
                else {
                    return nil
                }
                return exprID
            }
            try #require(references.count == 4)

            let intType = sema.types.make(.primitive(.int, .nonNull))
            for reference in [references[0], references[1]] {
                #expect(sema.bindings.isUnboundCallableRef(reference))
                let type = try #require(sema.bindings.exprType(for: reference))
                guard case let .functionType(function) = sema.types.kind(of: type) else {
                    Issue.record("A local class member reference should infer a function type.")
                    return
                }
                #expect(function.params.count == 1)
                #expect(function.returnType == intType)
                let receiverParameter = try #require(function.params.first)
                guard case let .classType(receiverType) = sema.types.kind(of: receiverParameter) else {
                    Issue.record("An unbound local class reference should take its class as the first parameter.")
                    return
                }
                let localClass = try #require(sema.symbols.symbol(receiverType.classSymbol))
                #expect(localClass.kind == .class)
                #expect(ctx.interner.resolve(localClass.name) == "Local")
            }

            let boundType = try #require(sema.bindings.exprType(for: references[2]))
            guard case let .functionType(boundFunction) = sema.types.kind(of: boundType) else {
                Issue.record("A value receiver should infer a function type.")
                return
            }
            #expect(boundFunction.params.isEmpty)
            #expect(boundFunction.returnType == intType)
            #expect(!sema.bindings.isUnboundCallableRef(references[2]))

            let externalType = try #require(sema.bindings.exprType(for: references[3]))
            guard case let .functionType(externalFunction) = sema.types.kind(of: externalType) else {
                Issue.record("A non-local class member reference should infer a function type.")
                return
            }
            #expect(externalFunction.params.count == 1)
            #expect(externalFunction.returnType == intType)
            #expect(sema.bindings.isUnboundCallableRef(references[3]))
            let receiverParameter = try #require(externalFunction.params.first)
            guard case let .classType(receiverType) = sema.types.kind(of: receiverParameter) else {
                Issue.record("A non-local unbound reference should take its class as the first parameter.")
                return
            }
            let outerClass = try #require(sema.symbols.symbol(receiverType.classSymbol))
            #expect(ctx.interner.resolve(outerClass.name) == "Outer")
        }
    }
}
#endif
