import kotlin.ExperimentalContextParameters

class Logger(val prefix: String)

class Formatter(val suffix: String)

@OptIn(ExperimentalContextParameters::class)
fun decorate(message: String): String {
    return context(Logger("log"), Formatter("!")) {
        contextOf<Logger>().prefix + ":" + message + contextOf<Formatter>().suffix
    }
}

@OptIn(ExperimentalContextParameters::class)
fun earlyExit(flag: Boolean): String {
    context("early") {
        if (flag) {
            return contextOf<String>()
        }
    }
    return "late"
}

@OptIn(ExperimentalContextParameters::class)
fun main() {
    println(context(1) { 2 })
    println(context("ok") { contextOf<String>() })
    println(context(1, 2) { "two" })
    println(context(1, 2, 3) { "three" })
    println(context(1, 2, 3, 4) { "four" })
    println(context(1, 2, 3, 4, 5) { "five" })
    println(context(1, 2, 3, 4, 5, 6) { "six" })
    println(decorate("hello"))
    println(earlyExit(true))
    println(earlyExit(false))
    println(context(Logger("outer")) { context(Formatter("?")) { contextOf<Logger>().prefix + contextOf<Formatter>().suffix } })
}
