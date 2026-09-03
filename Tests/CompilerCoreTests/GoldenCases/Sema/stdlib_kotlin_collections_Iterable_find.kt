fun probe(values: Iterable<Int>, nullable: Iterable<String?>, list: List<Int>) {
    val first = values.find { it > 1 }
    val last = values.findLast { it > 1 }
    val nullableFirst = nullable.find { it == null }
    val nullableLast = nullable.findLast { it == null }
    val listFirst = list.find { it > 1 }
    val listLast = list.findLast { it > 1 }
}
