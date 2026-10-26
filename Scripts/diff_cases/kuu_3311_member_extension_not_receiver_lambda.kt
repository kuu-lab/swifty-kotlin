// KUU-3311: a member extension operator is in scope inside its receiver lambda.
var res = "FAIL"

class Context {
    operator fun Any.not() { res = "OK" }
}

fun coVerify(block: Context.() -> Unit) { Context().block() }

fun main() {
    val c = Any()
    coVerify { !c }
    println(res)
}
