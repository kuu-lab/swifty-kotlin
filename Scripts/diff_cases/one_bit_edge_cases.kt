private fun printIntOneBitOperations(value: Int) {
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

private fun printLongOneBitOperations(value: Long) {
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

fun main() {
    // Int: zero, negative value, positive sign boundary, negative sign boundary, and a mixed value.
    printIntOneBitOperations(0)
    printIntOneBitOperations(-1)
    printIntOneBitOperations(Int.MAX_VALUE)
    printIntOneBitOperations(Int.MIN_VALUE)
    printIntOneBitOperations(0x12345678)

    // Long: zero, negative value, positive sign boundary, negative sign boundary, and a mixed value.
    printLongOneBitOperations(0L)
    printLongOneBitOperations(-1L)
    printLongOneBitOperations(Long.MAX_VALUE)
    printLongOneBitOperations(Long.MIN_VALUE)
    printLongOneBitOperations(0x12345678L)
}
