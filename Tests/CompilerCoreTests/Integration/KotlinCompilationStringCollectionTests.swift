#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Integration tests for the String stdlib extensions and mutable collection
/// operations added or improved in this PR (string-stdlib-and-runtime-parity).
@Suite struct KotlinCompilationStringCollectionTests {
    // MARK: - String case conversion

    @Test func testCompile_string_lowercase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "Hello World"
            val lower = s.lowercase()
        }
        """)
    }

    @Test func testCompile_string_uppercase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello world"
            val upper = s.uppercase()
        }
        """)
    }

    @Test func testCompile_string_localeAwareOperations() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val lower = "I".lowercase(Locale("tr"))
            val upper = "i".uppercase(Locale("tr"))
            val cmp = lower.compareTo(upper, Locale("en_US"))
        }
        """)
    }

    @Test func testCompile_string_normalize() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "e\\u0301"
            val normalized = s.normalize(NormalizationForms.NFC)
            val stable = normalized.isNormalized(NormalizationForms.NFC)
        }
        """)
    }

    // MARK: - String nullable conversions

    @Test func testCompile_string_toIntOrNull_validInput() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Int? = "42".toIntOrNull()
        }
        """)
    }

    @Test func testCompile_string_toIntOrNull_invalidInput() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Int? = "abc".toIntOrNull()
        }
        """)
    }

    @Test func testCompile_string_toDoubleOrNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Double? = "3.14".toDoubleOrNull()
        }
        """)
    }

    @Test func testCompile_string_toBigDecimal() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigDecimal

        fun main() {
            val result: BigDecimal = "3.14e2".toBigDecimal()
            val text = result.toString()
        }
        """)
    }

    @Test func testCompile_string_toBigInteger() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val result: BigInteger = "12345678901234567890".toBigInteger()
            val text = result.toString()
        }
        """)
    }

    // MARK: - String search

    @Test func testCompile_string_indexOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello world"
            val idx = s.indexOf("world")
        }
        """)
    }

    @Test func testCompile_string_lastIndexOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "aababc"
            val idx = s.lastIndexOf("ab")
        }
        """)
    }

    // MARK: - String transformation

    @Test func testCompile_string_repeat() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "ab".repeat(3)
        }
        """)
    }

    @Test func testCompile_string_reversed() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".reversed()
        }
        """)
    }

    @Test func testCompile_string_toList() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val chars = "hello".toList()
        }
        """)
    }

    // MARK: - STDLIB-TEXT-FN-108: String.toSortedSet()

    @Test func testCompile_string_toSortedSet() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val chars = "hello".toSortedSet()
        }
        """)
    }

    @Test func testCompile_charSequence_toSortedSet() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val text: CharSequence = "hello"
            val chars: Set<Char> = text.toSortedSet()
        }
        """)
    }

    // MARK: - String padding

    @Test func testCompile_string_padStart() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "42".padStart(5, '0')
        }
        """)
    }

    @Test func testCompile_string_padEnd() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hi".padEnd(5, '-')
        }
        """)
    }

    // MARK: - String slicing

    @Test func testCompile_string_drop() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".drop(2)
        }
        """)
    }

    @Test func testCompile_string_take() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".take(3)
        }
        """)
    }

    @Test func testCompile_string_dropLast() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".dropLast(2)
        }
        """)
    }

    @Test func testCompile_string_takeLast() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".takeLast(3)
        }
        """)
    }

    // MARK: - Mutable collections

    @Test func testCompile_collection_mutableListOf_addRemove() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = mutableListOf(1, 2, 3)
            list.add(4)
            list.removeAt(0)
        }
        """)
    }

    @Test func testCompile_collection_mutableListOf_clear() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = mutableListOf("a", "b", "c")
            list.clear()
        }
        """)
    }

    @Test func testCompile_collection_setOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = setOf(1, 2, 3)
            val has = s.contains(2)
        }
        """)
    }

    @Test func testCompile_collection_mutableSetOf_addRemove() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = mutableSetOf(1, 2)
            s.add(3)
            s.remove(1)
        }
        """)
    }

    @Test func testCompile_collection_mutableMapOf_putRemove() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val m = mutableMapOf("a" to 1)
            m.put("b", 2)
            m.remove("a")
        }
        """)
    }

    @Test func testCompile_collection_buildMap() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val m = buildMap {
                put("a", 1)
                put("b", 2)
            }
        }
        """)
    }

    @Test func testCompile_collection_listConversions() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = listOf(3, 1, 2)
            val mutable = list.toMutableList()
            val set = list.toSet()
            val sorted = list.sorted()
            val reversed = list.reversed()
        }
        """)
    }

    @Test func testCompile_collection_listSortingHOFs() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = listOf(3, 1, 2)
            val byValue = list.sortedBy { it }
            val byDescending = list.sortedByDescending { it }
            val withComparator = list.sortedWith { a, b -> b - a }
            val shuffled = list.shuffled()
            val reversed = list.reversed()
        }
        """)
    }

    // MARK: - MIGRATION-SEQ-003: Sequence terminal HOFs

    func testCompile_sequence_toList() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(1, 2, 3)
            val list: List<Int> = seq.toList()
        }
        """)
    }

    func testCompile_sequence_toMutableList() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf("a", "b", "c")
            val list: MutableList<String> = seq.toMutableList()
        }
        """)
    }

    func testCompile_sequence_toSet() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(1, 2, 2, 3)
            val set: Set<Int> = seq.toSet()
        }
        """)
    }

    func testCompile_sequence_first() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(10, 20, 30)
            val f: Int = seq.first()
        }
        """)
    }

    func testCompile_sequence_firstOrNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(10, 20, 30)
            val f: Int? = seq.firstOrNull()
        }
        """)
    }

    func testCompile_sequence_last() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(10, 20, 30)
            val l: Int = seq.last()
        }
        """)
    }

    func testCompile_sequence_lastOrNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(10, 20, 30)
            val l: Int? = seq.lastOrNull()
        }
        """)
    }

    func testCompile_sequence_single() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(42)
            val s: Int = seq.single()
        }
        """)
    }

    func testCompile_sequence_count() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(1, 2, 3)
            val n: Int = seq.count()
        }
        """)
    }

    func testCompile_sequence_any_noArg() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(1, 2, 3)
            val hasElements: Boolean = seq.any()
        }
        """)
    }

    func testCompile_sequence_any_predicate() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(1, 2, 3)
            val hasEven: Boolean = seq.any { it % 2 == 0 }
        }
        """)
    }

    func testCompile_sequence_all_predicate() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(2, 4, 6)
            val allEven: Boolean = seq.all { it % 2 == 0 }
        }
        """)
    }

    func testCompile_sequence_none_noArg() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = emptySequence<Int>()
            val isEmpty: Boolean = seq.none()
        }
        """)
    }

    func testCompile_sequence_none_predicate() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val seq = sequenceOf(1, 3, 5)
            val noEven: Boolean = seq.none { it % 2 == 0 }
        }
        """)
    }

    // MARK: - Chained string operations

    @Test func testCompile_string_chainedOperations() throws {
        try assertKotlinCompilesToKIR("""
        fun normalize(s: String): String {
            return s.trim().lowercase()
        }
        fun main() { normalize("  Hello  ") }
        """)
    }

    @Test func testCompile_string_nullableChain() throws {
        try assertKotlinCompilesToKIR("""
        fun tryParse(s: String?): Int {
            return s?.toIntOrNull() ?: 0
        }
        fun main() { tryParse("42") }
        """)
    }
}
#endif
