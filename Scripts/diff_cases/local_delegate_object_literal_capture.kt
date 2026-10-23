// KUU-2949: a local delegated variable captured by an anonymous object must
// keep dispatching getValue/setValue through the delegate instance stored in
// the object's capture field (JetBrains delegatedProperty/local/kt13557.kt).
import kotlin.properties.Delegates
import kotlin.reflect.KProperty

class IntProp(var backing: Int) {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = backing
    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
        backing = value
    }
}

fun notNullWrite(): String {
    var foo: String by Delegates.notNull()
    object { fun baz() { foo = "OK" } }.baz()
    return foo
}

fun lazyRead(): Int {
    val x: Int by lazy { 42 }
    return object { fun baz(): Int = x }.baz()
}

fun customVarWriteRead(): Int {
    var v: Int by IntProp(1)
    val o = object {
        fun bump() { v += 6 }
        fun read(): Int = v
    }
    o.bump()
    return o.read() + v
}

fun observableWrite(): String {
    var log = ""
    var v: Int by Delegates.observable(0) { _, old, new -> log += "$old->$new;" }
    object { fun set() { v = 9 } }.set()
    return "$v|$log"
}

fun localClassWrite(): String {
    var foo: String by Delegates.notNull()
    class Local {
        fun baz() { foo = "LC" }
    }
    Local().baz()
    return foo
}

fun lazyValInLocalClass(): Int {
    val x: Int by lazy { 11 }
    class Local {
        fun read(): Int = x
    }
    return Local().read()
}

fun main() {
    println(notNullWrite())
    println(lazyRead())
    println(customVarWriteRead())
    println(observableWrite())
    println(localClassWrite())
    println(lazyValInLocalClass())
}
