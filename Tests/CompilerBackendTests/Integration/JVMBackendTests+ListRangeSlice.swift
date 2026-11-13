#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func listRangeSliceCopiesElementsAndChecksBounds() throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val list = mutableListOf("first", "second", "third")
                val middle = list.slice(1..2)
                list[1] = "changed"
                println(middle)
                println(list.slice(9..8))
                try {
                    list.slice(1..3)
                } catch (e: IndexOutOfBoundsException) {
                    println("bounds")
                }
            }
            """, expected: "[second, third]\n[]\nbounds\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
