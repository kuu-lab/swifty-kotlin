fun groupFamily(
    values: Sequence<Int>,
    nullable: Sequence<String?>,
    destination: MutableMap<Any, MutableList<Int>>,
    transformedDestination: MutableMap<Any, MutableList<String>>,
    list: List<Int>
) {
    val grouped: Map<Int, List<Int>> = values.groupBy { it % 2 }
    val transformed: Map<Int, List<String>> = values.groupBy(
        { it % 2 },
        { "n=$it" }
    )
    val nullableGroups: Map<String, List<String?>> = nullable.groupBy { it ?: "null" }
    val groupedTo: MutableMap<Any, MutableList<Int>> = values.groupByTo(destination) { it % 2 }
    val transformedTo: MutableMap<Any, MutableList<String>> = values.groupByTo(
        transformedDestination,
        { it % 2 },
        { "s=$it" }
    )
    val listGrouped: Map<Int, List<Int>> = list.asSequence().groupBy { it % 2 }
}
