fun main() {
    // A transform lambda's Boolean/Char result must stay boxed when a HOF
    // stores/forwards it into a generically-typed List for later rendering
    // Primitive-array source HOFs must preserve the type tag so these print as
    // true/false or the character rather than a raw 0/1 or code point.
    println(intArrayOf(1, 6, 3).map { it > 5 })
    println(booleanArrayOf(true, false).map { it == true })
    println(booleanArrayOf(true, false).map { it })
    println(booleanArrayOf(true, false).map { !it })
    println(charArrayOf('a', 'b').map { it })

    // Same bug class in the Sequence eager-fallback and lazy per-step map
    // paths (applyMapStep/runtimeApplyMapElement and the .mapStep/.mapIndexedStep
    // cases in runtimeSequenceTransformElement).
    println(sequenceOf(1, 6, 3).map { it > 5 }.toList())
    println(intArrayOf(1, 6, 3).asSequence().map { it > 5 }.toList())
    println(sequenceOf(1, 6, 3).mapIndexed { idx, v -> idx == 1 || v > 5 }.toList())

    // mapNotNull/mapIndexed share the same runtimeMapNotNullResultValue helper.
    println(listOf(1, 6, 3).mapNotNull { if (it > 10) null else it > 5 })
    println(listOf(1, 6, 3).mapIndexed { idx, v -> idx == 1 || v > 5 })
}
