// KUU-1949: inapplicable receiver members must not hide top-level overloads.
interface S { fun require(n: Long) }

class Source : S {
    override fun require(n: Long) { println("member: $n") }
}

fun S.read(n: Int): String {
    require(n >= 0) { "neg: $n" }
    return "a"
}

fun S.requireBytes() { require(3L) }

class A
class Receiver(val length: Int) {
    fun convert(n: Long, block: A.() -> Int): Int = 0
}
fun convert(value: Boolean, block: String.() -> Int): Int = "ok".block()
fun Receiver.readLength(): Int = convert(true) { length }

fun main() {
    val source: S = Source()
    println(source.read(0))
    source.requireBytes()
    try {
        source.read(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    println(Receiver(99).readLength())
}
