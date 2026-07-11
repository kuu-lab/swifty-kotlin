fun <T> uncheckedCastReturn(value: Any?): T {
    @Suppress("UNCHECKED_CAST")
    return value as T
}

fun <T> uncheckedCastLocal(value: Any?): T {
    @Suppress("UNCHECKED_CAST")
    val result = value as T
    return result
}

fun annotatedLocalFun(): Int {
    @Suppress("UNUSED_PARAMETER")
    fun helper(x: Int): Int = x + 1
    return helper(41)
}

fun annotatedAssignment(): Int {
    var counter = 1
    @Suppress("UNUSED")
    counter = 2
    return counter
}

fun annotatedExpressionStatement() {
    @Suppress("UNUSED_EXPRESSION")
    println("first")
    println("second")
}
