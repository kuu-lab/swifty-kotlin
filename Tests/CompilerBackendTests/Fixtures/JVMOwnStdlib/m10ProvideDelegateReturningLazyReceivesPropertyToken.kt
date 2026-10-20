import kotlin.reflect.KProperty
class Provider {
    operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): Lazy<Int> {
        println(property.name); return lazy { println("initialize"); 42 }
    }
}
val top: Int by Provider()
class Box { val number: Int by Provider() }
fun main() {
    println(top); println(top)
    val box = Box(); println(box.number); println(box.number)
    val local: Int by Provider(); println(local); println(local)
}
