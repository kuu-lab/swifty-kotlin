fun iterableFlatFamily(values: Iterable<Int>, nullableValues: Iterable<Int?>) {
    val iterableFlat: List<String> = values.flatMap { value ->
        listOf(value.toString(), "i" + value.toString())
    }
    val sequenceFlat: List<String> = values.flatMap { value ->
        sequenceOf(value.toString(), "s" + value.toString())
    }
    val iterableIndexed: List<String> = values.flatMapIndexed { index, value ->
        listOf(index.toString() + ":" + value.toString())
    }
    val sequenceIndexed: List<String> = values.flatMapIndexed { index, value ->
        sequenceOf(index.toString() + ":" + value.toString())
    }

    val iterableTo: MutableList<Any?> = values.flatMapTo(mutableListOf<Any?>("seed-i")) { value ->
        listOf(value)
    }
    val sequenceTo: MutableList<Any?> = values.flatMapTo(mutableListOf<Any?>("seed-s")) { value ->
        sequenceOf(value)
    }
    val iterableIndexedTo: MutableList<Any?> = values.flatMapIndexedTo(mutableListOf<Any?>("seed-ii")) { index, value ->
        listOf(index, value)
    }
    val sequenceIndexedTo: MutableList<Any?> = values.flatMapIndexedTo(mutableListOf<Any?>("seed-is")) { index, value ->
        sequenceOf(index, value)
    }

    val nullableResult: List<Int?> = nullableValues.flatMap { value -> listOf(value) }
}
