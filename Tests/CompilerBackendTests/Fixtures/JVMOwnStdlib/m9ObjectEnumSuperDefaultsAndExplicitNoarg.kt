open class Base(val a: Int = 20, val b: Int = 22)
object Child: Base(b = 42)
enum class Entry(val value: Int = 42) { FIRST, SECOND(value = 21) { override fun read(): Int = value * 2 }; open fun read(): Int = value }
class Box(val value: Int = 1) { constructor(): this(42) }
fun main() { println(Child.a); println(Child.b); println(Entry.FIRST.read()); println(Entry.SECOND.read()); println(Box().value) }
