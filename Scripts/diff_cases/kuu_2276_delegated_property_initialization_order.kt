import kotlin.reflect.KProperty

class Delegate {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "OK"
}

class Holder {
    companion object { val value: String by Delegate() }
    fun read(): String = value
}

var initializationOrder: Int = 0

class OrderDelegate(private val marker: Int) {
    init { initializationOrder = initializationOrder * 10 + marker }
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "OK"
}

class OrderedCompanion {
    companion object {
        val first: String by OrderDelegate(1)
        init { initializationOrder = initializationOrder * 10 + 2 }
        val last: String by OrderDelegate(3)
    }
}

class OrdinaryHolder {
    val value: String by OrderDelegate(4)
}

object OrderedNamedObject {
    val first: String by OrderDelegate(5)
    init { initializationOrder = initializationOrder * 10 + 6 }
    val last: String by OrderDelegate(7)
}

fun box(): String {
    if (Holder().read() != "OK") return "FAIL-holder-method"
    if (Holder.value != "OK") return "FAIL-holder"
    if (OrderedCompanion.first != "OK") return "FAIL-companion-first"
    if (initializationOrder != 123) return "FAIL-companion-order"
    if (OrderedCompanion.last != "OK") return "FAIL-companion-last"
    if (OrdinaryHolder().value != "OK") return "FAIL-ordinary-control"
    if (initializationOrder != 1234) return "FAIL-ordinary-order"
    if (OrderedNamedObject.first != "OK") return "FAIL-object-first"
    if (initializationOrder != 1234567) return "FAIL-object-order"
    if (OrderedNamedObject.last != "OK") return "FAIL-object-last"
    return "OK"
}

fun main() { print(box()) }
