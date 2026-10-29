class Delegate {
    var v = "d0"
    operator fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): String = v
    operator fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: String) { v = value }
}

fun main() {
    val oo = object : Any() {
        var x by Delegate()
        var y = "init"
        fun use() { println(x); x = "x"; println(x); println(y) }
    }
    oo.use()
    val oo2 = object : Any() {
        var x by Delegate()
        fun use() { println(x); x = "y"; println(x) }
    }
    oo2.use()
}
