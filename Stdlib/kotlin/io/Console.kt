package kotlin.io

import kswiftk.internal.*

fun println(): Unit = __println()

fun println(message: Any?): Unit = __println(message)

fun print(): Unit = __print()

fun print(message: Any?): Unit = __print(message)

fun readLine(): String? = readlnOrNull()

fun readln(): String {
    val line = readlnOrNull()
    return if (line == null) {
        throw IllegalStateException("EOF")
    } else {
        line
    }
}

fun readlnOrNull(): String? = __readlnOrNull()
