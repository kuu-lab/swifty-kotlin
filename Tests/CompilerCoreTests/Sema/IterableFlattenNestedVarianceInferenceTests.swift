@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite
struct IterableFlattenNestedVarianceInferenceTests {
    @Test
    func resolvesFlattenForNestedIterableSubtypes() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun flattenSets(): List<Int> = listOf(setOf(1)).flatten()
        fun flattenRanges(): List<Int> = listOf(1..3, 4..5).flatten()
        fun flattenSetValues(values: List<Set<Int>>): List<Int> = values.flatten()
        fun flattenRangeValues(values: List<IntRange>): List<Int> = values.flatten()
        fun flattenNestedLists(): List<Int> = listOf(listOf(1)).flatten()
        fun flattenTyped(values: Iterable<Iterable<Int>>): List<Int> = values.flatten()
        fun flattenDiscardedContext() {
            println(listOf(setOf(1)).flatten())
            println(listOf(1..3, 4..5).flatten())
        }
        """, allowDefaultStdlibLibrary: true)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
