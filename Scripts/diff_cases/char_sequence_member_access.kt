fun printLength(cs: CharSequence) {
    println(cs.length)
}

fun main() {
    printLength("hello")
    val cs: CharSequence = "world!"
    println(cs.length)
    println(cs.get(1))
    println(cs[2])
    println(cs.subSequence(1, 3))
    val sb: CharSequence = StringBuilder("abc")
    println(sb.length)
    println(sb.get(1))
    println(sb[2])
}
