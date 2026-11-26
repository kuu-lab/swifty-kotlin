#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    // HashMap iteration order depends on its table size, so the repository
    // stdlib's hashMapOf must size the map like kotlin-stdlib does, including
    // maps that start empty and grow afterwards.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func hashMapOfIterationOrderMatchesKotlinStdlibAfterGrowth(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                val keys = listOf("z", "a", "q", "b", "y", "c", "p")

                val empty = hashMapOf<String, Int>()
                for (k in keys) empty.put(k, k.length)
                println(empty)

                val noPairs: HashMap<String, Int> = hashMapOf(*arrayOf<Pair<String, Int>>())
                for (k in keys) noPairs.put(k, k.length)
                println(noPairs)

                val one = hashMapOf("z" to 0)
                for (k in keys.drop(1)) one.put(k, k.length)
                println(one)

                println(hashMapOf("z" to 5, "a" to 1, "b" to 2, "c" to 3))
            }
            """, expected: "{p=1, a=1, q=1, b=1, c=1, y=1, z=1}\n{p=1, a=1, q=1, b=1, c=1, y=1, z=1}\n{p=1, a=1, q=1, b=1, c=1, y=1, z=0}\n{a=1, z=5, b=2, c=3}\n", mode: mode, root: root)
        }
    }
}
#endif
