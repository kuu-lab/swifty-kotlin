// KUU-3134: kotlinc accepts local `inline` functions under
// `@Suppress("NOT_YET_SUPPORTED_LOCAL_INLINE_FUNCTION")`; the suppressed
// function inline-expands at its call sites with closure captures intact.
fun box(): String {
    var n = 0
    @Suppress("NOT_YET_SUPPORTED_LOCAL_INLINE_FUNCTION", "NOT_YET_SUPPORTED_IN_INLINE")
    inline fun bump() { n += 1 }
    bump()
    bump()
    return "box:$n"
}

fun lambdaArg(): String {
    var hit = 0
    @Suppress("NOT_YET_SUPPORTED_LOCAL_INLINE_FUNCTION")
    inline fun runTwice(block: () -> Unit) {
        block()
        block()
    }
    runTwice { hit += 1 }
    return "lambdaArg:$hit"
}

fun nonLocalReturn(): String {
    @Suppress("NOT_YET_SUPPORTED_LOCAL_INLINE_FUNCTION")
    inline fun run(block: () -> Unit) { block() }
    run { return "nonLocalReturn:EARLY" }
    return "nonLocalReturn:END"
}

fun main() {
    println(box())
    println(lambdaArg())
    println(nonLocalReturn())
}
