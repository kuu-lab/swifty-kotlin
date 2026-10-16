data class Person(val name: String, val age: Int)

fun consume(action: (Person) -> Unit) {
    action(Person("Alice", 29))
}

fun <T> consumeGeneric(value: T, action: (T) -> Unit) {
    action(value)
}

fun main() {
    val action: (Person) -> Unit = fun(person) { println(person.name) }
    action(Person("Alice", 29))

    consume(fun(person) { println(person.name) })
    consumeGeneric(Person("Alice", 29), fun(person) { println(person.name) })
    consume { person -> println(person.name) }
    consume(fun(person: Person) { println(person.name) })
    println(Person("Alice", 29).name)

    listOf(Person("Alice", 29), Person("Bob", 17)).forEach(fun(person) {
        if (person.name == "Alice") return
        println("${person.name} is not Alice")
    })
    println("Finished")
}
