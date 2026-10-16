#if canImport(Testing)
import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct LocalClassInterfaceDelegationTests {
    @Test
    func localClassDelegationSatisfiesInheritedAbstractMembers() throws {
        let ctx = makeContextFromSource("""
        interface Callback { fun foo() }
        interface SuccessCallback<in T> { fun onSuccess(value: T) }
        interface MaybeCallbacks<in T> : SuccessCallback<T>, Callback
        interface Disposable
        interface Observer<in T> { fun onSubscribe(disposable: Disposable) }
        interface MaybeObserver<in T> : Observer<T>, MaybeCallbacks<T>

        fun <T> original(emitter: MaybeCallbacks<T>) {
            class OuterLocal<U> : MaybeObserver<T>, Callback by emitter {
                override fun onSubscribe(disposable: Disposable) {}
                override fun onSuccess(value: T) {
                    class InnerLocal : MaybeObserver<T>, Observer<T> by this, MaybeCallbacks<T> by emitter {}
                }
            }
        }

        interface P { fun f(): String }
        interface Parent<T> { fun read(): T }
        interface Child<T> : Parent<T>
        interface Required { fun missing(): Int }
        object Delegate : P { override fun f() = "OK" }
        object ParentDelegate : Child<String> { override fun read() = "value" }

        fun call(): String {
            val delegate = Delegate
            class DelegatingLocal : P by delegate, Child<String> by ParentDelegate
            return DelegatingLocal().f() + DelegatingLocal().read()
        }

        fun explicitOverride(delegate: P): String {
            class ExplicitLocal : P by delegate { override fun f() = "override" }
            return ExplicitLocal().f()
        }

        fun incomplete(delegate: P) {
            class Partial : P by delegate, Required
        }
        """)
        try runSema(ctx)

        let abstractErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
        #expect(abstractErrors.count == 1, "Got: \(ctx.diagnostics.diagnostics)")
        #expect(abstractErrors.first?.message.contains("missing") == true)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        func localClass(named name: String) -> (DeclID, ClassDecl, SymbolID)? {
            for declID in ast.arena.exprs.compactMap({ expr -> DeclID? in
                guard case let .localNominalDecl(declID, _) = expr else { return nil }
                return declID
            }) {
                guard let decl = ast.arena.decl(declID),
                      case let .classDecl(classDecl) = decl,
                      ctx.interner.resolve(classDecl.name) == name,
                      let symbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                return (declID, classDecl, symbol)
            }
            return nil
        }

        for (name, expectedDelegations, expectedForwarders) in [
            ("OuterLocal", 1, 1),
            ("InnerLocal", 2, 3),
            ("DelegatingLocal", 2, 2),
            ("ExplicitLocal", 1, 0),
            ("Partial", 1, 1),
        ] {
            let (_, classDecl, symbol) = try #require(localClass(named: name))
            let interfaces = sema.symbols.delegatedInterfaces(forClass: symbol)
            #expect(interfaces.count == expectedDelegations, "\(name): \(interfaces)")
            #expect(
                sema.symbols.classDelegationForwardingMethodSymbols(forClass: symbol).count == expectedForwarders,
                "\(name)"
            )
            for entry in classDecl.superTypeEntries where entry.delegateExpression != nil {
                let interface = try #require(interfaces.first {
                    sema.symbols.classDelegationExpr(forClass: symbol, interface: $0) == entry.delegateExpression
                })
                let field = try #require(sema.symbols.classDelegationField(forClass: symbol, interface: interface))
                #expect(sema.bindings.exprType(for: try #require(entry.delegateExpression)) != nil)
                #expect(sema.symbols.nominalLayout(for: symbol)?.fieldOffsets[field] != nil)
            }
        }

        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.count == 1)
    }
}
#endif
