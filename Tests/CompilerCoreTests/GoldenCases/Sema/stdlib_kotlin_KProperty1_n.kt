package golden.sema

import kotlin.reflect.KProperty
import kotlin.reflect.KProperty1

class Person(val name: String)

fun <T, V> read(property: KProperty1<T, V>, receiver: T, metadata: KProperty<*>): V =
    property.getValue(receiver, metadata)

fun main() {
    val property: KProperty1<Person, String> = Person::name
    println(read(property, Person("Ada"), property))
}
