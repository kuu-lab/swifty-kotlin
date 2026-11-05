package kotlin.io

import java.io.IOException
import kotlin.internal.KsSymbolName

// KSP-614: Only "write one already-rendered value to stdout" stays in the
// runtime (`__kk_print_raw`); it needs the platform's stdout.

@KsSymbolName("__kk_print_raw")
internal external fun __printRaw(message: Any?)

// KSP-1163: Kotlin/Native keeps String-specialized console bridges in the
// kotlin.io metadata. The bundled compiler exposes the same exact overloads;
// the call-site lowering may still use the shared raw bridge for user calls.
@PublishedApi
@KsSymbolName("__kk_print_raw")
internal external fun __printStringRaw(message: String)

@PublishedApi
@KsSymbolName("__kk_println_raw")
internal external fun __printlnStringRaw(message: String)

public fun print(message: String) {
    __printStringRaw(message)
}

public fun println(message: String) {
    __printlnStringRaw(message)
}

public fun print(message: CharArray) {
    print(message.concatToString())
}

public fun println(message: CharArray) {
    println(message.concatToString())
}

// KUU-4296: Kotlin/JVM declares scalar print/println overloads, so a Java
// platform value like `ConcurrentLinkedQueue<Int>.poll()` (`Int!`) resolves
// to the non-null scalar parameter and an empty result raises NPE through the
// platform null assertion. Without these overloads the call falls back to
// `Any?` and a real null prints as "null" instead.
public fun print(message: Int) {
    print(message.toString())
}

public fun print(message: Long) {
    print(message.toString())
}

public fun print(message: Byte) {
    print(message.toString())
}

public fun print(message: Short) {
    print(message.toString())
}

public fun print(message: Char) {
    print(message.toString())
}

public fun print(message: Boolean) {
    print(message.toString())
}

public fun print(message: Float) {
    print(message.toString())
}

public fun print(message: Double) {
    print(message.toString())
}

public fun println(message: Int) {
    println(message.toString())
}

public fun println(message: Long) {
    println(message.toString())
}

public fun println(message: Byte) {
    println(message.toString())
}

public fun println(message: Short) {
    println(message.toString())
}

public fun println(message: Char) {
    println(message.toString())
}

public fun println(message: Boolean) {
    println(message.toString())
}

public fun println(message: Float) {
    println(message.toString())
}

public fun println(message: Double) {
    println(message.toString())
}

public fun print() {
    __printRaw("")
}

public fun print(message: Any?) {
    print(message.toString())
}

public fun println() {
    __printRaw("\n")
}

public fun println(message: Any?) {
    println(message.toString())
}

// KSP-615: Only the platform-dependent "read one line from stdin" operation
// stays in the runtime (`__kk_readline_raw`).

@KsSymbolName("__kk_readline_raw")
internal external fun __readLineRaw(): String?

// KUU-4162: `java.lang.System.in` is a runtime-backed InputStream whose close
// marks stdin closed, like KUU-4156's console-sink closed flags do for
// stdout/stderr. On the JVM, console reads after `System.in.close()` throw
// `java.io.IOException("Stream closed")` instead of returning null.
@KsSymbolName("__kk_console_stdin_closed")
internal external fun __consoleStdinClosed(): Boolean

public fun readLine(): String? {
    if (__consoleStdinClosed()) throw IOException("Stream closed")
    return __readLineRaw()
}

public fun readln(): String = readLine() ?: throw RuntimeException("EOF has already been reached")

public fun readlnOrNull(): String? = readLine()
