fun main() {
    val sb = StringBuilder("hello")
    println(sb is CharSequence)
    println(sb is Appendable)
    println(sb is Any)
}
