@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMutableSetBulkDispatchTests {
    @Test(arguments: [true, false])
    func bulkMutationsDispatchToCustomSetAndPropagateThrows(artifact: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/ksp1077_custom_mutable_set_bulk.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "MutableSetBulkDispatch",
            expected: "true\nfalse\nfalse\ntrue\nfalse\ntrue\n2\ntrue\nfalse\nfalse\ntrue\n1\nremoveAll-override\nretainAll-override\n1\ntrue\nfalse\n0\nRRRTTRTTT\ntrue\nfalse\ntrue\nfalse\n1\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func inheritedAbstractMutableSetBulkImplementationsDispatch(artifact: Bool) throws {
        try assertKotlinOutput("""
        class InheritedSet : AbstractMutableSet<Int>() {
            val backing = mutableSetOf(1, 2, 3)
            override val size: Int get() = backing.size
            override fun iterator(): MutableIterator<Int> = backing.iterator()
            override fun add(element: Int): Boolean = backing.add(element)
        }
        fun main() {
            val source = InheritedSet()
            val set: MutableSet<Int> = source
            println(set.removeAll(listOf(2, 2)))
            println(set.removeAll(listOf(2)))
            println(set.retainAll(listOf(3)))
            println(set.retainAll(listOf(3)))
            println(set.size)
            println(set.contains(3))
        }
        """, moduleName: "InheritedSetBulk", expected: "true\nfalse\ntrue\nfalse\n1\ntrue\n",
        allowDefaultStdlibLibrary: artifact)
    }

    @Test(arguments: [true, false])
    func nativeDefaultBulkBodiesDoNotReenterTheirBridge(artifact: Bool) throws {
        // Native MutableSet has intentional bridge defaults absent on JVM MutableSet.
        try assertKotlinOutput("""
        class DefaultSet : MutableSet<Int> {
            val backing = mutableSetOf(1, 2, 3)
            override val size: Int get() = backing.size
            override fun isEmpty(): Boolean = backing.isEmpty()
            override fun contains(element: Int): Boolean = backing.contains(element)
            override fun containsAll(elements: Collection<Int>): Boolean = backing.containsAll(elements)
            override fun iterator(): MutableIterator<Int> = backing.iterator()
            override fun add(element: Int): Boolean = backing.add(element)
            override fun addAll(elements: Collection<Int>): Boolean = backing.addAll(elements)
            override fun remove(element: Int): Boolean = backing.remove(element)
            override fun clear() { backing.clear() }
        }
        fun main() {
            val set: MutableSet<Int> = DefaultSet()
            println(set.removeAll(listOf(2)))
            println(set.retainAll(listOf(3)))
            println(set.size)
            println(set.contains(2))
        }
        """, moduleName: "DefaultSetBulk", expected: "false\nfalse\n3\ntrue\n",
        allowDefaultStdlibLibrary: artifact)
    }
}
