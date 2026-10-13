#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct ObjectLiteralInterfaceDelegationTests {
    @Test func anonymousObjectDelegationPreservesAndBindsTheDelegate() throws {
        let ctx = makeContextFromSource("""
        interface Greeter { fun greet(): String }
        class Impl : Greeter { override fun greet() = "hi" }
        fun main() {
            val o = object : Greeter by Impl() {}
            println(o.greet())
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let declID = try #require(ast.arena.exprs.compactMap { expr -> DeclID? in
            guard case let .objectLiteral(_, declID, _) = expr else { return nil }
            return declID
        }.first)
        guard case let .objectDecl(decl)? = ast.arena.decl(declID) else {
            Issue.record("Expected an anonymous object declaration")
            return
        }
        let delegateExpr = try #require(decl.superTypeEntries.first?.delegateExpression)
        let owner = try #require(sema.bindings.declSymbols[declID])
        let interface = try #require(sema.symbols.delegatedInterfaces(forClass: owner).first)
        #expect(sema.symbols.classDelegationExpr(forClass: owner, interface: interface) == delegateExpr)
        #expect(sema.bindings.exprType(for: delegateExpr) != nil)
        #expect(sema.symbols.classDelegationForwardingMethodSymbols(forClass: owner).count == 1)
        let field = try #require(sema.symbols.classDelegationField(forClass: owner, interface: interface))
        let layout = try #require(sema.symbols.nominalLayout(for: owner))
        #expect(layout.fieldOffsets[field] == layout.objectHeaderWords)
        #expect(layout.instanceFieldCount == 1)
    }

    @Test func inheritedGenericMembersAndExplicitOverridesAreBound() throws {
        let ctx = makeContextFromSource("""
        interface Parent<T> { fun read(): T; var value: T }
        interface Child<T> : Parent<T>
        class Impl : Child<Int> {
            override fun read(): Int = value
            override var value: Int = 7
        }
        fun make(delegate: Child<Int>) {
            val o = object : Child<Int> by delegate {
                override fun read(): Int = value + 1
            }
            val value: Int = o.value
            o.value = value + o.read()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let declID = try #require(ast.arena.exprs.compactMap { expr -> DeclID? in
            guard case let .objectLiteral(_, declID, _) = expr else { return nil }
            return declID
        }.first)
        let owner = try #require(sema.bindings.declSymbols[declID])
        #expect(sema.symbols.classDelegationForwardingMethodSymbols(forClass: owner).isEmpty)
        let property = try #require(sema.symbols.classDelegationForwardingPropertySymbols(forClass: owner).first)
        #expect(sema.symbols.propertyType(for: property) == sema.types.intType)
        #expect(sema.symbols.symbol(property)?.flags.contains(.mutable) == true)
    }

    @Test func delegationDoesNotHideMissingMembersOrInvalidDelegates() throws {
        let ctx = makeContextFromSource("""
        interface Greeter { fun greet(): String }
        interface Other { fun missing(): Int; val missingValue: Int }
        class Impl : Greeter { override fun greet() = "hi" }
        open class Base
        fun check() {
            val partial = object : Greeter by Impl(), Other {}
            val wrongType = object : Greeter by 1 {}
            val wrongSupertype = object : Base by Base() {}
        }
        """)
        try runSema(ctx)
        let abstractErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
        #expect(abstractErrors.count == 2, "Got: \(abstractErrors)")
        #expect(abstractErrors.allSatisfy { $0.message.contains("missing") })
        assertHasDiagnostic("KSWIFTK-SEMA-DELEGATE", in: ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test(arguments: [false, true])
    func sameArityOverloadsRetainSeparateForwarders(hasOverride: Bool) throws {
        let ctx = makeContextFromSource("""
        interface Parent<T> { fun echo(value: T): T; fun echo(value: String): String }
        interface Child<T> : Parent<T>
        class Impl : Child<Int> {
            override fun echo(value: Int): Int = value
            override fun echo(value: String): String = value
        }
        fun main() {
            val o = object : Child<Int> by Impl() {
                \(hasOverride ? "override fun echo(value: Int): Int = value + 1" : "")
            }
            val number: Int = o.echo(1)
            val text: String = o.echo("x")
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let declID = try #require(ast.arena.exprs.compactMap { expr -> DeclID? in
            guard case let .objectLiteral(_, declID, _) = expr else { return nil }
            return declID
        }.first)
        let owner = try #require(sema.bindings.declSymbols[declID])
        let methods = sema.symbols.classDelegationForwardingMethodSymbols(forClass: owner)
        #expect(methods.count == (hasOverride ? 1 : 2))
        let parameters = methods.compactMap { sema.symbols.functionSignature(for: $0)?.parameterTypes }
        #expect(parameters.contains([sema.types.stringType]))
        #expect(parameters.contains([sema.types.intType]) == !hasOverride)
    }

    @Test func comparisonInDelegateDoesNotConsumeOtherSupertypesOrMembers() throws {
        let ctx = makeContextFromSource("""
        interface Left { fun left(): Int }
        interface Right { fun right(): Int }
        class L : Left { override fun left(): Int = 8 }
        class R : Right { override fun right(): Int = 20 }
        fun main(): Int {
            val offset = 2
            val o = object : Left by (if (offset < 3) L() else L()), Right by R() {
                fun marker(): Int = 6
            }
            return o.left() + o.right() + o.marker()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let declID = try #require(ast.arena.exprs.compactMap { expr -> DeclID? in
            guard case let .objectLiteral(_, declID, _) = expr else { return nil }
            return declID
        }.first)
        guard case let .objectDecl(decl)? = ast.arena.decl(declID) else {
            Issue.record("Expected an anonymous object declaration")
            return
        }
        #expect(decl.superTypeEntries.compactMap(\.delegateExpression).count == 2)
        #expect(decl.memberFunctions.count == 1)
    }
}
#endif
