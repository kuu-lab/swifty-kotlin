#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct InterfaceDelegationCompletenessTests {
    private static let positiveContext = Result {
        let ctx = makeContextFromSource("""
        object SharedArrayList : MutableList<Any> by mutableListOf()
        class ListWrapper<T>(delegate: MutableList<T>) : MutableList<T> by delegate
        object SharedSet : MutableSet<Int> by mutableSetOf()
        object SharedMap : MutableMap<String, Int> by mutableMapOf()
        interface Parent<T> { fun read(): T; var value: T }
        interface Left<T> : Parent<T>
        interface Right<T> : Parent<T>
        interface Child<T> : Left<T>, Right<T>
        class Impl : Child<Int> {
            override fun read(): Int = value
            override var value: Int = 7
        }
        object Delegated : Child<Int> by Impl()
        class Outer {
            class Nested<T>(delegate: Child<T>) : Child<T> by delegate
            object NestedObject : Child<Int> by Impl()
            companion object : Child<Int> by Impl()
        }
        """)
        try runSema(ctx)
        return ctx
    }

    @Test func collectionAndInheritedDelegationSatisfiesAbstractMembers() throws {
        let ctx = try Self.positiveContext.get()
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func objectDelegateExpressionIsPreservedAndReceivesExpectedType() throws {
        let ctx = try Self.positiveContext.get()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let objectID = try #require(ast.sortedFiles.flatMap(\.topLevelDecls).first {
            guard case let .objectDecl(decl) = ast.arena.decl($0) else { return false }
            return ctx.interner.resolve(decl.name) == "SharedArrayList"
        })
        guard case let .objectDecl(decl) = ast.arena.decl(objectID) else {
            Issue.record("Expected SharedArrayList object")
            return
        }
        let expression = try #require(decl.superTypeEntries.first?.delegateExpression)
        let delegateType = try #require(sema.bindings.exprType(for: expression))
        guard case let .classType(type) = sema.types.kind(of: delegateType) else {
            Issue.record("Expected a nominal delegate type")
            return
        }
        #expect(type.args == [.invariant(sema.types.anyType)])
        let symbol = try #require(sema.bindings.declSymbols[objectID])
        let interfaces = sema.symbols.delegatedInterfaces(forClass: symbol)
        #expect(interfaces.count == 1)
        let interface = try #require(interfaces.first)
        #expect(sema.symbols.classDelegationExpr(forClass: symbol, interface: interface) == expression)
    }

    @Test func diamondAndNestedDeclarationsSynthesizeInheritedForwardersOnce() throws {
        let ctx = try Self.positiveContext.get()
        let sema = try #require(ctx.sema)
        for path in [["Delegated"], ["Outer", "Nested"], ["Outer", "NestedObject"], ["Outer", "Companion"]] {
            let symbol = try #require(sema.symbols.lookup(fqName: path.map { ctx.interner.intern($0) }))
            let methods = sema.symbols.classDelegationForwardingMethodSymbols(forClass: symbol)
            let properties = sema.symbols.classDelegationForwardingPropertySymbols(forClass: symbol)
            #expect(methods.count == 1)
            #expect(properties.count == 1)
            #expect(sema.symbols.symbol(methods[0])?.flags.contains(.abstractType) == false)
            #expect(sema.symbols.symbol(properties[0])?.flags.contains(.mutable) == true)
            let signature = try #require(sema.symbols.functionSignature(for: methods[0]))
            #expect(signature.returnType == sema.symbols.propertyType(for: properties[0]))
            if path != ["Outer", "Nested"] {
                #expect(signature.returnType == sema.types.intType)
            }
        }
    }

    @Test func delegationDoesNotHideUnrelatedMissingMembersOrInvalidDelegates() throws {
        let ctx = makeContextFromSource("""
        interface Parent { fun read(): Int }
        interface Child : Parent
        interface Other { fun missing(): Int; val missingValue: Int }
        class Impl : Child { override fun read(): Int = 1 }
        object Partial : Child by Impl(), Other
        class Outer { object NestedPartial : Child by Impl(), Other }
        object WrongType : Child by 1
        open class Base
        object WrongSupertype : Base by Base()
        """)
        try runSema(ctx)
        let abstractErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
        #expect(abstractErrors.count == 4, "Got: \(abstractErrors)")
        #expect(abstractErrors.allSatisfy { $0.message.contains("missing") })
        assertHasDiagnostic("KSWIFTK-SEMA-DELEGATE", in: ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }
}
#endif
