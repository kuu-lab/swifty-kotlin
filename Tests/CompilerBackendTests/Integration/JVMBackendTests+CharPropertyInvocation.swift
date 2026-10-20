#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func charPropertyNamesPreserveUserExtensionInvocations(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun Char.code(): Int { print("F"); return this.code + 10 }
            operator fun Int.invoke(): Int = this + 1000
            fun Char.implicit(): Int = code()
            fun Char.category(): Int = 20
            fun Char.directionality(): Int = 30
            fun source(): Char { print("R"); return 'a' }
            fun main() {
                println('a'.code())
                println('a'.code)
                println(source().code())
                val present: Char? = 'b'
                val absent: Char? = null
                println(present?.code()); println(absent?.code())
                println('a'.category()); println('a'.directionality())
                println('a'.implicit())
            }
            """, expected: "F107\n97\nRF107\nF108\nnull\n20\n30\nF107\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func charCodePropertyValuesInvokeAfterOneReceiverRead(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            operator fun Int.invoke(delta: Int = 20): Int { print("I"); return this + delta }
            fun source(): Char { print("R"); return 'a' }
            fun argument(): Int { print("A"); return 3 }
            class Callbacks { val callback: () -> Int = { 7 } }
            fun main() {
                println('a'.code())
                println(source().code(argument()))
                val present: Char? = 'b'
                val absent: Char? = null
                println(present?.code()); println(absent?.code(argument()))
                println(('a'.code)())
                println(Callbacks().callback())
            }
            """, expected: "I117\nRAI100\nI118\nnull\nI117\n7\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        "fun main() { println('a'.code()) }",
        "fun main() { val value: Char? = 'a'; println(value?.code()) }",
    ])
    func charCodePropertyCannotBeInvokedWithoutAUserFunction(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
