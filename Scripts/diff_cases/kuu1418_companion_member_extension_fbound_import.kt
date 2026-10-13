package z

import z.Tok.Companion.wrapCause

interface Copyable<T> where T : Throwable, T : Copyable<T> {
    fun createCopy(): T?
}

internal val CLOSED = Tok(null)

internal class Tok(private val origin: Throwable?) {
    companion object {
        inline fun Tok.wrapCause(wrap: (Throwable) -> Throwable): Throwable? {
            return when (origin) {
                null -> null
                is Copyable<*> -> origin.createCopy()
                else -> wrap(origin)
            }
        }
    }
}

fun main() {
    val x: Tok = CLOSED
    println(x.wrapCause { it } == null)
}
