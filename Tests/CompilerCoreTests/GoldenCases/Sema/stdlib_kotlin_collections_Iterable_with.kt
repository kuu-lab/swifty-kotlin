fun iterableWithIndex(values: Iterable<Int>): Iterable<IndexedValue<Int>> = values.withIndex()

fun listWithIndex(values: List<String>): Iterable<IndexedValue<String>> = values.withIndex()

fun nullableWithIndex(values: Iterable<String?>): Iterable<IndexedValue<String?>> = values.withIndex()
