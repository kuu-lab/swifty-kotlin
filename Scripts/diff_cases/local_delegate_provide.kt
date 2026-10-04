import kotlin.reflect.KProperty

// BUG-146: `provideDelegate` on a delegate used in a *local* declaration
// (`fun f() { val x by Factory() }`) must call `provideDelegate` and bind the
// local to the effective delegate's getValue/setValue, exactly like a
// member/top-level delegated property.

class StrDelegate(private val v: String) {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = v
}

class StrFactory(private val v: String) {
    operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): StrDelegate {
        println("provideDelegate for ${prop.name}")
        return StrDelegate(v.uppercase())
    }
}

class IntBox(private var stored: Int) {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = stored
    operator fun setValue(thisRef: Any?, property: KProperty<*>, newValue: Int) {
        stored = newValue
    }
}

class IntBoxFactory(private val initial: Int) {
    operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): IntBox = IntBox(initial)
}

class Holder {
    val memberName by StrFactory("member")
}

fun main() {
    val name by StrFactory("hello")
    println(name)

    var counter by IntBoxFactory(10)
    println(counter)
    counter = 42
    println(counter)
    counter = counter + 1
    println(counter)

    val holder = Holder()
    println(holder.memberName)
}
