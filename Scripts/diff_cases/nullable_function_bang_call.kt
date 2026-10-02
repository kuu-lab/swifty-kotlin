fun main() {
    val nf2: (() -> String)? = { "s" }
    println(nf2!!())
    val nf4: ((String) -> String)? = { it + "!" }
    println(nf4!!("a"))
    val nf: (() -> String)? = { "s" }
    val f = nf!!
    println(f())
    val ni: (() -> Int)? = { 7 }
    println(ni!!())
}
