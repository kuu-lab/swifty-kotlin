fun main() {
    val s = "banana"
    println(s.indexOfFirst { it == 'a' })
    println(s.indexOfLast { it == 'a' })
    println(s.indexOfFirst { it == 'z' })
    println(s.indexOfLast { it == 'z' })
    println("".indexOfFirst { it == 'a' })
    println("".indexOfLast { it == 'a' })
    val cs: CharSequence = s
    println(cs.indexOfFirst { it == 'n' })
    println(cs.indexOfLast { it == 'n' })
    println(s.indexOfFirst { it.isUpperCase() })
}
