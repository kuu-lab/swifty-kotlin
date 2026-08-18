fun main() {
    val cs: CharSequence = "hello"
    println(cs.length)
    println(cs[0])
    println(cs.get(1))
    println(cs.subSequence(1, 4))

    val sb = StringBuilder("hello")
    val cs2: CharSequence = sb
    println(cs2.length)
    println(cs2[1])
    println(cs2.get(3))
    println(cs2.subSequence(1, 4))
}
