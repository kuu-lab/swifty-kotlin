#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// KUU-4071: member `equals(other: Any?)` on a non-null scalar receiver must
/// box through its wrapper and dispatch `java/util/Objects.equals`, matching
/// kotlinc. Previously the JVM backend rejected it with
/// `KSWIFTK-JVM-0001: Unsupported JVM member: equals`.
extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func scalarMemberEqualsBoxesReceiverAndArgument(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                println('a'.equals('b'))
                println('a'.equals('a'))
                val c: Char = 'x'
                println(c.equals('x'))
                println(c.equals('y'))
                println(c.equals("x"))
                println(c.equals(null))
                println(c.equals(120))
                println('a'.equals(97))
                println(1.equals(1))
                println(1.equals(1L))
                println(1L.equals(1L))
                println(true.equals(true))
                println(true.equals(1))
                println(1.5.equals(1.5))
                println(1.5f.equals(1.5f))
                println(Double.NaN.equals(Double.NaN))
                println((-0.0).equals(0.0))
                println(127.toByte().equals(127.toByte()))
                println(1.toShort().equals(1.toShort()))
            }
            """, expected: "false\ntrue\ntrue\nfalse\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func scalarMemberEqualsOnNullableReceivers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val nc: Char? = 'x'
                println(nc?.equals('x'))
                println(nc?.equals('y'))
                val missing: Char? = null
                println(missing?.equals('x'))
                println((nc as Any?)?.equals('x'))
                val ni: Int? = 5
                println(ni?.equals(5))
                println(ni?.equals(5L))
            }
            """, expected: "true\nfalse\nnull\ntrue\ntrue\nfalse\n", mode: mode, root: root)
        }
    }
}
#endif
