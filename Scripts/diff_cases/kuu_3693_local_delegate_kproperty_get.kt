// DIFF_JVM
import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0

// KUU-3693: `KProperty0.get` on the KProperty handed to a local delegated
// property's delegate must throw the same catchable
// UnsupportedOperationException the JVM raises for local delegated
// references ("call/callBy are not supported for this declaration.").
var last: KProperty<*>? = null

object Probe {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): Int {
        last = property
        return 42
    }

    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
        last = property
    }
}

fun describe(block: () -> Any?): String = try {
    block().toString()
} catch (e: UnsupportedOperationException) {
    "UOE:${e.message}"
}

fun main() {
    var x: Int by Probe
    x = 7
    println(x)
    @Suppress("UNCHECKED_CAST")
    val prop = last as KMutableProperty0<Int>
    println(describe { prop.get() })
    println(describe { prop.set(9); "set" })
    println(describe { prop.invoke() })
    println(describe { prop.name })
    println(describe { prop.getDelegate() })
    val y: Int by Probe
    println(y)
    @Suppress("UNCHECKED_CAST")
    val readOnly = last as KProperty0<Int>
    println(describe { readOnly.get() })
}
