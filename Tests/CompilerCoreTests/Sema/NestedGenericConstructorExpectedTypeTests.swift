#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NestedGenericConstructorExpectedTypeTests {
    @Test func nestedConstructorUsesOuterParameterExpectedType() throws {
        let ctx = makeContextFromSources([
            """
            package lib
            interface Thing
            class Impl : Thing
            class Box<T>(val value: T)
            """,
            """
            package app
            import lib.*
            fun Thing(x: Int = 0): Impl = Impl()
            fun box(value: Box<Thing>) {}
            fun main() { box(Box(Thing())) }
            """,
        ])
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let boxCall = try #require(nameRefCallExprID(named: "Box", in: ast, interner: ctx.interner))
        let boxSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("lib"), ctx.interner.intern("Box")]))
        let thingSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("lib"), ctx.interner.intern("Thing")]))
        let thingType = sema.types.make(.classType(ClassType(
            classSymbol: thingSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedBoxType = sema.types.make(.classType(ClassType(
            classSymbol: boxSymbol,
            args: [.invariant(thingType)],
            nullability: .nonNull
        )))
        #expect(sema.bindings.exprType(for: boxCall) == expectedBoxType)
    }

    @Test func incompatibleNestedConstructorArgumentStillFails() throws {
        let ctx = makeContextFromSource("""
        interface Thing
        class Other
        class Box<T>(val value: T)
        fun accept(value: Box<Thing>) {}
        fun test() { accept(Box(Other())) }
        """)

        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
