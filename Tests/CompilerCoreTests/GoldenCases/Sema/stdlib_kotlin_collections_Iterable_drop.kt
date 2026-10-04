fun probe(values: Iterable<Int>, nullable: Iterable<String?>, list: List<Int>) {
    val dropped = values.drop(2)
    val droppedZero = values.drop(0)
    val droppedWhile = values.dropWhile { it < 3 }
    val nullableResult = nullable.dropWhile { it == null }
    val listDrop = list.drop(1)
    val listDropWhile = list.dropWhile { it < 2 }
}
