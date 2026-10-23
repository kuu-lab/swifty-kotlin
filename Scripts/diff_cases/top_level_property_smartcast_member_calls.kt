val G: Any = 'A'

fun main() {
    if (G is Char) {
        println(G)
        println(G.code)
        println(G.toInt())
    }
}
