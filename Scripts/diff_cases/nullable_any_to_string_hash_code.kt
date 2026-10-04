fun main() {
    val nullableInt: Int? = null
    println(nullableInt.toString())

    val nullableAny: Any? = null
    println(nullableAny.toString())
    println(nullableAny.hashCode())

    val nullableString: String? = null
    println(nullableString.toString())
    println(nullableString.hashCode())

    val nonNullString: String? = "abc"
    println(nonNullString.toString())
    println(nonNullString.hashCode())

    val nullableThrowable: Throwable? = null
    println(nullableThrowable.toString())

    println(null.toString())
    println(null.hashCode())
}
