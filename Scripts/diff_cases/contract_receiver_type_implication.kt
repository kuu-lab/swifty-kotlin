// KUU-2274: based on JetBrains Kotlin `kt45236.kt` at 679366a83f99851b42f64795f10ed803ff011c73.
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

sealed class NetRequestStatus<out T : Any> {
    abstract val value: T?

    data class Error<out T : Any>(
        val error: Throwable,
        override val value: T? = null,
    ) : NetRequestStatus<T>()
}

@OptIn(ExperimentalContracts::class)
fun <T : Any> NetRequestStatus<T>.isError(): Boolean {
    contract { returns(true) implies (this@isError is NetRequestStatus.Error) }
    return this is NetRequestStatus.Error
}

fun <T : Any> successOrThrow() {
    val nextTerminal: NetRequestStatus<T> = NetRequestStatus.Error(Exception())
    if (nextTerminal.isError()) throw nextTerminal.error
}

fun box(): String {
    try {
        successOrThrow<String>()
    } catch (e: Exception) {
        return "OK"
    }
    return "'successOrThrow<...>()' should throw an exception"
}

fun main() {
    print(box())
}
