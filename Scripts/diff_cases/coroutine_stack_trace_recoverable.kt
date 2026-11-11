@file:OptIn(ExperimentalStdlibCoroutineSupportApi::class)

import kotlin.coroutines.ExperimentalStdlibCoroutineSupportApi
import kotlin.coroutines.debug.StackTraceRecoverable

private class CodedException(val code: Int) : Exception(), StackTraceRecoverable<CodedException> {
    override fun copyForStackTraceRecovery(): CodedException = CodedException(code)
}

private class UncopyableException : Exception(), StackTraceRecoverable<UncopyableException> {
    override fun copyForStackTraceRecovery(): UncopyableException? = null
}

private fun <T> copy(exception: StackTraceRecoverable<T>): T?
    where T : Throwable, T : StackTraceRecoverable<T> =
    exception.copyForStackTraceRecovery()

fun main() {
    val copied: CodedException? = copy(CodedException(42))
    val declined: UncopyableException? = copy(UncopyableException())
    println(copied?.code)
    println(declined)
}
