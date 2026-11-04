// KUU-4078: kotlin.jvm.Synchronized resolves as a marker annotation on
// functions and property accessors (a no-op outside JVM, like Kotlin/Native).
class Counter {
    private var value = 0

    @Synchronized
    fun increment(): Int {
        value += 1
        return value
    }

    @get:Synchronized
    var getter: Int = 7

    @set:Synchronized
    var setter: Int = 0

    var both: Int = 0
        @Synchronized get() = field + 1
        @Synchronized set(v) { field = v }
}

@Synchronized
fun topLevel(): Int = 41

fun main() {
    val c = Counter()
    println(c.increment())
    println(c.increment())
    println(c.getter)
    c.setter = 9
    println(c.setter)
    c.both = 10
    println(c.both)
    println(topLevel())
}
