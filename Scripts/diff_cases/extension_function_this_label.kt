// KUU-1243: An extension function's name labels its receiver, including
// inside a suspend receiver lambda with the same receiver type.
interface CC
interface CScope { val ctx: CC }
class Job

fun CScope.reader(coroutineContext: CC) {
    val job = launch2(coroutineContext) {
        val inner = this@reader.ctx
    }
}
fun CScope.launch2(context: CC, block: suspend CScope.() -> Unit): Job = TODO()

class Scope(val value: Int)
fun Scope.invokeBlock(block: Scope.() -> Int): Int = block()
fun Scope.readLabel(other: Scope): Int {
    val direct = this@readLabel.value
    return direct + other.invokeBlock { this@readLabel.value * 10 + this.value }
}

fun main() {
    println(Scope(3).readLabel(Scope(7)))
}
