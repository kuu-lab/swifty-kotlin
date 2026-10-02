fun probe(values: Sequence<Int>, nullable: Sequence<String?>) {
    val at = values.elementAt(1)
    val atElse = values.elementAtOrElse(3) { it + 10 }
    val atNull = values.elementAtOrNull(99)
    val negativeNull = values.elementAtOrNull(-1)
    val nullableElement = nullable.elementAtOrNull(0)
}
