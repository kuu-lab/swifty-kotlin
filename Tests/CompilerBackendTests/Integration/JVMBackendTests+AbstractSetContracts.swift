#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func abstractSetsRetainSetInheritanceEqualityAndReadOnlyMarkers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            private class ProbeSet<E>(private val elements: List<E>): AbstractSet<E>() {
                override val size: Int get() = elements.size
                override fun iterator(): Iterator<E> = elements.iterator()
            }
            fun main() {
                val ordered = ProbeSet(listOf(1, 2, 3))
                val reordered = ProbeSet(listOf(3, 1, 2))
                val differentSize = ProbeSet(listOf(1, 2))
                val differentElements = ProbeSet(listOf(1, 2, 4))
                val withNull = ProbeSet(listOf<String?>(null, "a"))
                println(ordered == reordered); println(ordered.equals(reordered))
                println(ordered == differentSize); println(ordered == differentElements)
                println((ordered as Any) == listOf(1, 2, 3)); println(ordered.equals(null))
                println(ordered.hashCode() == reordered.hashCode())
                println(withNull.hashCode() == "a".hashCode())
                val set: Set<Int> = ordered
                println(set.size); println(set.contains(2)); println(set.toList().size)
                val erased: Any = ordered
                println(erased is Set<*>); println(erased is Collection<*>)
                println(erased is MutableSet<*>); println((erased as? MutableSet<Int>) == null)
                try { erased as MutableSet<Int>; println("bad") }
                catch (failure: ClassCastException) { println("readonly") }
            }
            """, expected: "true\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\ntrue\n3\ntrue\n3\ntrue\ntrue\nfalse\ntrue\nreadonly\n", mode: mode, root: root)
        }
    }
}
#endif
