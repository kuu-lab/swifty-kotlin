#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    // `for` over a concrete JDK map type (LinkedHashMap, HashMap, SortedMap) used to
    // call java/lang/Iterable.iterator and fail with IncompatibleClassChangeError.
    @Test
    func forLoopOverConcreteJDKMapIteratesEntries() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                val linked = linkedMapOf("b" to 2, "a" to 1)
                for ((key, value) in linked) println("$key=$value")
                for (entry in linked) println(entry.key + entry.value)
                val hashed = hashMapOf("x" to 1)
                for ((key, value) in hashed) println("$key:$value")
                val sorted = sortedMapOf("z" to 26, "y" to 25)
                for ((key, value) in sorted) println("$key$value")
            }
            """, expected: "b=2\na=1\nb2\na1\nx:1\ny25\nz26\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
