fun visit(key: String, value: Int) {
    println("ref:$key=$value")
}

fun main() {
    val m = mapOf("a" to 1, "b" to 2)
    m.forEach { k, v -> println("$k$v") }
    m.forEach { k, v -> println("typed:${k.length + v}") }

    var sum = 0
    val prefix = "captured:"
    m.forEach { k, v ->
        sum += v
        println("$prefix$k=$sum")
    }
    println("sum=$sum")

    m.forEach { (k, v) -> println("destructured:$k=$v") }
    m.forEach { e -> println("entry:${e.key}=${e.value}") }
    m.forEach { println("implicit:${it.key}=${it.value}") }

    val action: (String, Int) -> Unit = { k, v -> println("stored:$k=$v") }
    m.forEach(action)
    m.forEach(::visit)
    m.forEach { k, v ->
        if (k == "a") return@forEach
        println("skip:$k=$v")
    }

    mapOf(3 to 4, 5 to 6).forEach { k, v -> println("ints:${k + v}") }
    mutableMapOf("x" to 7).forEach { k, v -> println("mutable:$k=$v") }
    val nullable: Map<String?, Int?> = mapOf(null to 8, "n" to null)
    nullable.forEach { k, v -> println("nullable:$k=$v") }
    emptyMap<String, Int>().forEach { k, v -> println("unexpected:$k=$v") }
    println("empty")

    try {
        m.forEach { k, v ->
            if (v == 2) throw IllegalStateException(k)
            println("before-throw:$k")
        }
    } catch (e: IllegalStateException) {
        println("caught:${e.message}")
    }
}
