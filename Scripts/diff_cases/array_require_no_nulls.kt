fun main() {
    val nullable: Array<Int?> = arrayOf(1, 2)
    val nonNull: Array<Int> = nullable.requireNoNulls()
    println(nonNull.contentToString())

    try {
        arrayOf<Int?>(1, null).requireNoNulls()
        println("unexpected")
    } catch (e: IllegalArgumentException) {
        println("null rejected")
    }
}
