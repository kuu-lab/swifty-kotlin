#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableReferenceCompanionFunctionTests {
    @Test
    func objectAndClassNameReferencesBindInheritedSingletonMembers() throws {
        let source = """
        abstract class Base {
            fun foo(): String = "A"
            abstract fun bar(): String
        }
        object Singleton : Base() {
            override fun bar(): String = "C"
        }
        class Some {
            companion object : Base() {
                override fun bar(): String = "B"
            }
        }
        fun probe() {
            val singletonFoo: () -> String = Singleton::foo
            val singletonBar: () -> String = Singleton::bar
            val someFoo: () -> String = Some::foo
            val someBar: () -> String = Some::bar
            val explicitCompanionFoo: () -> String = Some.Companion::foo
            val singletonFooResult: String = (Singleton::foo)()
            val singletonBarResult: String = (Singleton::bar)()
            val someFooResult: String = (Some::foo)()
            val someBarResult: String = (Some::bar)()
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
                guard case .callableRef? = ast.arena.expr(exprID) else { return nil }
                return exprID
            }
            try #require(references.count == 9)

            let someReferences = references.filter { reference in
                guard case let .callableRef(receiver?, _, _) = ast.arena.expr(reference),
                      let symbol = sema.bindings.identifierSymbol(for: receiver)
                else {
                    return false
                }
                return sema.symbols.symbol(symbol)?.name == ctx.interner.intern("Some")
            }
            try #require(someReferences.count == 4)

            for reference in references {
                let target = try #require(sema.bindings.identifierSymbol(for: reference))
                #expect(sema.symbols.symbol(target)?.kind == .function)
                #expect(!sema.bindings.isUnboundCallableRef(reference))
                guard case let .functionType(function) = sema.types.kind(
                    of: try #require(sema.bindings.exprType(for: reference))
                ) else {
                    Issue.record("A singleton-bound callable reference should have a function type.")
                    continue
                }
                #expect(function.receiver == nil)
                #expect(function.params.isEmpty)
                #expect(function.returnType == sema.types.stringType)
            }
        }
    }
}
#endif
