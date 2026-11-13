#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func arrayAsListLinksAgainstOwnStdlibAndSharesStorage() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println(emptyArray<String>().asList())
                val array = arrayOf<String?>("first", null)
                val view = array.asList()
                println(view)
                array[0] = "second"
                println(view)
                val mutableView = view as MutableList<String?>
                mutableView[1] = "third"
                println(array[1])
                try {
                    mutableView.add("extra")
                } catch (_: UnsupportedOperationException) {
                    println("fixed size")
                }
            }
            """, expected: "[]\n[first, null]\n[second, null]\nthird\nfixed size\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
