fun testAssociateWithInts() {
    val result = sequenceOf(1, 2, 3).associateWith { it * it }
    println(result[1])
    println(result[2])
    println(result[3])
}

fun testAssociateWithStrings() {
    val result = sequenceOf("a", "bb", "ccc").associateWith { it.length }
    println(result["a"])
    println(result["bb"])
    println(result["ccc"])
}
