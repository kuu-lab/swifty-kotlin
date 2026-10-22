#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func memberExtensionsPreferTheirOwnReceiverForUnqualifiedMembers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            open class Base(protected val value: Int) {
                fun read(): Int = value
            }
            open class Owner(value: Int) : Base(value) {
                fun Owner.direct(): Int = read() + this@Owner.read()
                fun Owner.capture(): () -> Int = { read() + this@Owner.read() }
                fun <T : Owner> T.generic(): Int = read() + this@Owner.read()
                fun Owner.peer(): Int = read() + this@Owner.read()
                fun Owner.forward(): Int = this.peer()
                fun run(other: Owner) {
                    println(other.direct())
                    println(other.capture()())
                    println(other.generic())
                    println(other.forward())
                }
            }
            class Offset(private val offset: Int) {
                fun Offset.direct(): Int = offset + this@Offset.offset
                fun readOffset(): Int = offset
                fun Offset.method(): Int = readOffset() + this@Offset.offset
                fun Offset.capture(): () -> Int = { offset + this@Offset.offset }
                fun Offset.defaulted(extra: Int = offset): Int = extra + this@Offset.offset
                fun run(other: Offset) {
                    println(other.direct())
                    println(other.method())
                    println(other.capture()())
                    println(other.defaulted())
                }
            }
            fun main() { Offset(10).run(Offset(4)); Owner(10).run(Owner(4)) }
            """, expected: "14\n14\n14\n14\n14\n14\n14\n8\n", mode: mode, root: root)
        }
    }
}
#endif
