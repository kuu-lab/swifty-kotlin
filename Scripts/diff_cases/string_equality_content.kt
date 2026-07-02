fun main() {
    val nullableNull: String? = null
    val nullableA: String? = "abc"
    val nullableUpper: String? = "ABC"

    println("abc".equals("abc"))
    println("abc".equals("ABC"))
    println("abc".equals("ABC", true))
    println("abc".equals("ABC", false))
    println("abc".equals(null))
    println(nullableNull.contentEquals(null))
    println(nullableNull.contentEquals(nullableA))
    println(nullableA.contentEquals(nullableUpper))
    println(nullableA.contentEquals(nullableUpper, true))
    println(nullableA.contentEquals(nullableUpper, false))
}
