package golden.sema

fun requireNotNullDefault(value: String?): String {
    return requireNotNull(value)
}

fun requireNotNullWithMessage(value: String?): String {
    return requireNotNull(value) { "value was null" }
}

fun main() {
    val text: String? = "hello"
    println(requireNotNullDefault(text).length)
    println(requireNotNullWithMessage(text).length)
}
