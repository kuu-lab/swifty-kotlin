fun probe(values: Iterable<Int>, nullable: Iterable<String?>, list: List<Int>) {
    val iterableAt = values.elementAt(1)
    val iterableElse = values.elementAtOrElse(3) { it + 10 }
    val iterableNull = values.elementAtOrNull(99)
    val negativeNull = values.elementAtOrNull(-1)
    val nullableElement = nullable.elementAtOrNull(0)
    val listAt = list.elementAt(1)
    val listElse = list.elementAtOrElse(1) { -1 }
    val listNull = list.elementAtOrNull(99)
}
