fun <T> identity(value: T): T = value

val topLevel: Int = with(1) { { 3 } }()
fun expressionBody(): Int = with(1) { { 4 } }()

fun main() {
    val value: Int = with(1) { { 2 } }()
    println(value)
    println(topLevel)
    println(expressionBody())

    val withArgument: Int = with(1) { { x: Int -> x + 1 } }(6)
    val identityResult: Int = identity { 5 }()
    val runResult: Int = run { { 6 } }()
    val memberResult: Int = 1.let { { 7 } }()
    val stored: () -> Int = with(1) { { 8 } }
    val storedResult: Int = stored()
    val nonFunction: Int = with(1) { 9 }
    val direct: Int = { 10 }()
    println(withArgument)
    println(identityResult)
    println(runResult)
    println(memberResult)
    println(storedResult)
    println(nonFunction)
    println(direct)
}
