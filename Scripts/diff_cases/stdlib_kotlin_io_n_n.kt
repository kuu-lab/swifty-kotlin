private fun produceP(): String {
    print("p")
    return "value"
}

private fun produceQ(): String {
    print("q")
    return "value"
}

fun main() {
    print("A")
    println("B")
    print(null)
    println(null)
    val p = produceP()
    print(p)
    val q = produceQ()
    println(q)
}
