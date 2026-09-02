import kotlin.reflect.KMutableProperty0

var topLevel: Int = 10

fun write(property: KMutableProperty0<Int>, value: Int) {
    property.setValue(null, property, value)
}

fun main() {
    val property: KMutableProperty0<Int> = ::topLevel
    write(property, 42)
    println(topLevel)
    property.setValue(null, property, 17)
    println(topLevel)
}
