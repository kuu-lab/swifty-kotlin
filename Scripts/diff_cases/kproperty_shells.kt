import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0
import kotlin.reflect.KProperty1
import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KMutableProperty1

class Person(val name: String, var age: Int)

fun describe(prop: KProperty<*>) {
    println("captured")
}

fun main() {
    val p = Person("Alice", 30)
    val nameRef: KProperty0<String> = p::name
    val ageRef: KMutableProperty0<Int> = p::age
    val classAge: KProperty1<Person, Int> = Person::age
    val mutClassAge: KMutableProperty1<Person, Int> = Person::age
    describe(nameRef)
    describe(ageRef)
    describe(classAge)
    describe(mutClassAge)
}
