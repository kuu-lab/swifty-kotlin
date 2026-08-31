import kotlin.reflect.KProperty

class MyLazy<T>(private val initializer: () -> T) {
    private var cached: Any? = null
    private var done: Boolean = false
    operator fun getValue(thisRef: Any?, property: KProperty<*>): T {
        if (!done) { cached = initializer(); done = true }
        @Suppress("UNCHECKED_CAST")
        return cached as T
    }
}

fun <T> myLazy(initializer: () -> T): MyLazy<T> = MyLazy(initializer)
var evaluations: Int = 0

val top: String by MyLazy { val word = "top"; word }
val evaluated: Int by myLazy { evaluations = evaluations + 1; evaluations }

class Box(val prefix: String) {
    val member: String by myLazy { val word = prefix; word + "-member" }
}

fun local(prefix: String): String {
    val value: String by myLazy { val word = prefix; word + "-local" }
    return value
}

val ctor: String by MyLazy { "ctor" }
val factory: String by myLazy { "factory" }
val parenthesizedCtor: String by MyLazy({ "parenthesized-ctor" })
val parenthesizedFactory: String by myLazy({ "parenthesized-factory" })

fun main() {
    println(ctor)
    println(factory)
    println(parenthesizedCtor)
    println(parenthesizedFactory)
    println(top)
    println(evaluated)
    println(evaluated)
    println(evaluations)
    println(Box("member").member)
    println(local("capture"))
}
