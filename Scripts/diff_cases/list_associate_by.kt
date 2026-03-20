fun main() {
    // Basic associateBy with key selector
    val words = listOf("apple", "banana", "cherry", "avocado")
    println(words.associateBy { it.first() })

    // associateBy with key selector and value transform
    println(words.associateBy({ it.first() }, { it.length }))

    // associateBy with integers
    val numbers = listOf(1, 2, 3, 4, 5)
    println(numbers.associateBy { it % 3 })

    // associateBy with value transform on integers
    println(numbers.associateBy({ it % 3 }, { it * 10 }))

    // Duplicate keys: last value wins
    val items = listOf("a1", "b2", "a3", "b4", "c5")
    println(items.associateBy { it[0] })

    // Empty list
    val empty = emptyList<String>()
    println(empty.associateBy { it.length })

    // Single element
    val single = listOf("hello")
    println(single.associateBy { it.length })

    // associateBy with string key and value transform
    val people = listOf("Alice", "Bob", "Charlie")
    println(people.associateBy({ it.length }, { it.uppercase() }))

    // associateBy preserving last duplicate
    val dupes = listOf(1, 2, 3, 4, 5, 6)
    println(dupes.associateBy { it % 2 })
}
