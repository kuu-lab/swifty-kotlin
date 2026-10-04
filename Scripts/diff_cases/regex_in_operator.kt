fun main() {
    val r = Regex("a.c")
    println(r in "abc")
    println(r in "xyz")
    println("abc".contains(r))
    println("xyz".contains(r))
}
