fun main() {
    val text: String? = "hello"
    println(requireNotNull(text).length)
    println(requireNotNull(text) { "should not be evaluated" }.length)

    val nullText: String? = null
    try {
        requireNotNull(nullText)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        requireNotNull(nullText) { "custom require" }
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
