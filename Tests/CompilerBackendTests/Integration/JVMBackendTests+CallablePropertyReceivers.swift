#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func callablePropertiesSeparateDispatchAndFunctionReceivers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            class Converter(private val action: Int.() -> String) {
                fun lexical(value: Int): String = value.action()
                fun explicit(value: Int): String = action.invoke(value)
                fun snapshot(value: Int): String { val callback = action; return callback(value) }
            }
            class Holder(val action: Int.() -> String)
            var reads = 0
            val tracked: String.(Int) -> String
                get() { reads += 1; return { n -> this + n.toString() } }
            inline fun inlineReceiver(value: Int, action: Int.() -> String): String = value.action()
            fun main() {
                val converter = Converter { "n=" + this.toString() }
                println(converter.lexical(7))
                println(converter.explicit(8))
                println(converter.snapshot(9))
                val holder = Holder { "h=" + this.toString() }
                println(holder.action(10))
                println(holder.action.invoke(11))
                println(inlineReceiver(12) { "i=" + this.toString() })
                val absent: String? = null
                println(absent?.tracked(1)); println(reads)
                println("x".tracked(2)); println(reads)
                val present: String? = "y"
                println(present?.tracked(3)); println(reads)
            }
            """, expected: "n=7\nn=8\nn=9\nh=10\nh=11\ni=12\nnull\n0\nx2\n1\ny3\n2\n", mode: mode, root: root)
        }
    }
}
#endif
