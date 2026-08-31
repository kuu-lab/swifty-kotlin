fun inspect(map: Map<String?, Int?>) {
    val iterator = map.iterator()
    println(iterator.hasNext())
    val entry = iterator.next()
    println(entry.key)
    println(entry.value)
    println(iterator.hasNext())

    val projected: Map<Any?, Number?> = map
    val projectedIterator: Iterator<Map.Entry<Any?, Number?>> = projected.iterator()
    println(projectedIterator.hasNext())
    val projectedEntry = projectedIterator.next()
    println(projectedEntry.key)
    println(projectedEntry.value)
}
