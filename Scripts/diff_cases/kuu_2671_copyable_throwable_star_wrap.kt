// KUU-2671: a bundled (kklib-loaded) F-bounded `CopyableThrowable<*>` star
// projection must satisfy `where T : Throwable, T : CopyableThrowable<T>` when
// calling `createCopy()` inside a when/smart-cast branch — the declared bounds
// live on the imported nominal, not the per-symbol bound map.
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CopyableThrowable
import kotlinx.coroutines.ExperimentalCoroutinesApi

@OptIn(ExperimentalCoroutinesApi::class)
class CopyableError(val code: Int) : Exception("copy-$code"), CopyableThrowable<CopyableError> {
    override fun createCopy(): CopyableError? = CopyableError(code + 1)
}

@OptIn(ExperimentalCoroutinesApi::class)
class Token(private val origin: Throwable?) {
    fun wrapCause(wrap: (Throwable) -> Throwable = { it }): Throwable? {
        return when (origin) {
            null -> null
            is CopyableThrowable<*> -> origin.createCopy()
            is CancellationException -> CancellationException(origin.message, origin)
            else -> wrap(origin)
        }
    }
}

fun main() {
    println(Token(null).wrapCause() == null)
    val copied = Token(CopyableError(7)).wrapCause() as? CopyableError
    println(copied?.code)
    println((Token(CancellationException("cancelled")).wrapCause() as? CancellationException)?.message)
    println(Token(IllegalStateException("state")).wrapCause()?.message)
}
