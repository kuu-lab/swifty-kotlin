private class Sink<in T>(private val stored: T) {
    fun accept(value: T) { println(stored == value) }
}
private class Counter(private var value: Int) {
    fun next(): Int { value += 1; return value }
}
private open class Parent(protected val label: String)
private class Child : Parent("protected") {
    fun read(): String = label
}
private class Visible(internal val value: Int)
fun main() {
    val sink: Sink<String> = Sink<Any>("same")
    sink.accept("same")
    sink.accept("different")
    val counter = Counter(3)
    println(counter.next())
    println(Child().read())
    println(Visible(7).value)
}
