// STDLIB-REFLECT-061: KClass member access
import kotlin.reflect.full.*

data class Person(val name: String, val age: Int)

class Counter {
    var count: Int = 0
    fun increment() { count++ }
    fun decrement() { count-- }
}

fun main() {
    val personClass = Person::class
    val counterClass = Counter::class

    // memberProperties: non-extension properties
    val personMemberProps = personClass.memberProperties
    println("Person::class.memberProperties has name: ${personMemberProps.any { it.name == "name" }}")
    println("Person::class.memberProperties has age: ${personMemberProps.any { it.name == "age" }}")

    // functions: includes generated data-class component functions
    val personFunctions = personClass.functions
    println("Person::class.functions has component1: ${personFunctions.any { it.name == "component1" }}")
    println("Person::class.functions has component2: ${personFunctions.any { it.name == "component2" }}")

    // memberFunctions: non-extension functions
    val counterMemberFunctions = counterClass.memberFunctions
    println("Counter::class.memberFunctions has increment: ${counterMemberFunctions.any { it.name == "increment" }}")
    println("Counter::class.memberFunctions has decrement: ${counterMemberFunctions.any { it.name == "decrement" }}")

    // declaredMemberProperties: own declared properties
    val personDeclaredProps = personClass.declaredMemberProperties
    println("Person::class.declaredMemberProperties has name: ${personDeclaredProps.any { it.name == "name" }}")
    println("Person::class.declaredMemberProperties has age: ${personDeclaredProps.any { it.name == "age" }}")

    // declaredMemberFunctions: own declared functions
    val counterDeclaredFunctions = counterClass.declaredMemberFunctions
    println("Counter::class.declaredMemberFunctions has increment: ${counterDeclaredFunctions.any { it.name == "increment" }}")
    println("Counter::class.declaredMemberFunctions has decrement: ${counterDeclaredFunctions.any { it.name == "decrement" }}")

    // Filtering: verify filtered list contains expected member
    val filteredMemberProps = personMemberProps.filter { it.name == "name" }
    println("Filtered properties contains name: ${filteredMemberProps.any { it.name == "name" }}")
}
