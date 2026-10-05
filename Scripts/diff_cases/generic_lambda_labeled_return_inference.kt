fun <T> evaluate(action: () -> T): T = action()
inline fun <T> inlineEvaluate(action: () -> T): T = action()

fun select(flag: Boolean): Int = evaluate {
    if (flag) return@evaluate 21
    34
}

fun nullable(flag: Boolean): Int? = evaluate {
    if (flag) return@evaluate null
    55
}

fun mixed(flag: Boolean): Any = evaluate {
    if (flag) return@evaluate "text"
    89
}

fun nonlocal(flag: Boolean): String {
    val value = inlineEvaluate {
        if (flag) return "function"
        return@inlineEvaluate 144
    }
    return "value=$value"
}

fun main() {
    println(evaluate { return@evaluate 13 })
    println(evaluate<Int> { return@evaluate 13 })
    println(evaluate explicit@{ return@explicit "explicit" })
    println(evaluate { return@evaluate 2147483648L })
    println(evaluate { return@evaluate true })
    println(evaluate { return@evaluate 1.5 })
    println(evaluate { return@evaluate 17; })
    println(evaluate { return@evaluate })
    println(select(true))
    println(select(false))
    println(nullable(true))
    println(nullable(false))
    println(mixed(true))
    println(mixed(false))
    println(evaluate outer@{
        println(evaluate inner@{ return@inner "inner" })
        return@outer 233
    })
    println(inlineEvaluate outer@{
        inlineEvaluate inner@{ return@outer 377 }
    })
    println(evaluate same@{
        println(evaluate same@{ return@same "shadowed" })
        return@same 610
    })
    println(evaluate local@{
        fun helper(): String { return "local" }
        println(helper())
        return@local 987
    })
    println(nonlocal(true))
    println(nonlocal(false))
    val action = action@{ return@action 1597 }
    println(action())
    println(evaluate { if (true) return@evaluate 2584 else return@evaluate 4181 })
}
