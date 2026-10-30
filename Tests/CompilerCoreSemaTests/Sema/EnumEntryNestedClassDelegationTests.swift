#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct EnumEntryNestedClassDelegationTests {
    // KUU-3672: a class nested inside an enum entry's anonymous class body is
    // not part of the enum's `nestedClasses`/`nestedObjects` — its declIDs live
    // on `EnumEntryDecl.nestedClasses`. They still need the same class
    // delegation registration (delegated interfaces, `$delegate_*` storage,
    // forwarding members) as any other nested class.
    @Test
    func innerClassDelegationRegistersInterfaceStorageAndForwarders() throws {
        let ctx = makeContextFromSource("""
        interface IFoo { fun foo(): String }
        interface IBar { fun bar(): String }
        enum class Test : IFoo, IBar {
            FOO {
                inner class Inner : IFoo by FOO
                val z = Inner()
                override fun foo() = "OK"
                override fun bar() = z.foo()
            }
        }
        fun box() = Test.FOO.bar()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let innerSymbol = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Test"),
            ctx.interner.intern("FOO"),
            ctx.interner.intern("Inner"),
        ]))
        let interfaces = sema.symbols.delegatedInterfaces(forClass: innerSymbol)
        #expect(interfaces.count == 1)
        let interface = try #require(interfaces.first)
        #expect(sema.symbols.classDelegationExpr(forClass: innerSymbol, interface: interface) != nil)
        #expect(sema.symbols.classDelegationField(forClass: innerSymbol, interface: interface) != nil)
        #expect(!sema.symbols.classDelegationForwardingMethodSymbols(forClass: innerSymbol).isEmpty)
    }
}
#endif
