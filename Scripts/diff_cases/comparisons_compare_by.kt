import kotlin.comparisons.compareBy
import kotlin.comparisons.compareByDescending

data class Person(val name: String, val age: Int)

fun main() {
    val people = listOf(Person("bob", 30), Person("alice", 25), Person("carol", 25))
    val byAgeThenName = people.sortedWith(compareBy({ it.age }, { it.name }))
    println(byAgeThenName.map { it.name })

    val descThenName = people.sortedWith(compareByDescending<Person> { it.age }.thenBy { it.name })
    println(descThenName.map { it.name })

    val nums = listOf(3, 1, 2)
    println(nums.sortedWith(compareBy { it }))
    println("OK")
}
