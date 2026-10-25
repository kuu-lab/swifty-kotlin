class Bob {
    fun Bob.bar() = "OK"
    fun Bob.other() = "OTHER"
}

fun Any.foo() = when(this) {
    is Bob -> bar()
    else -> "FAIL"
}

fun Any.explicitCheck(): String {
    if (this is Bob) return bar()
    return "FAIL"
}

fun Any.qualifiedCheck(): String {
    return if (this is Bob) this.bar() else "FAIL"
}

fun main() {
    println(Bob().foo())
    println("x".foo())
    println(Bob().explicitCheck())
    println(Bob().qualifiedCheck())
}
