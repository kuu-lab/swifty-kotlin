package java.io

public class PrintWriter : Writer {
    private var stringWriter: StringWriter? = null

    public constructor(output: Writer) {
        if (output is StringWriter) stringWriter = output
    }

    public constructor(output: Writer, autoFlush: Boolean) : this(output)

    public fun write(value: String): Unit {
        stringWriter?.write(value)
    }

    public fun write(value: String, offset: Int, length: Int): Unit {
        stringWriter?.write(value, offset, length)
    }

    public fun print(value: String): Unit {
        write(value)
    }

    public fun print(value: Any?): Unit {
        write(value.toString())
    }

    public fun println(): Unit {
        write("\n")
    }

    public fun println(value: String): Unit {
        write(value)
        println()
    }

    public fun println(value: Any?): Unit {
        println(value.toString())
    }

    public fun flush(): Unit {}

    public override fun close(): Unit {}

    public fun checkError(): Boolean = false
}
