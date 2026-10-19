fun outer(): Int {
    fun inner(p: Int): Int {
        fun grand(c: Int): Int = c + 1
        return grand(p * p)
    }
    val f: () -> Int = { -> inner(7) }
    return f()
}

fun main() {
    println(outer())
}
