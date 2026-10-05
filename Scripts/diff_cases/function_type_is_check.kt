typealias Action = (Int) -> Int

fun provide(action: Action?): Action? {
    println("subject")
    return action
}

fun main() {
    val plain: (Int) -> Int = { it + 1 }
    println(plain is (Int) -> Int)
    println(plain !is (Int) -> Int)
    println(plain is (Int) -> Any)
    println(when (plain) { is (Int) -> Int -> "plain"; else -> "missing" })
    println(when (plain) { !is (Int) -> Int -> "missing"; else -> "negated" })

    val absent: ((Int) -> Int)? = null
    println(absent is (Int) -> Int)
    println(absent !is (Int) -> Int)
    println(absent is ((Int) -> Int)?)

    val receiver: Int.() -> Int = { this + 1 }
    println(receiver is Int.() -> Int)
    println(receiver !is Int.() -> Int)

    val suspended: suspend (Int) -> Int = { it + 2 }
    println(suspended is suspend (Int) -> Int)
    println(suspended !is suspend (Int) -> Int)

    val present: Action? = plain
    println(present is (Int) -> Int)
    println(present !is (Int) -> Int)
    println(present is ((Int) -> Int)?)
    println(when (provide(plain)) { is Action -> "present"; else -> "missing" })
    println(when (provide(null)) { is Action -> "missing"; !is Action -> "absent"; else -> "missing" })
    println(provide(plain) is (Int) -> Int)
    println(provide(null) !is (Int) -> Int)
    println(provide(null) is ((Int) -> Int)?)
}
