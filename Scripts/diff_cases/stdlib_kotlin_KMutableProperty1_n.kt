import kotlin.reflect.KMutableProperty1

class Counter(var value: Int)

fun <T, V> assign(property: KMutableProperty1<T, V>, receiver: T, value: V) {
    property.setValue(receiver, property, value)
}

fun main() {
    val counter = Counter(1)
    val property: KMutableProperty1<Counter, Int> = Counter::value

    property.setValue(counter, property, 7)
    println(counter.value)

    assign(property, counter, 9)
    println(counter.value)
}
