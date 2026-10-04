fun main() {
    val s = "abc"

    println(s.sumBy { it.code })
    println("".sumBy { it.code })

    println(s.sumByDouble { it.code.toDouble() / 2.0 })
    println("".sumByDouble { it.code.toDouble() })
}
