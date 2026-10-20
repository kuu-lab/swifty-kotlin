import kotlin.reflect.KProperty
import kotlin.reflect.KMutableProperty
private lateinit var top: String
interface A { fun a(): Int }
interface B { fun b(): Int }
class Impl: A, B { override fun a(): Int = 1; override fun b(): Int = 2 }
fun makeA(): A { println(10); return Impl() }
fun makeB(): B { println(20); return Impl() }
class Multiple: B by makeB(), A by makeA() {
    fun ready(): Boolean = ::top.isInitialized
}
class Value {
    var token: KProperty<*>? = null
    operator fun provideDelegate(thisRef: Any?, p: KProperty<*>): Value { token = p; return this }
    operator fun getValue(thisRef: Any?, p: KProperty<*>): Int {
        println(p == token); println(p is KMutableProperty<*>); println(thisRef == null); return 42
    }
    operator fun setValue(thisRef: Any?, p: KProperty<*>, value: Int) { println(p == token) }
}
class Owner { var number: Int by Value() }
fun main() {
    val multiple = Multiple(); println(multiple.a() + multiple.b()); println(multiple.ready())
    top = "ok"; println(multiple.ready())
    val owner = Owner(); println(owner.number); owner.number = 1
    var local: Int by Value(); println(local); local = 1
}
