import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KMutableProperty1
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0
import kotlin.reflect.KProperty1

class Person(val name: String, var age: Int, var label: String)

fun main() {
    val person = Person("A", 1, "L")
    println(person.name)
    val nameProperty: KProperty0<String> = person::name
    println(nameProperty.name)
    println(nameProperty.get())
    println(nameProperty.invoke())
    val nameAsProperty: KProperty<String> = nameProperty
    println(nameAsProperty.name)
    val nullableName: KProperty0<String>? = nameProperty
    println(nullableName?.name)

    val ageProperty: KMutableProperty0<Int> = person::age
    println(ageProperty.name)
    println(ageProperty.get())
    println(ageProperty.invoke())
    val ageAsProperty0: KProperty0<Int> = ageProperty
    println(ageAsProperty0.get())
    ageProperty.set(2)
    println(person.age)

    val labelProperty: KMutableProperty0<String> = person::label
    println(labelProperty.name)
    println(labelProperty.get())
    println(labelProperty.invoke())
    labelProperty.set("M")
    println(person.label)

    val unboundName: KProperty1<Person, String> = Person::name
    println(unboundName.name)
    println(unboundName.get(person))
    println(unboundName.invoke(person))
    val unboundNameAsProperty: KProperty<String> = unboundName
    println(unboundNameAsProperty.name)

    val unboundAge: KMutableProperty1<Person, Int> = Person::age
    println(unboundAge.name)
    println(unboundAge.get(person))
    println(unboundAge.invoke(person))
    val unboundAgeAsProperty1: KProperty1<Person, Int> = unboundAge
    println(unboundAgeAsProperty1.get(person))
    unboundAge.set(person, 3)
    println(person.age)

    val unboundLabel: KMutableProperty1<Person, String> = Person::label
    println(unboundLabel.name)
    println(unboundLabel.get(person))
    println(unboundLabel.invoke(person))
    unboundLabel.set(person, "N")
    println(person.label)
}
