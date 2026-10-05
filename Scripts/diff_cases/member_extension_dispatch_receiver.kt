class Offset(private val offset: Int) {
    fun Int.plusOffset(): Int = this + offset
    fun Int.withDefault(extra: Int = offset): Int = this + extra + offset
    fun Int.withBlock(block: (Int) -> Int): Int = block(this) + offset
    fun Int.captured(): () -> Int = { this + offset }
    fun Int.qualifiedCapture(): () -> Int = { this + this@Offset.offset }
    fun Int.defaultBlock(block: () -> Int = { offset }): Int = this + block()
    fun Offset.sameOwner(): Int = offset + this@Offset.offset
    fun readOffset(): Int = offset
    fun Offset.sameOwnerMethod(): Int = readOffset() + this@Offset.offset
    fun Offset.sameOwnerCapture(): () -> Int = { offset + this@Offset.offset }
    fun <T> Int.generic(value: T): T {
        println(this + offset)
        return value
    }
    fun run(n: Int) {
        println(n.plusOffset())
        println(n.withDefault())
        println(n.withDefault(3))
        println(n.withBlock { it + offset })
        val closure = n.captured()
        println(closure())
        println(n.qualifiedCapture()())
        println(n.defaultBlock())
        val nullable: Int? = n
        println(nullable?.plusOffset())
        println(nullable?.withDefault())
        println(nullable?.withBlock { it + offset })
        val absent: Int? = null
        println(absent?.plusOffset())
        println(Offset(4).sameOwner())
        println(Offset(4).sameOwnerMethod())
        println(Offset(4).sameOwnerCapture()())
        println(n.generic(7))
        val nested = { n.plusOffset() }
        println(nested())
    }
}

class MutableOffset(var offset: Int) {
    fun Int.capture(): () -> Int = { this + offset }
    fun run() {
        val closure = 2.capture()
        offset = 20
        println(closure())
    }
}

open class BaseOffset(protected val offset: Int) {
    open fun Int.value(extra: Int = 3): Int = this + offset + extra
    fun run(n: Int) {
        println(n.value())
        println(n.value(4))
        val nullable: Int? = n
        println(nullable?.value())
    }
}

class DerivedOffset : BaseOffset(10) {
    override fun Int.value(extra: Int): Int = this + extra + 110
}

class GenericOffset<T>(private val offset: T) {
    fun Int.getOffset(): T {
        println(this)
        return offset
    }
    fun run(n: Int): T = n.getOffset()
}

fun main() {
    Offset(10).run(2)
    DerivedOffset().run(2)
    println(GenericOffset(9).run(2))
    MutableOffset(10).run()
}
