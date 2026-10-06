package diff

fun main() {
    var traversals = 0
    val values: Iterable<Int> = Iterable {
        traversals++
        listOf(3, 1, 2).iterator()
    }
    println(traversals)
    println(values.toList())
    println(values.toList())
    println(traversals)

    val empty: Iterable<String> = Iterable { emptyList<String>().iterator() }
    println(empty.toList())

    var namedTraversals = 0
    val named: Iterable<Int> = Iterable(iterator = {
        namedTraversals++
        listOf(1).iterator()
    })
    println(namedTraversals)
    val first = named.iterator()
    val second = named.iterator()
    println(first.next())
    println(second.next())
    println(first.hasNext())
    println(second.hasNext())
    println(named.toList())
    println(named.toList())
    println(namedTraversals)

    val namedEmpty = Iterable<String>(iterator = { emptyList<String>().iterator() })
    println(namedEmpty.toList())
    val positional = Iterable<Int>({ listOf(7).iterator() })
    println(positional.toList())
}
