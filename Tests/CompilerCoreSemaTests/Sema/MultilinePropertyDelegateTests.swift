#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct MultilinePropertyDelegateTests {
    @Test(arguments: [false, true])
    func delegateOnFollowingLineInitializesTheProperty(useStdlibArtifact: Bool) throws {
        if useStdlibArtifact {
            TestStdlibCache.shared.prepare()
        }

        let source = """
        import kotlin.properties.Delegates

        object Store {
            var value: String
                by Delegates.observable("OK") { _, _, _ -> }
        }

        object PrivateSetterStore {
            var value: String by Delegates.observable("OK") { _, _, _ -> }
            private set
        }

        class ProtectedSetterStore {
            var value: String
                by Delegates.observable("OK") { _, _, _ -> }
            protected set
        }

        object EmptyStore {
            var value: String
        }

        fun box(): String = Store.value
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: useStdlibArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useStdlibArtifact
            )
            try runToKIR(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0424" }.count == 1, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0424" }, "\(errors)")

            let ast = try #require(ctx.ast)
            let interner = ctx.interner
            let store = try #require(firstObjectDecl(named: "Store", in: ast, interner: interner))
            let storePropertyID = try #require(store.memberProperties.first)
            guard case let .propertyDecl(storeProperty)? = ast.arena.decl(storePropertyID) else {
                Issue.record("Expected Store.value to be a property declaration")
                return
            }
            #expect(interner.resolve(storeProperty.name) == "value")
            #expect(storeProperty.initializer == nil)
            #expect(storeProperty.delegateExpression != nil)

            let privateSetterStore = try #require(
                firstObjectDecl(named: "PrivateSetterStore", in: ast, interner: interner)
            )
            let privatePropertyID = try #require(privateSetterStore.memberProperties.first)
            guard case let .propertyDecl(privateProperty)? = ast.arena.decl(privatePropertyID) else {
                Issue.record("Expected PrivateSetterStore.value to be a property declaration")
                return
            }
            #expect(privateProperty.delegateExpression != nil)
            #expect(privateProperty.setter?.visibility == .private)

            let protectedSetterStore = try #require(
                firstClassDecl(named: "ProtectedSetterStore", in: ast, interner: interner)
            )
            let protectedPropertyID = try #require(protectedSetterStore.memberProperties.first)
            guard case let .propertyDecl(protectedProperty)? = ast.arena.decl(protectedPropertyID) else {
                Issue.record("Expected ProtectedSetterStore.value to be a property declaration")
                return
            }
            #expect(protectedProperty.delegateExpression != nil)
            #expect(protectedProperty.setter?.visibility == .protected)

            let emptyStore = try #require(firstObjectDecl(named: "EmptyStore", in: ast, interner: interner))
            let emptyPropertyID = try #require(emptyStore.memberProperties.first)
            guard case let .propertyDecl(emptyProperty)? = ast.arena.decl(emptyPropertyID) else {
                Issue.record("Expected EmptyStore.value to be a property declaration")
                return
            }
            #expect(emptyProperty.delegateExpression == nil)
        }
    }
}
#endif
