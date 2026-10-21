import fixture.ElementAccessOracle

fun readIterable(source: Iterable<Int>, operation: Int): Int? = when (operation) {
    0 -> source.first()
    1 -> source.last()
    2 -> source.firstOrNull()
    else -> source.lastOrNull()
}
fun readList(source: List<Int>, operation: Int): Int? = when (operation) {
    0 -> source.first()
    1 -> source.last()
    2 -> source.firstOrNull()
    else -> source.lastOrNull()
}
fun main() {
    val list = listOf(10, 20, 30)
    val collection: Collection<Int> = list
    val set: Set<Int> = setOf(3, 1, 2)
    println(list.first()); println(list.last()); println(list.firstOrNull()); println(list.lastOrNull())
    println(collection.first()); println(collection.last()); println(collection.firstOrNull()); println(collection.lastOrNull())
    println(set.first()); println(set.last()); println(set.firstOrNull()); println(set.lastOrNull())
    val nullable = listOf<Int?>(null, 2, null)
    println(nullable.first()); println(nullable.last()); println(nullable.firstOrNull()); println(nullable.lastOrNull())
    val nullableIterable = ElementAccessOracle.nullableIterable() as Iterable<String?>
    println(nullableIterable.first()); println(nullableIterable.last()); println(nullableIterable.firstOrNull()); println(nullableIterable.lastOrNull())
    val emptyList = emptyList<Int>()
    val emptyIterable: Iterable<Int> = emptySet<Int>()
    for (operation in 0..3) {
        try { println(readList(emptyList, operation)) }
        catch (e: NoSuchElementException) { println(e.message) }
        try { println(readIterable(emptyIterable, operation)) }
        catch (e: NoSuchElementException) { println(e.message) }
    }
    for (operation in 0..3) {
        println("list:$operation")
        println(readList(ElementAccessOracle.list(false, false) as List<Int>, operation))
        println("erased:$operation")
        println(readIterable(ElementAccessOracle.list(false, false) as Iterable<Int>, operation))
        println("empty list:$operation")
        try { println(readList(ElementAccessOracle.list(true, false) as List<Int>, operation)) }
        catch (e: NoSuchElementException) { println(e.message) }
        println("empty erased:$operation")
        try { println(readIterable(ElementAccessOracle.list(true, false) as Iterable<Int>, operation)) }
        catch (e: NoSuchElementException) { println(e.message) }
        println("cursor:$operation")
        println(readIterable(ElementAccessOracle.iterable(3, 0) as Iterable<Int>, operation))
        println("empty cursor:$operation")
        try { println(readIterable(ElementAccessOracle.iterable(0, 0) as Iterable<Int>, operation)) }
        catch (e: NoSuchElementException) { println(e.message) }
    }
    val nonList = ElementAccessOracle.collection() as Collection<Int>
    println(nonList.first()); println(nonList.last()); println(nonList.firstOrNull()); println(nonList.lastOrNull())
    for (operation in 0..3) {
        try { println(readIterable(ElementAccessOracle.iterable(2, 1) as Iterable<Int>, operation)) }
        catch (e: IllegalStateException) { println(e.message) }
        try { println(readIterable(ElementAccessOracle.iterable(2, 2) as Iterable<Int>, operation)) }
        catch (e: IllegalStateException) { println(e.message) }
        try { println(readIterable(ElementAccessOracle.list(false, true) as Iterable<Int>, operation)) }
        catch (e: IllegalStateException) { println(e.message) }
    }
}
