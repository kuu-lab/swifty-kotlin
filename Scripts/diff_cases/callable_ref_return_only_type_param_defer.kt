// A generic callable reference whose type parameter occurs only in return
// position has no input evidence for the enclosing call's solver; the
// reference must defer that parameter to the enclosing call's inference
// instead of collapsing it to `Any?` (Arrow Core `Either.catch`).
fun <A, B> combine(block: () -> A, transform: (A) -> B, recover: (Throwable) -> B): B {
    return try {
        transform(block())
    } catch (t: Throwable) {
        recover(t)
    }
}

fun <R> right(value: R): R = value
fun <R> left(error: Throwable): R = throw error

fun catchIt(f: () -> Int): Int = combine(f, ::right, ::left)
fun <R> catchItGen(f: () -> R): R = combine(f, ::right, ::left)

fun <T> retOnly(value: Int): T = throw UnsupportedOperationException()
fun catchIt2(f: () -> Int): Int = combine(f, ::retOnly, { error: Throwable -> 0 })

fun main() {
    println(catchIt { 41 } + 1)
    println(catchItGen { 7 })
    println(catchIt2 { 5 })
}
