package java.io

import java.io.OutputStream
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_printStderr")
internal external fun __printStderrRaw(message: String): Int

public class PrintStream internal constructor() {
    private var output: OutputStream? = null

    public constructor(output: OutputStream) : this() {
        this.output = output
    }

    public fun print(message: String) {
        val target = output
        if (target == null) {
            __printStderrRaw(message)
        } else {
            target.write(message.toByteArray())
        }
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
