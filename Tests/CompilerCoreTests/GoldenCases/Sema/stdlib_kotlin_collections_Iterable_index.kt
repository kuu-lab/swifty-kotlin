fun probe(
    values: Iterable<Int>,
    nullable: Iterable<String?>,
    list: List<Int>
) {
    values.indexOf(1)
    nullable.indexOf(null)
    values.indexOfFirst { it > 0 }
    values.indexOfLast { it > 0 }
    list.indexOf(1)
    list.indexOfFirst { it > 0 }
    list.indexOfLast { it > 0 }
}
