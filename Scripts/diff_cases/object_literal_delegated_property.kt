import kotlin.properties.Delegates
import kotlin.reflect.KProperty

class IntBox(var v: Int) {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = v
    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
        v = value
    }
}

fun main() {
    val o = object {
        val x: Int by lazy { 42 }
        fun show(): Int = x
    }
    println(o.x)
    println(o.show())

    val m = object {
        var count: Int by IntBox(7)
        fun read(): Int = count
        fun bump() { count += 1 }
    }
    println(m.count)
    m.count = 8
    println(m.count)
    println(m.read())
    m.bump()
    println(m.count)

    val base = 20
    val captured = object {
        val x: Int by lazy { base + 1 }
        fun show(): Int = x
    }
    println(captured.x)
    println(captured.show())

    val p = object {
        var count: Int by Delegates.observable(0) { _, old, new ->
            println("obs $old->$new")
        }
        fun inc() { count += 1 }
    }
    p.inc()
    println(p.count)
}
