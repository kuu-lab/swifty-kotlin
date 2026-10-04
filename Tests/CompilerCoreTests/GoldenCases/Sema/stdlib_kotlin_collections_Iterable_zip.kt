fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)
    val nullable: Array<String?> = arrayOf("a", null)

    val pairs = values.zip(nullable)
    val transformed = values.zip(nullable) { left, right -> "$left:$right" }
    val iterableOverload = values.zip(listOf("x"))

    println(pairs)
    println(transformed)
    println(iterableOverload)
}
