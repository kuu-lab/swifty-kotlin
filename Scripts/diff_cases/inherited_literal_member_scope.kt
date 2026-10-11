package collisioncontract

interface BaseReader { fun read(target: String, count: Long): Long }
interface ChildReader : BaseReader {
    fun read(target: ByteArray, start: Int = 0, end: Int = target.size): Int
}
class Reader : ChildReader {
    override fun read(target: String, count: Long): Long = count + 100L
    override fun read(target: ByteArray, start: Int, end: Int): Int = end - start
}
fun gate(value: Boolean, lazyMessage: () -> Any): String = "top-boolean"
fun width(value: Long): Int = 7
fun choose(value: Int): String = "top-int"
class Collision {
    fun gate(value: Long): String = "member-long"
    fun checks() {
        println(gate(true) { "message" })
        println(gate(3))
    }
    fun width() {
        val values: Map<Long, Int> = mapOf(0L to 1, 0x10L to 2, -1L to 16)
        values.forEach { (number, length) -> println(width(number)) }
    }
}
class Priority {
    fun choose(value: Int): String = "member-int"
    fun check() { println(choose(1)) }
}
fun Priority.choose(value: Int): String = "extension-int"
class ExtensionFallback {
    fun choose(value: String): String = "member-string"
    fun check() { println(choose(1)) }
}
fun ExtensionFallback.choose(value: Int): String = "extension-int"
class Outer {
    fun route(value: Long): String = "outer-long"
    inner class Inner {
        fun route(value: String): String = "inner-string"
        fun check() { println(route(3)) }
    }
}
fun main() {
    val source: ChildReader = Reader()
    println(source.read("sink", 10))
    println(source.read("sink", 10L))
    val raw: BaseReader = source
    println(raw.read("sink", 10))
    val direct: Reader = Reader()
    println(direct.read("sink", 10))
    println(source.read(byteArrayOf(1, 2, 3), 1))
    Collision().checks()
    Collision().width()
    Priority().check()
    ExtensionFallback().check()
    Outer().Inner().check()
}
