import kotlin.reflect.KProperty

class Delegate(var v: String) {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = v
    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: String) { v = value }
}

// KUU-2944 (JetBrains delegatedProperty/local/kt21085.kt): a delegated local
// referenced from a lambda inside a local class must be captured as the
// delegate instance, so reads inside the lambda dispatch getValue.
fun box(): String {
    val x by Delegate("O")
    class Local(val y: String) {
        val fn = { x + y }
    }
    return Local("K").fn()
}

fun memberFunctionRead(): String {
    val x by Delegate("O")
    class Local(val y: String) {
        fun f() = x + y
    }
    return Local("K").f()
}

fun varWriteThroughMember(): String {
    var x by Delegate("O")
    class Local(val y: String) {
        fun write(v: String) { x = v }
        fun read() = x + y
    }
    val local = Local("K")
    local.write("P")
    return local.read() + "|" + x
}

fun initBlockLambda(): String {
    val x by Delegate("O")
    class Local(val y: String) {
        val fn: () -> String
        init {
            fn = { x + y }
        }
    }
    return Local("K").fn()
}

fun objectLiteralMemberRead(): String {
    val x by Delegate("O")
    val obj = object {
        val y = "K"
        fun f() = x + y
    }
    return obj.f()
}

fun main() {
    println(box())
    println(memberFunctionRead())
    println(varWriteThroughMember())
    println(initBlockLambda())
    println(objectLiteralMemberRead())
}
