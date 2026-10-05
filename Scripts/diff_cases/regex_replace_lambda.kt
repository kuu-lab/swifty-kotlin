fun main() {
    println(Regex("a").replace("aaa") { "X" })
    println(Regex("a").replace("aaa") { it.value + "!" })
    val regex = Regex("(\\d+)-(\\d+)")
    println(regex.replace("1-2 3-4") { it.groupValues[1] + "+" + it.groupValues[2] })
    println(regex.replace("1-2 3-4") { "X" })
    println(Regex("\\w+").replace("hello world") { it.value.uppercase() })

    var calls = 0
    println(Regex("a").replace("bbb") { calls++; "X" })
    println(Regex("a").replace("") { calls++; "X" })
    println(calls)
    println(Regex("").replace("ab") { "|" })
    println(Regex("").replace("") { "|" })
    println(Regex("a").replace("banana") { "" })
    println(Regex("(a)").replace("aba") { "\$1\\literal" })

    var index = 0
    println(Regex("a").replace("aaa") { index++; it.value + index })
    println(index)
    try {
        Regex("a").replace("aaa") { throw IllegalStateException("transform failed") }
        println("no-throw")
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
