#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaLangStringExposesJDKStaticAndInstanceMembers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                println(java.lang.String.valueOf(5))
                println(java.lang.String.valueOf(true))
                println(java.lang.String.valueOf("text"))
                println(java.lang.String.valueOf(charArrayOf('a', 'b')))
                println(java.lang.String.join("-", "a", "b"))
                println(java.lang.String.join("-", listOf("x", "y")))
                println(java.lang.String.format("%s:%d", "item", 3))
                println(java.lang.String.copyValueOf(charArrayOf('c', 'd')))
                println(java.lang.String.copyValueOf(charArrayOf('x', 'y', 'z'), 1, 2))
                val destination = charArrayOf('?', '?', '?', '?', '?')
                java.lang.String("abc").getChars(0, 3, destination, 1)
                println(destination.concatToString())
                println(java.lang.String("abc").contentEquals("abc"))
                println(java.lang.String("abc").regionMatches(1, "bc", 0, 2))
                val kotlinString: String = "kotlin"
                println(kotlinString.length)
            }
            """, expected: "5\ntrue\ntext\nab\na-b\nx-y\nitem:3\ncd\nyz\n?abc?\ntrue\ntrue\n6\n", mode: mode, root: root)
        }
    }

    @Test
    func kotlinStringDoesNotExposeJavaStaticMembers() throws {
        try withWorkspace { root in
            let result = try compile("fun main() { String.valueOf(5) }", root: root, mode: .jvmClass)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.message.contains("valueOf") })

            let instanceResult = try compile("fun main() { String(\"text\").getChars(0, 1, CharArray(1), 0) }", root: root, mode: .jvmClass)
            #expect(instanceResult.0 != 0)
        }
    }

    @Test
    func javaLangStringRemainsDistinctFromKotlinString() throws {
        try withWorkspace { root in
            let result = try compile("fun accept(value: java.lang.String) {}; fun main() { accept(\"text\") }", root: root, mode: .jvmClass)
            #expect(result.0 != 0)
        }
    }
}
#endif
