package kotlin.io

import kotlin.internal.KsSymbolName

// KSP-614: kotlin.io.print / kotlin.io.println.
// Only "write one already-rendered value to stdout" stays in the runtime
// (`__kk_print_raw`); it needs the platform's stdout. Newline handling and
// overload selection live here.

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

// KSP-615: kotlin.io.readLine / readln / readlnOrNull.
// Only the platform-dependent "read one line from stdin" operation stays in
// the runtime (`__kk_readline_raw`); EOF nullability and the readln throw
// branch are implemented in Kotlin here.

@KsSymbolName("__kk_readline_raw")
internal external fun __readLineRaw(): String?

public fun readLine(): String? = __readLineRaw()

public fun readln(): String = readLine() ?: throw RuntimeException("EOF has already been reached")

public fun readlnOrNull(): String? = readLine()
