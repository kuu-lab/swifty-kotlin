class Buffer(val size: Int)

inline fun build(block: StringBuilder.() -> Unit): String {
    val sb = StringBuilder()
    sb.block()
    return sb.toString()
}

fun Buffer.describe(): String = build {
    append("size=")
    append(this@describe.size)
}

fun main() {
    println(Buffer(4).describe())
}
