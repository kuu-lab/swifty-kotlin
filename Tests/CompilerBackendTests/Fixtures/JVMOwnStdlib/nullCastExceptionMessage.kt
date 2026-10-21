fun main() {
    val text: String? = null
    try {
        println(text as String)
    } catch (error: NullPointerException) {
        println(error.message)
    }
    val count: Int? = null
    try {
        println(count as Int)
    } catch (error: NullPointerException) {
        println(error.message)
    }
    val safe: String? = null
    println(safe as? String)
}
