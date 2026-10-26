#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AnonymousObjectMemberExtensionReceiverTests {
    @Test
    func extensionThisUsesDeclaredReceiverInAnonymousOverride() throws {
        let ctx = makeContextFromSource("""
        interface Unsafe { fun String.emit() }

        class Named : Unsafe {
            fun namedDispatch(): Int = 1

            override fun String.emit() {
                val receiver: String = this
                val dispatch: Int = namedDispatch()
            }
        }

        fun String.topLevelExtension() {
            val receiver: String = this
        }

        class Owner(val out: Appendable) {
            val target = object : Unsafe {
                fun objectDispatch(): Int = 2

                override fun String.emit() {
                    out.append(this)
                    val receiver: String = this
                    val dispatch: Int = objectDispatch()
                }

                fun regular() {
                    val receiver: Unsafe = this
                    val dispatch: Int = objectDispatch()
                }
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
