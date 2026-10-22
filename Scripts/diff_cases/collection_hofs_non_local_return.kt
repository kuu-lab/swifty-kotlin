private fun returnFromFilter(values: List<Int>): Int {
    values.filter {
        if (it == 2) return 11
        false
    }
    return 0
}

private fun returnFromAny(values: List<Int>): Int {
    values.any {
        if (it == 2) return 12
        false
    }
    return 0
}

private fun returnFromAll(values: List<Int>): Int {
    values.all {
        if (it == 2) return 13
        true
    }
    return 0
}

private fun returnFromIterableFilter(values: Iterable<Int>): Int {
    values.filter {
        if (it == 2) return 44
        false
    }
    return 0
}

private fun returnFromIterableAny(values: Iterable<Int>): Int {
    values.any {
        if (it == 2) return 45
        false
    }
    return 0
}

private fun returnFromIterableAll(values: Iterable<Int>): Int {
    values.all {
        if (it == 2) return 46
        true
    }
    return 0
}

private fun returnFromNone(values: List<Int>): Int {
    values.none {
        if (it == 2) return 14
        false
    }
    return 0
}

private fun returnFromTakeWhile(values: List<Int>): Int {
    values.takeWhile {
        if (it == 2) return 15
        true
    }
    return 0
}

private fun returnFromGroupBy(values: List<Int>): Int {
    values.groupBy {
        if (it == 2) return 16
        it
    }
    return 0
}

private fun returnFromOnEach(values: List<Int>): Int {
    values.onEach {
        if (it == 2) return 17
    }
    return 0
}

private fun returnFromCount(values: List<Int>): Int {
    values.count {
        if (it == 2) return 18
        false
    }
    return 0
}

private fun returnFromFlatMap(values: List<Int>): Int {
    values.flatMap {
        if (it == 2) return 19
        listOf(it)
    }
    return 0
}

private fun returnFromMapNotNull(values: List<Int>): Int {
    values.mapNotNull {
        if (it == 2) return 20
        it
    }
    return 0
}

private fun returnFromFilterNot(values: List<Int>): Int {
    values.filterNot {
        if (it == 2) return 21
        false
    }
    return 0
}

private fun returnFromDropWhile(values: List<Int>): Int {
    values.dropWhile {
        if (it == 2) return 22
        true
    }
    return 0
}

private fun returnFromAssociate(values: List<Int>): Int {
    values.associate {
        if (it == 2) return 23
        it to it
    }
    return 0
}

private fun returnFromAssociateBy(values: List<Int>): Int {
    values.associateBy {
        if (it == 2) return 24
        it
    }
    return 0
}

private fun returnFromPartition(values: List<Int>): Int {
    values.partition {
        if (it == 2) return 25
        true
    }
    return 0
}

private fun returnFromFirst(values: List<Int>): Int {
    values.first {
        if (it == 2) return 26
        false
    }
    return 0
}

private fun returnFromFirstOrNull(values: List<Int>): Int {
    values.firstOrNull {
        if (it == 2) return 27
        false
    }
    return 0
}

private fun returnFromLast(values: List<Int>): Int {
    values.last {
        if (it == 2) return 28
        false
    }
    return 0
}

private fun returnFromFind(values: List<Int>): Int {
    values.find {
        if (it == 2) return 29
        false
    }
    return 0
}

private fun returnFromIndexOfFirst(values: List<Int>): Int {
    values.indexOfFirst {
        if (it == 2) return 30
        false
    }
    return 0
}

private fun returnFromDistinctBy(values: List<Int>): Int {
    values.distinctBy {
        if (it == 2) return 31
        it
    }
    return 0
}

private fun returnFromMapIndexed(values: List<Int>): Int {
    values.mapIndexed { index, value ->
        if (value == 2) return 32
        index
    }
    return 0
}

private fun returnFromFilterIndexed(values: List<Int>): Int {
    values.filterIndexed { _, value ->
        if (value == 2) return 33
        false
    }
    return 0
}

private fun returnFromOnEachIndexed(values: List<Int>): Int {
    values.onEachIndexed { _, value ->
        if (value == 2) return 34
    }
    return 0
}

@Suppress("DEPRECATION")
private fun returnFromSumBy(values: List<Int>): Int {
    values.sumBy {
        if (it == 2) return 35
        it
    }
    return 0
}

private fun returnFromZip(values: List<Int>): Int {
    values.zip(listOf(7, 8, 9)) { value, _ ->
        if (value == 2) return 36
        value
    }
    return 0
}

private fun returnFromZipWithNext(values: List<Int>): Int {
    values.zipWithNext { first, second ->
        if (second == 2) return 37
        first + second
    }
    return 0
}

private fun returnFromElementAtOrElse(values: List<Int>): Int {
    values.elementAtOrElse(10) {
        return 41
    }
    return 0
}

private fun returnFromSingle(values: List<Int>): Int {
    values.single {
        if (it == 2) return 42
        false
    }
    return 0
}

private fun returnFromSingleOrNull(values: List<Int>): Int {
    values.singleOrNull {
        if (it == 2) return 43
        false
    }
    return 0
}

fun main() {
    val values = listOf(1, 2, 3)
    println(returnFromFilter(values))
    println(returnFromAny(values))
    println(returnFromAll(values))
    val iterable: Iterable<Int> = values
    println(returnFromIterableFilter(iterable))
    println(returnFromIterableAny(iterable))
    println(returnFromIterableAll(iterable))
    println(returnFromNone(values))
    println(returnFromTakeWhile(values))
    println(returnFromGroupBy(values))
    println(returnFromOnEach(values))
    println(returnFromCount(values))
    println(returnFromFlatMap(values))
    println(returnFromMapNotNull(values))
    println(returnFromFilterNot(values))
    println(returnFromDropWhile(values))
    println(returnFromAssociate(values))
    println(returnFromAssociateBy(values))
    println(returnFromPartition(values))
    println(returnFromFirst(values))
    println(returnFromFirstOrNull(values))
    println(returnFromLast(values))
    println(returnFromFind(values))
    println(returnFromIndexOfFirst(values))
    println(returnFromDistinctBy(values))
    println(returnFromMapIndexed(values))
    println(returnFromFilterIndexed(values))
    println(returnFromOnEachIndexed(values))
    println(returnFromSumBy(values))
    println(returnFromZip(values))
    println(returnFromZipWithNext(values))
    println(returnFromElementAtOrElse(values))
    println(returnFromSingle(values))
    println(returnFromSingleOrNull(values))
}
