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
