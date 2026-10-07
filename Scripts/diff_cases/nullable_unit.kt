import kotlin.reflect.typeOf

class UnitReceiver { fun touch() {} }

fun emptyUnit(): Unit? = null
fun presentUnit(): Unit? = Unit
fun main() {
    var unit: Unit? = null
    println(unit)
    println(emptyUnit())
    println(unit?.toString())
    println(unit ?: Unit)
    val erased: Any? = unit
    println(erased)
    unit = Unit
    println(unit)
    println(unit?.toString())
    println(presentUnit())
    val boxed: Any? = unit
    println(boxed)
    unit = null
    println(unit)
    val absent: UnitReceiver? = null
    val present: UnitReceiver? = UnitReceiver()
    println(absent?.touch())
    println(present?.touch())
    val callback: () -> Unit? = { null }
    println(callback())
    println(typeOf<Unit?>().isMarkedNullable)
    println(typeOf<Unit>().isMarkedNullable)
}
