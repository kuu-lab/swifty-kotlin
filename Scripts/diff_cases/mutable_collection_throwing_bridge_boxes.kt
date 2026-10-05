fun mutate(values: MutableCollection<Char>) {
    println(values.add('c'))
    println(values.remove('b'))
    println(values.remove('z'))
    println(values.addAll(listOf('d', 'e')))
    println(values.addAll(emptyList<Char>()))
    println(values.removeAll(listOf('a', 'e')))
    println(values.removeAll(listOf('z')))
    println(values.retainAll(listOf('c')))
    println(values.retainAll(listOf('c')))
    println(values)
    values.clear()
    println(values.isEmpty())
}

fun main() {
    val list: MutableList<Char> = mutableListOf('a', 'b')
    mutate(list)
    println(list.add('x'))
    println(list.remove('x'))
    list.clear()
    println(list.isEmpty())
    val set: MutableSet<Char> = mutableSetOf('a', 'b')
    mutate(set)
    println(set.add('x'))
    println(set.remove('x'))
    set.clear()
    println(set.isEmpty())
}
