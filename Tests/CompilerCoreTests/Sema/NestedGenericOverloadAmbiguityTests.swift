#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NestedGenericOverloadAmbiguityTests {
    @Test func nestedConstructorKeepsEachOverloadCandidateContext() throws {
        let ctx = makeContextFromSource("""
        interface Thing
        class Impl : Thing
        class Box<T>(val value: T)
        fun choose(value: Box<Thing>, tag: Any?) {}
        fun choose(value: Box<Impl>, tag: String) {}
        fun main() {
            val tag: Any? = null
            choose(Box(Impl()), tag)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let boxCall = try #require(nameRefCallExprID(named: "Box", in: ast, interner: ctx.interner))
        let boxSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Box")]))
        let thingSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Thing")]))
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

    @Test func nestedConstructorDoesNotHideAmbiguousOverloads() throws {
        let ctx = makeContextFromSource("""
        interface Thing
        class Impl : Thing
        class Box<T>(val value: T)
        fun choose(value: Box<Thing>, tag: Any?) {}
        fun choose(value: Box<Impl>, tag: String) {}
        fun main() { choose(Box(Impl()), "tag") }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1, "Expected overload ambiguity: \(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "Did not expect a no-viable-overload diagnostic: \(errors)")
    }
}
#endif
