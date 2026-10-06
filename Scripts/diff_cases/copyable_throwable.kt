import kotlinx.coroutines.CopyableThrowable
import kotlinx.coroutines.ExperimentalCoroutinesApi

@OptIn(ExperimentalCoroutinesApi::class)
class CopyableError(val code: Int) : Exception("copy"), CopyableThrowable<CopyableError> {
    override fun createCopy(): CopyableError? = CopyableError(code)
}
@OptIn(ExperimentalCoroutinesApi::class)
class OptOutError : Exception(), CopyableThrowable<OptOutError> {
    override fun createCopy(): OptOutError? = null
}
@OptIn(ExperimentalCoroutinesApi::class)
fun main() {
    val error: Throwable = CopyableError(7)
    if (error is CopyableThrowable<*>) {
        println((error.createCopy() as CopyableError).code)
    }
    println(OptOutError().createCopy() == null)
}
