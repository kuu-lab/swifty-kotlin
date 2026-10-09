fun retLambda(flag: Boolean): (String) -> String =
    if (flag) ({ s -> s.uppercase() }) else ({ s -> s.lowercase() })

fun main() {
    println(retLambda(true)("Ab"))
    println(retLambda(false)("Ab"))
    runExtra()
}

fun plainLambdaReturn(): (String) -> String = { s -> s + "!" }

fun mergedThenReturn(flag: Boolean): (String) -> String {
    val f: (String) -> String = if (flag) ({ s -> s + "1" }) else ({ s -> s + "2" })
    return f
}

fun runExtra() {
    println(plainLambdaReturn()("x"))
    println(mergedThenReturn(true)("x"))
    println(mergedThenReturn(false)("x"))
}
