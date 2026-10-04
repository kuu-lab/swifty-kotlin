import kotlin.reflect.KProperty1

class Person(val name: String)

fun main() {
    val property: KProperty1<Person, String> = Person::name
    println(property.getValue(Person("Ada"), property))
    println(property.getValue(Person("Grace"), property))
}
