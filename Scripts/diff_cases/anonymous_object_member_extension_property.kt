object O

class Delegate {
    var v = "d0"
    operator fun getValue(thisRef: O, property: kotlin.reflect.KProperty<*>): String = v
    operator fun setValue(thisRef: O, property: kotlin.reflect.KProperty<*>, value: String) { v = value }
}

fun main() {
    val oo = object : Any() {
        var O.e: String
            get() = "ge"
            set(v) { println("set:$v") }
        var O.d by Delegate()
        fun use() { println(O.e); O.e = "u"; println(O.d); O.d = "du" }
    }
    oo.use()
    with(oo) { println(O.e); O.e = "w"; println(O.d); O.d = "dw" }
}
