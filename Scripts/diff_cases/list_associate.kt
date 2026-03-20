fun main() {
    // associate: transform each element to a key-value Pair
    val words = listOf("apple", "banana", "cherry")
    println(words.associate { it.first() to it.length })
    println(words.associate { it to it.uppercase() })

    // associateBy: key selector only
    val numbers = listOf(1, 2, 3, 4, 5)
    println(numbers.associateBy { it * 2 })
    println(numbers.associateBy { it % 3 })

    // associateBy with key + value transform
    println(words.associateBy({ it.first() }, { it.length }))
    println(words.associateBy({ it.length }, { it.uppercase() }))

    // associateWith: each element becomes the key, lambda gives value
    println(numbers.associateWith { it * it })
    println(words.associateWith { it.length })

    // empty list
    val empty = emptyList<String>()
    println(empty.associate { it to it.length })
    println(empty.associateBy { it.length })
    println(empty.associateWith { it.length })

    // duplicate keys: last wins
    val dupes = listOf("a", "ab", "abc", "abcd", "b", "bc")
    println(dupes.associateBy { it.first() })
    println(dupes.associate { it.length to it })

    // single element
    val single = listOf(42)
    println(single.associate { it to "value" })
    println(single.associateBy { it })
    println(single.associateWith { it.toString() })

    // Int keys and values
    val ints = listOf(10, 20, 30)
    println(ints.associate { it to it / 10 })
    println(ints.associateBy { it + 1 })
    println(ints.associateWith { it - 5 })
}
