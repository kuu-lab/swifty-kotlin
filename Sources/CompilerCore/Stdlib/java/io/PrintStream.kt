package java.io

import java.io.OutputStream
import kotlin.internal.KsSymbolName
import kotlin.text.format

@KsSymbolName("__kk_printStderr")
internal external fun __printStderrRaw(message: String): Int

@KsSymbolName("__kk_print_raw")
internal external fun __printStdoutRaw(message: String)

// KUU-4156: closing a console-sink PrintStream (`System.out`/`System.err`,
// i.e. one without a wrapped OutputStream) marks the matching raw console
// bridge closed so `kotlin.io.print`/`println` and `printStackTrace` — which
// bypass this object — also drop output like on the JVM.
@KsSymbolName("__kk_console_stdout_close")
internal external fun __closeStdoutRaw()

@KsSymbolName("__kk_console_stderr_close")
internal external fun __closeStderrRaw()

public class PrintStream internal constructor() {
    private var output: OutputStream? = null
    private var writesToStdout: Boolean = false
    private var closed: Boolean = false

    internal constructor(writesToStdout: Boolean) : this() {
        this.writesToStdout = writesToStdout
    }

    public constructor(output: OutputStream) : this() {
        this.output = output
    }

    private fun writeMessage(message: String) {
        if (closed) {
            return
        }
        val target = output
        if (target != null) {
            target.write(message.toByteArray())
        } else if (writesToStdout) {
            __printStdoutRaw(message)
        } else {
            __printStderrRaw(message)
        }
    }

    public fun print(message: String) {
        writeMessage(message)
    }

    public fun print(message: Any?) {
        writeMessage(message.toString())
    }

    public fun print(message: Boolean) {
        writeMessage(message.toString())
    }

    public fun print(message: Char) {
        writeMessage(message.toString())
    }

    public fun print(message: Int) {
        writeMessage(message.toString())
    }

    public fun print(message: Long) {
        writeMessage(message.toString())
    }

    public fun print(message: Float) {
        writeMessage(message.toString())
    }

    public fun print(message: Double) {
        writeMessage(message.toString())
    }

    public fun print(message: CharArray) {
        writeMessage(message.concatToString())
    }

    public fun println() {
        writeMessage("\n")
    }

    public fun println(message: String) {
        writeMessage(message + "\n")
    }

    public fun println(message: Any?) {
        writeMessage(message.toString() + "\n")
    }

    public fun println(message: Boolean) {
        writeMessage(message.toString() + "\n")
    }

    public fun println(message: Char) {
        writeMessage(message.toString() + "\n")
    }

    public fun println(message: Int) {
        writeMessage(message.toString() + "\n")
    }

    public fun println(message: Long) {
        writeMessage(message.toString() + "\n")
    }

    public fun println(message: Float) {
        writeMessage(message.toString() + "\n")
    }

    public fun println(message: Double) {
        writeMessage(message.toString() + "\n")
    }

    public fun println(message: CharArray) {
        writeMessage(message.concatToString() + "\n")
    }

    public fun format(format: String, vararg args: Any?): PrintStream {
        writeMessage(format.format(*args))
        return this
    }

    public fun format(locale: java.util.Locale?, format: String, vararg args: Any?): PrintStream {
        writeMessage(format.format(locale, *args))
        return this
    }

    public fun printf(format: String, vararg args: Any?): PrintStream =
        this.format(format, *args)

    public fun printf(locale: java.util.Locale?, format: String, vararg args: Any?): PrintStream =
        this.format(locale, format, *args)

    public fun flush() {
        output?.flush()
    }

    public fun close() {
        if (closed) {
            return
        }
        closed = true
        val target = output
        output = null
        if (target != null) {
            target.close()
        } else if (writesToStdout) {
            __closeStdoutRaw()
        } else {
            __closeStderrRaw()
        }
    }
}
