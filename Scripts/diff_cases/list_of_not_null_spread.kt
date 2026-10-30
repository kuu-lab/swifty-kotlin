fun main() {
    val values: Array<Int?> = arrayOf(null, 4, 5)
    println(listOfNotNull(*values))
    println(listOfNotNull(1, *values, 8))
    println(listOfNotNull(*emptyArray<Int?>()))
    println(listOfNotNull(9))
    val nested = listOfNotNull(values)
    println(nested.size)
    println(nested[0].size)
}
