import kotlin.properties.ObservableProperty
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

// Regression for object-literal super-constructor calls against bundled
// stdlib classes: `object : ObservableProperty(v)` used to drop initialValue
// because the super <init> call was skipped when the ctor carried an
// external link name (.kklib artifact path).
class Named(initial: String) : ObservableProperty<String>(initial) {
    override fun afterChange(property: KProperty<*>, oldValue: String, newValue: String) {
        println("named:$oldValue->$newValue")
    }
}

val named = Named("yo")
var delegated: String by named

fun main() {
    val anon = object : ObservableProperty<String>("hi") {}
    println(anon.toString())
    println(anon.getValue(null, ::delegated))

    var local: Int by object : ObservableProperty<Int>(7) {
        override fun beforeChange(property: KProperty<*>, oldValue: Int, newValue: Int): Boolean {
            println("veto:$oldValue->$newValue")
            return newValue >= 0
        }
    }
    println(local)
    local = 42
    println(local)
    local = -1
    println(local)

    println(named.toString())
    println(delegated)
    delegated = "world"
    println(delegated)

    val generic = object : ObservableProperty<List<Int>>(listOf(1, 2)) {}
    println(generic.toString())
}
