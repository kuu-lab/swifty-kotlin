package kotlin.io

import kotlin.internal.KsSymbolName

// KSP-614: kotlin.io.print / kotlin.io.println.
// Only "write one already-rendered value to stdout" stays in the runtime
// (`__kk_print_raw`); it needs the platform's stdout. Newline handling and
// overload selection live here.

@KsSymbolName("__kk_print_raw")
internal external fun __printRaw(message: Any?)

public fun print() {
    __printRaw("")
}

public fun print(message: Any?) {
    __printRaw(message.toString())
}

public fun println() {
    __printRaw("\n")
}

public fun println(message: Any?) {
    __printRaw(message.toString())
    __printRaw("\n")
}
