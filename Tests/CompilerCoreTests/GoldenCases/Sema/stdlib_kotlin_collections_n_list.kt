package golden.sema

fun listOfSingle(): List<Int> {
    val single = listOf(7)
    return single
}

fun listOfNullable(): List<String?> {
    val nullable = listOf<String?>(null)
    return nullable
}

fun listOfNotNullSingle(value: Int?): List<Int> {
    return listOfNotNull(value)
}

fun listOfNotNullNull(): List<Any> {
    return listOfNotNull<Any>(null)
}

fun listOfNotNullValue(): List<Int> {
    return listOfNotNull(7)
}
