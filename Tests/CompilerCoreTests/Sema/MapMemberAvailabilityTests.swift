@testable import CompilerCore
import Foundation
import Testing

/// KUU-1362: `Map<K, V>` is not an `Iterable` in Kotlin. Iterable/Collection-only
/// members must be rejected in Sema (unresolved member) instead of binding a
/// result type with no callee and lowering to an undefined symbol (LINK-0001)
/// or a wrong runtime bridge. The issue's minimal repro was
/// `mapOf("a" to 1, "b" to null).filterNotNull()`, which kotlinc rejects with
/// `unresolved reference`; the same phantom-claim class covered fold/first/
/// groupBy/zip/requireNoNulls/... on a Map receiver.
@Suite
struct MapMemberAvailabilityTests {
    @Test
    func iterableOnlyMembersAreRejectedOnMapReceiver() throws {
        let expressions = [
            "m.filterNotNull()",
            "m.filterNotNullTo(mutableListOf())",
            "m.filterIsInstance<Any>()",
            "m.fold(0) { acc, e -> acc }",
            "m.first()",
            "m.last()",
            "m.singleOrNull()",
            "m.distinct()",
            "m.withIndex().toList()",
            "m.mapIndexed { i, _ -> i }",
            "m.forEachIndexed { i, _ -> println(i) }",
            "m.groupBy { it.value }",
            "m.partition { it.value > 0 }",
            "m.zip(listOf(1))",
            "m.unzip()",
            "m.takeWhile { it.value > 0 }",
            "m.dropWhile { it.value > 0 }",
            "m.joinToString(\",\")",
            "m.shuffled()",
            "m.reversed()",
            "m.toCollection(mutableListOf())",
            "m.toMutableList()",
            "m.toTypedArray()",
            "m.requireNoNulls()",
            "m.sumOf { it.value }",
            "m.indexOfFirst { it.value > 0 }",
            "m.containsAll(listOf(1))",
            "m.elementAt(0)",
            "m.find { it.value > 0 }",
        ]
        let sources = expressions.enumerated().map { index, expression in
            """
            package rejected\(index)
            fun probe(m: Map<String, Int?>, mm: MutableMap<String, Int?>) {
                \(expression)
            }
            """
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(!errors.isEmpty, "Expected rejection of \(expressions[index])")
                #expect(
                    errors.contains { $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-0003"
                        || $0.code == "KSWIFTK-TYPE-0001" },
                    "Expected member/overload diagnostic for \(expressions[index]), got \(errors)"
                )
            }
        }
    }

    @Test
    func validMapOperationsRemainAvailable() throws {
        let source = """
        fun probe(m: Map<String, Int?>, mm: MutableMap<String, Int?>) {
            val filtered: Map<String, Int?> = m.filter { it.value != null }
            val byKey = m.filterKeys { it.isNotEmpty() }
            val byValue = m.filterValues { it == null }
            val mapped: List<Int> = m.mapNotNull { it.value }
            val keys = m.mapKeys { it.key + "!" }
            val values = m.mapValues { it.value ?: 0 }
            val anyHit: Boolean = m.any { it.value != null }
            val allHit: Boolean = m.all { it.value != null }
            val noneHit: Boolean = m.none { it.value != null }
            val count: Int = m.count()
            val hasA: Boolean = m.contains("a")
            val hasKey: Boolean = m.containsKey("a")
            val hasValue: Boolean = m.containsValue(1)
            val got: Int? = m.get("a")
            val gotValue: Int? = m.getValue("a")
            val gotDefault: Int? = m.getOrDefault("a", 0)
            val gotElse: Int? = m.getOrElse("a") { 0 }
            val iterated = m.iterator()
            m.forEach { println(it.key) }
            m.onEach { println(it.key) }
            val asSeq = m.asSequence()
            val asIter = m.asIterable()
            val list = m.toList()
            val mapCopy = m.toMap()
            val mutableCopy = m.toMutableMap()
            val notEmpty: Boolean = m.isNotEmpty()
            val nullOrEmpty: Boolean = m.isNullOrEmpty()
            val flat: List<Int> = m.flatMap { listOf(it.value ?: 0) }
            val toDest = m.mapTo(mutableListOf()) { it.key }
            val filterDest = m.filterTo(mutableMapOf()) { it.value != null }
            val flatDest = m.flatMapTo(mutableListOf()) { listOf(it.value ?: 0) }
            val firstNN = m.firstNotNullOfOrNull { it.value }
            val biggest = m.maxByOrNull { it.value ?: 0 }
            val plus = m + ("c" to 3)
            val minus = m - "a"
            mm.putAll(m)
            val orPut = mm.getOrPut("z") { 0 }
            val removed = mm.remove("a")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected valid Map calls: \(errors)")
        }
    }
}
