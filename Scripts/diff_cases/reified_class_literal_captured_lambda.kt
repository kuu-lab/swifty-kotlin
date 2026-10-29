// KUU-3742: a reified class literal in a lambda must use its captured token.
private class OK2

private inline fun invokeInline(block: () -> String): String = block()
private inline fun invokeCross(crossinline block: () -> String): String = block()

private inline fun <reified T : Any> direct(): String = T::class.simpleName!!
private inline fun <reified T : Any> plain(): String = invokeInline { T::class.simpleName!! }
private inline fun <reified T : Any> crossed(): String = invokeCross { T::class.simpleName!! }
private inline fun <reified T : Any> crossedCheck(value: Any): String =
    invokeCross { if (value is T) "yes" else "no" }
private inline fun <T> captured(value: T): String = invokeCross { "$value" }

fun main() {
    println("direct:" + direct<OK2>())
    println("plain:" + plain<OK2>())
    println("cross:" + crossed<OK2>())
    println("cross-literal:" + invokeCross { OK2::class.simpleName!! })
    println("cross-const:" + invokeCross { "OK" })
    println("captured:" + captured("hello"))
    println("cross-check-yes:" + crossedCheck<OK2>(OK2()))
    println("cross-check-no:" + crossedCheck<OK2>("no"))
}
