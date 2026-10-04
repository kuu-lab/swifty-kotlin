data class Person(val name: String, val age: Int)

fun main() {
    val numbers = listOf(1, 3, 5, 7, 9)
    println(numbers.binarySearch(5))
    println(numbers.binarySearch(4))
    println(numbers.binarySearch(5, 1, 4))
    println(numbers.binarySearch { it - 7 })
    val ascending = compareBy<Int> { it }
    println(numbers.binarySearch(5, ascending))
    println(numbers.binarySearch(5, ascending, 1, 4))

    val people = listOf(
        Person("Alice", 25),
        Person("Bob", 30),
        Person("Charlie", 35),
        Person("David", 40),
    )

    println(people.binarySearchBy(35) { it.age })
    println(people.binarySearchBy(35, 1) { it.age })
    println(people.binarySearchBy(35, 1, 4) { it.age })
    println(people.binarySearchBy(28) { it.age })
}
