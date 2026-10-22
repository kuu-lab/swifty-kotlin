#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func implicitCharCodePropertiesUseTheirBoundReceivers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4(#"""
            operator fun Char.plus(s: String): Int = code + s.length
            class Other
            fun withOther(block: Other.() -> Int): Int = Other().block()
            fun withChar(value: Char, block: Char.() -> Int): Int = value.block()
            fun Char.read(): Int = code
            fun Char.explicit(): Int = this.code
            fun Char.outer(): Int = withOther { code }
            fun Char.inner(): Int = withChar('z') { code }
            fun Char.shadowed(): Int { val code = 7; return code }
            fun Char.captured(): () -> Int = { code }
            class Holder(val code: Int) {
                fun Char.total(): Int = code + this@Holder.code
                fun run(): Int = 'a'.total()
            }
            class Named(val code: Int) { fun read(): Int = code }
            fun source(): Char { print("C"); return 'a' }
            fun main() {
                println('a'.plus("bc"))
                println('a'.read()); println('a'.explicit())
                println('a'.outer()); println('a'.inner()); println('a'.shadowed())
                println(Holder(900).run()); println(Named(42).read())
                println('x'.captured()()); println(source().read())
                val present: Char? = 'a'
                val absent: Char? = null
                println(present?.read()); println(absent?.read())
                println('\uffff'.read()); println('\u0000'.read()); println('\ud83d'.read())
            }
            """#, expected: "99\n97\n97\n97\n122\n7\n997\n42\n120\nC97\n97\nnull\n65535\n0\n55357\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        "fun main() { println(code) }",
        "fun String.read(): Int = code",
        "fun main() { val code: String = \"x\"; val value: Int = code }",
        "fun main() { val value: String = 'a'.code }",
        "fun Char?.unsafe(): Int = code",
    ])
    func implicitCharCodeKeepsInvalidReceiverAndValueUsesRejected(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
