@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrivateMemberExtensionTests {
    @Test(arguments: [false, true])
    func stringHelperResolvesInsideItsDeclaringClass(nested: Bool) throws {
        let host = """
        class Host {
            private fun String.helper(): String = this
            fun use(s: String) = s.helper()
            fun use2() = "x".helper()
        }
        """
        let ctx = makeContextFromSource(nested ? "class Outer { \(host) }" : host)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let helper = try findKIRFunction(named: "helper", in: module, interner: ctx.interner)
        #expect(helper.params.count == 2)
        #expect(helper.params[1].type == sema.types.stringType)
        #expect(sema.symbols.memberExtensionOwnerSymbol(for: helper.symbol) != nil)
        for name in ["use", "use2"] {
            let function = try findKIRFunction(named: name, in: module, interner: ctx.interner)
            #expect(function.returnType == sema.types.stringType)
            #expect(function.body.contains { instruction in
                guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == helper.symbol && arguments.count == 2
            })
        }
    }

    /// KUU-3746: `C().length` must resolve to the member `length`, not the
    /// same-named private member extension `Box.length` — the extension is
    /// never applicable (its receiver is `Box`, not `C`) and is invisible
    /// outside `C` anyway, so its privacy must not be diagnosed.
    @Test
    func memberAccessPrefersMemberOverPrivateMemberExtension() throws {
        let ctx = makeContextFromSource("""
        class Box(val size: Int)
        class C {
            private val Box.length: Int
                get() = size
            val length: Int get() = 2
        }
        fun main() = println(C().length)
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let memberProperties = sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("C"), ctx.interner.intern("length"),
        ]).filter { candidate in
            sema.symbols.symbol(candidate)?.kind == .property
                && sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil
        }
        let member = try #require(memberProperties.first)
        #expect(sema.bindings.identifierSymbols.values.contains(member))
    }

    /// The member extension remains reachable where both receivers exist:
    /// `b.length` inside a `C` member binds the private extension getter.
    @Test
    func memberExtensionResolvesInsideDeclaringClass() throws {
        let ctx = makeContextFromSource("""
        class Box(val size: Int)
        class C {
            private val Box.length: Int
                get() = size
            fun read(b: Box) = b.length
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    /// A member extension that is applicable via an implicit dispatch
    /// receiver must still report its `private` visibility from outside the
    /// declaring class — only non-applicable extension candidates are
    /// discarded before the access check (KUU-3746).
    @Test
    func privateMemberExtensionGetterStillErrorsFromOutside() throws {
        let ctx = makeContextFromSource("""
        class Box(val size: Int)
        class C {
            private val Box.length: Int
                get() = size
        }
        fun main() {
            val c = C()
            with(c) { println(Box(3).length) }
        }
        """)
        try runSema(ctx)

        let privateAccessErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0040"
        }
        #expect(privateAccessErrors.count == 1, "\(ctx.diagnostics.diagnostics)")
    }

    /// Same FQName shape without the private modifier: the member still
    /// wins over the non-private member extension on `C().length`.
    @Test
    func memberAccessPrefersMemberOverNonPrivateMemberExtension() throws {
        let ctx = makeContextFromSource("""
        class Box(val size: Int)
        class C {
            val Box.length: Int
                get() = size
            val length: Int get() = 2
        }
        fun main() = println(C().length)
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let memberProperties = sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("C"), ctx.interner.intern("length"),
        ]).filter { candidate in
            sema.symbols.symbol(candidate)?.kind == .property
                && sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil
        }
        let member = try #require(memberProperties.first)
        #expect(sema.bindings.identifierSymbols.values.contains(member))
    }

    @Test
    func privateMemberExtensionSetterUsesLexicalClassVisibility() throws {
        let ctx = makeContextFromSource("""
        class Owner {
            var Int.value: String
                get() = "before"
                private set(value) {}

            fun writeFromLocalClass() {
                class Local {
                    fun write() { 42.value = "inside" }
                }
                Local().write()
            }
        }

        fun withOwner(owner: Owner, block: Owner.() -> Unit) { owner.block() }

        class Outsider {
            fun write(owner: Owner) {
                withOwner(owner) { 42.value = "outside" }
            }
        }
        """)
        try runSema(ctx)

        let privateAccessErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0040" }
        #expect(privateAccessErrors.count == 1, "\(ctx.diagnostics.diagnostics)")
    }
}
