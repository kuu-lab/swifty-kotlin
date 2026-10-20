import kotlin.reflect.KProperty
class Value(private var stored: Int) {
    operator fun getValue(owner: Any?, property: KProperty<*>): Int { println(property.name); return stored }
    operator fun setValue(owner: Any?, property: KProperty<*>, value: Int) { println(property.name); stored = value }
}
class Provider {
    operator fun provideDelegate(owner: Any?, property: KProperty<*>): Value { println(property.name); return Value(10) }
}
var top: Int by Value(1)
class Box { var number: Int by Provider() }
fun main() {
    println(top); top = 2; println(top)
    val box = Box(); println(box.number); box.number += 5; println(box.number)
    var local: Int by Value(3)
    val change = { local += 4; local }
    println(change()); println(change())
}
