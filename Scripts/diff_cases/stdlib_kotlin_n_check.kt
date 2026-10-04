fun main() {
    val value: String? = "hello"
    println(checkNotNull(value).length)
    println(checkNotNull(value) { "unused" }.length)

    val nullValue: String? = null
    try {
        checkNotNull(nullValue)
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    try {
        checkNotNull(nullValue) { "custom check" }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
