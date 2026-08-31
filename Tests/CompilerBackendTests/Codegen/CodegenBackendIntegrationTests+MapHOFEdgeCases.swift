#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMapHOFEdgeCasesTests {

    @Test func testCodegenMapGetOrDefaultReturnsExistingKey() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2)
            println(map.getOrDefault("a", 99))
            println(map.getOrDefault("b", 99))
        }
        """
        try assertKotlinOutput(source, moduleName: "MapGetOrDefaultKeyPresent", expected: "1\n2\n")
    }

    @Test func testCodegenMapGetOrDefaultReturnsDefaultWhenKeyAbsent() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2)
            println(map.getOrDefault("z", 99))
        }
        """
        try assertKotlinOutput(source, moduleName: "MapGetOrDefaultKeyAbsent", expected: "99\n")
    }

    @Test func testCodegenMapGetOrDefaultWithEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            println(empty.getOrDefault("key", 42))
        }
        """
        try assertKotlinOutput(source, moduleName: "MapGetOrDefaultEmptyMap", expected: "42\n")
    }

    @Test func testCodegenMapFlatMapTransformsAllEntries() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2)
            val result = map.flatMap { listOf("${it.key}:${it.value}") }
            println(result)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapFlatMapTransformsAllEntries", expected: "[a:1, b:2]\n")
    }

    @Test func testCodegenMapFlatMapWithEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.flatMap { listOf("${it.key}:${it.value}") }
            println(result)
            println(result.size)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapFlatMapEmptyMap", expected: "[]\n0\n")
    }

    @Test func testCodegenMapMapNotNullFiltersNullResults() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
            val result = map.mapNotNull { if (it.value > 1) "${it.key}:${it.value}" else null }
            println(result)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapMapNotNullFiltersNulls", expected: "[b:2, c:3]\n")
    }

    @Test func testCodegenMapMapNotNullWithEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.mapNotNull { "${it.key}:${it.value}" }
            println(result)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapMapNotNullEmptyMap", expected: "[]\n")
    }

    @Test func testCodegenMapMaxByOrNullReturnsNullForEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.maxByOrNull { it.value }
            println(result)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapMaxByOrNullEmptyMap", expected: "null\n")
    }

    @Test func testCodegenMapMaxByOrNullReturnsEntryWithMaxSelector() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 3, "c" to 2)
            val entry = map.maxByOrNull { it.value }
            println(entry?.key)
            println(entry?.value)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapMaxByOrNullNonEmpty", expected: "b\n3\n")
    }

    @Test func testCodegenMapMinByOrNullReturnsNullForEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.minByOrNull { it.value }
            println(result)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapMinByOrNullEmptyMap", expected: "null\n")
    }

    @Test func testCodegenMapMinByOrNullReturnsEntryWithMinSelector() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 3, "b" to 1, "c" to 2)
            val entry = map.minByOrNull { it.value }
            println(entry?.key)
            println(entry?.value)
        }
        """
        try assertKotlinOutput(source, moduleName: "MapMinByOrNullNonEmpty", expected: "b\n1\n")
    }
}
#endif
