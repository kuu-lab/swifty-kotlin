interface Writer {
    fun flush(): Int
}

class BufferedWriter : Writer {
    override fun flush(): Int = 42
}

fun flush(): Int = 7

fun Writer.flushLater(): () -> Int = ::flush

fun main() {
    val writer: Writer = BufferedWriter()
    println(writer.flushLater()())
}
