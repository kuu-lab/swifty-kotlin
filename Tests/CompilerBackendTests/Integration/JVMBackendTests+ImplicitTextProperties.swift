#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func implicitTextLengthPropertiesUseTheirBoundReceivers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            class Other
            fun withOther(block: Other.() -> Int): Int = Other().block()
            fun String.implicitLength(): Int = length
            fun CharSequence.sequenceLength(): Int = length
            fun String.nestedLength(): Int = withOther { length }
            fun String.shadowedLength(): Int { val length = 7; return length }
            class Holder(val length: Int) {
                fun String.score(): Int = length
                fun run(): Int = "text".score()
            }
            fun main() {
                println("a😀".implicitLength())
                val sequence: CharSequence = "text"
                println(sequence.sequenceLength())
                println("outer".nestedLength())
                println("x".shadowedLength())
                println(Holder(900).run())
            }
            """, expected: "3\n4\n5\n7\n4\n", mode: mode, root: root)
        }
    }
}
#endif
