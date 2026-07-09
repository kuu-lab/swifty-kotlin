@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// Regression coverage for class-body-declared instance properties (i.e. not
/// primary constructor parameters) whose initializer must be written to the
/// instance's this-relative field offset rather than a global-style slot.
extension CodegenBackendIntegrationTests {
    func testCodegenClassInstanceMutableMapPropertyPersistsMutations() throws {
        let source = """
        class RegistryClass {
            val items: MutableMap<String, String> = mutableMapOf<String, String>()
            fun put(k: String, v: String) { items[k] = v }
            fun get(k: String): String? = items[k]
            fun size(): Int = items.size
        }

        fun main() {
            val rc = RegistryClass()
            rc.put("b", "2")
            println(rc.size())
            println(rc.get("b"))
        }
        """

        try assertKotlinOutput(source, moduleName: "ClassInstanceMutableMapProperty", expected: "1\n2\n")
    }

    func testCodegenClassInstanceNonZeroPrimitiveAndListPropertiesAreIndependentPerInstance() throws {
        let source = """
        class Counter {
            var count: Int = 5
            val history: MutableList<Int> = mutableListOf()
            fun increment() {
                count = count + 1
                history.add(count)
            }
        }

        fun main() {
            val a = Counter()
            println(a.count)
            a.increment()
            a.increment()
            println(a.count)
            println(a.history)

            val b = Counter()
            println(b.count)
            println(b.history)
        }
        """

        try assertKotlinOutput(
            source, moduleName: "ClassInstanceNonZeroPrimitiveAndListProperty",
            expected: "5\n7\n[6, 7]\n5\n[]\n"
        )
    }

    func testCodegenObjectLateinitAndCollectionPropertiesStillUseGlobalStorage() throws {
        let source = """
        class Payload(val value: String)

        object Cache {
            lateinit var current: Payload
            val log: MutableList<String> = mutableListOf()
            fun set(v: String) {
                current = Payload(v)
                log.add(v)
            }
            fun read(): String = current.value
        }

        fun main() {
            Cache.set("first")
            Cache.set("second")
            println(Cache.read())
            println(Cache.log)
        }
        """

        try assertKotlinOutput(source, moduleName: "ObjectLateinitAndCollectionProperty", expected: "second\n[first, second]\n")
    }

    func testCodegenClassInstanceLateinitPropertyIsPerInstance() throws {
        let source = """
        class Box(val label: String)

        class Holder {
            lateinit var box: Box
            fun assign(s: String) { box = Box(s) }
            fun read(): String = box.label
        }

        fun main() {
            val h1 = Holder()
            val h2 = Holder()
            h1.assign("one")
            h2.assign("two")
            println(h1.read())
            println(h2.read())
        }
        """

        try assertKotlinOutput(source, moduleName: "ClassInstanceLateinitProperty", expected: "one\ntwo\n")
    }
}
