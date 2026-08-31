fun probe(
    values: Iterable<Int>,
    nullable: Iterable<String?>,
    list: List<Int>
) {
    val iterableFold = values.fold(0) { acc, value -> acc + value }
    val iterableFoldIndexed = values.foldIndexed("") { index, acc, value -> "$acc$index:$value" }
    val nullableInitial: String? = null
    val nullableFold = nullable.fold(nullableInitial) { acc, value -> (acc ?: "") + (value ?: "") }
    val listFold = list.fold(1) { acc, value -> acc * value }
    val listFoldIndexed = list.foldIndexed(0) { index, acc, value -> acc + index * value }
}
