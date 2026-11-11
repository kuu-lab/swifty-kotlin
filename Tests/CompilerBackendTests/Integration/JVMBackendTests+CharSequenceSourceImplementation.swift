#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11CharSequenceSourceImplementationDispatch(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            class Word(private val text: String) : CharSequence {
                override val length: Int get() = text.length
                override fun get(index: Int): Char = text[index]
                override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                    text.substring(startIndex, endIndex)
            }
            fun inspect(value: CharSequence) {
                println(value.length)
                println(value[1])
                println(value.subSequence(1, 3))
                val slice: CharSequence = value.subSequence(1, 3)
                println(slice.length)
                println(slice[0])
            }
            fun main() {
                println(Word("abc").length)
                inspect(Word("abc"))
                inspect("xyz")
                inspect(StringBuilder("123"))
            }
            """, expected: "3\n3\nb\nbc\n2\nb\n3\ny\nyz\n2\ny\n3\n2\n23\n2\n2\n", mode: mode, root: root)
        }
    }
}
#endif
