data class Person(val name: String, val age: Int)

fun main() {
    val people = listOf(
        Person("Alice", 30),
        Person("Bob", 25),
        Person("Alice", 25),
        Person("Bob", 30),
        Person("Charlie", 25)
    )

    // thenBy: sort by name ascending, then by age ascending
    println("-- thenBy --")
    val sorted = people.sortedWith(compareBy<Person> { it.name }.thenBy { it.age })
    sorted.forEach { println("${it.name} ${it.age}") }

    // thenByDescending: sort by name ascending, then by age descending
    println("-- thenByDescending --")
    val sortedDesc = people.sortedWith(compareBy<Person> { it.name }.thenByDescending { it.age })
    sortedDesc.forEach { println("${it.name} ${it.age}") }

    // Descending sort using compareByDescending with compareTo
    println("-- descending --")
    println(listOf(3, 1, 4, 1, 5).sortedWith(compareByDescending { it }))
}
