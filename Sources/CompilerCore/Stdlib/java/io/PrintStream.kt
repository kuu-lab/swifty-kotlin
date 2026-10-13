package java.io

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_printStderr")
internal external fun __printStderrRaw(message: String): Int

public class PrintStream internal constructor() {
    public fun print(message: String) {
        __printStderrRaw(message)
    }

    public fun print(message: Any?) {
        print(message.toString())
    }

    public fun println(message: String) {
        print(message + "\n")
    }

    public fun println(message: Any?) {
        println(message.toString())
    }

    public fun println() {
        print("\n")
    }
}
