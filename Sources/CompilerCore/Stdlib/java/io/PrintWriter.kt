package java.io

public open class PrintWriter : Writer {
    private var output: Writer? = null
    private var autoFlush: Boolean = false
    private var trouble: Boolean = false

    public constructor(out: Writer) {
        output = out
    }

    public constructor(out: Writer, autoFlush: Boolean) {
        output = out
        this.autoFlush = autoFlush
    }

    public override fun write(text: String): Unit {
        val target = output
        if (target == null) {
            trouble = true
            return
        }
        try {
            target.write(text)
        } catch (_: IOException) {
            trouble = true
        }
    }

    public fun write(value: Int): Unit = write(value.toChar().toString())

    public fun print(value: String): Unit = write(value)

    public fun print(value: Any?): Unit = write(value.toString())

    public fun println(): Unit {
        write("\n")
        if (autoFlush) flush()
    }

    public fun println(value: String): Unit {
        write(value)
        println()
    }

    public fun println(value: Any?): Unit {
        write(value.toString())
        println()
    }

    public override fun flush(): Unit {
        val target = output
        if (target == null) {
            trouble = true
            return
        }
        try {
            target.flush()
        } catch (_: IOException) {
            trouble = true
        }
    }

    public override fun close(): Unit {
        val target = output ?: return
        try {
            target.close()
        } catch (_: IOException) {
            trouble = true
        }
        output = null
    }

    public fun checkError(): Boolean {
        flush()
        return trouble
    }
}
