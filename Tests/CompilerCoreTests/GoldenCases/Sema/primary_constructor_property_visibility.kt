// KUU-1597 Sema owner: pin constructor property visibility, protected/internal access, variance, and mutable property resolution; observed values stay in Scripts/diff_cases/primary_constructor_property_visibility.kt.
private class Sink<in T>(private val stored: T) {
    fun accept(value: T): Boolean = stored == value
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
    val accepted: Boolean = sink.accept("same")
    val counter = Counter(3)
    val count: Int = counter.next()
    val label: String = Child().read()
    val visible: Int = Visible(7).value
}
