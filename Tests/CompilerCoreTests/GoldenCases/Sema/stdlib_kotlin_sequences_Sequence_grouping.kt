fun testSequenceGroupingByContracts(source: Sequence<String>): Grouping<String, Int> {
    val grouping: Grouping<String, Int> = source.groupingBy { it.length }
    return grouping
}
