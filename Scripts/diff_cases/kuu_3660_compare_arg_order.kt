// KUU-3660: comparator / Comparable argument order must match JVM semantics.
// PosBox and NegBox intentionally violate the usual antisymmetry contract by
// returning a constant nonzero compareTo, so any (candidate, current) argument
// swap flips which element wins an extrema fold or where a stable sort moves
// it. JVM folds invoke compare(current, candidate); sorts shift a placed
// element only when compare(pivot, placed) orders it first.
class PosBox(val id: Int) : Comparable<PosBox> {
    override fun compareTo(other: PosBox): Int = 10
    override fun toString(): String = "P$id"
}

class NegBox(val id: Int) : Comparable<NegBox> {
    override fun compareTo(other: NegBox): Int = -10
    override fun toString(): String = "N$id"
}

val posCmp = Comparator<PosBox> { _, _ -> 10 }
val negCmp = Comparator<PosBox> { _, _ -> -10 }
val entryCmp = Comparator<Map.Entry<PosBox, Int>> { _, _ -> 10 }

fun ids(items: List<PosBox>): String = items.joinToString(",") { it.id.toString() }
fun nids(items: List<NegBox>): String = items.joinToString(",") { it.id.toString() }

fun main() {
    val p1 = PosBox(1)
    val p2 = PosBox(2)
    val p3 = PosBox(3)
    val list = listOf(p3, p1, p2)

    // Vararg folds lowered through kk_compare_any / __kk_compare_with_comparator.
    println("varargMin:" + minOf(p3, p1, p2).id)
    println("varargMax:" + maxOf(p3, p1, p2).id)
    println("varargMinCmp:" + minOf(p3, p1, p2, posCmp).id)
    println("varargMaxCmp:" + maxOf(p3, p1, p2, posCmp).id)

    // Comparable extrema and selectors on List.
    println("min:" + list.min().id)
    println("max:" + list.max().id)
    println("minOrNull:" + list.minOrNull()!!.id)
    println("maxOrNull:" + list.maxOrNull()!!.id)
    println("minBy:" + list.minBy { it }.id)
    println("maxBy:" + list.maxBy { it }.id)
    println("minByOrNull:" + list.minByOrNull { it }!!.id)
    println("maxByOrNull:" + list.maxByOrNull { it }!!.id)
    println("minOfSel:" + list.minOf { it }.id)
    println("maxOfSel:" + list.maxOf { it }.id)

    // Natural and comparator-based ordering; a constant comparator must leave
    // order untouched for +10 and reverse it for -10.
    println("sorted:" + ids(list.sorted()))
    println("sortedDesc:" + ids(list.sortedDescending()))
    println("sortedBy:" + ids(list.sortedBy { it }))
    println("sortedByDesc:" + ids(list.sortedByDescending { it }))
    println("sortedWith:" + ids(list.sortedWith(posCmp)))
    println("sortedWithNeg:" + ids(list.sortedWith(negCmp)))
    val inplace = mutableListOf(p3, p1, p2)
    inplace.sortWith(posCmp)
    println("sortWith:" + ids(inplace))
    println("minWith:" + list.minWith(posCmp).id)
    println("maxWith:" + list.maxWith(posCmp).id)
    println("minOfWith:" + list.minOfWith(posCmp) { it }.id)
    println("maxOfWith:" + list.maxOfWith(posCmp) { it }.id)
    println("binarySearch:" + list.binarySearch(p2, posCmp))

    // Array delegates and by-key extrema.
    val arr = arrayOf(p3, p1, p2)
    println("arrMinOrNull:" + arr.minOrNull()!!.id)
    println("arrMinByOrNull:" + arr.minByOrNull { it }!!.id)
    println("arrMaxByOrNull:" + arr.maxByOrNull { it }!!.id)
    println("arrSortedWith:" + ids(arr.sortedWith(posCmp)))
    println("arrSortedArrayWith:" + ids(arr.sortedArrayWith(posCmp).toList()))

    // Set extrema.
    val set = setOf(p3, p1, p2)
    println("setMinOrNull:" + set.minOrNull()!!.id)
    println("setMaxOrNull:" + set.maxOrNull()!!.id)

    // Sequence extrema.
    val seq = list.asSequence()
    println("seqMinOrNull:" + seq.minOrNull()!!.id)
    println("seqMaxOrNull:" + seq.maxOrNull()!!.id)
    println("seqMinWithOrNull:" + seq.minWithOrNull(posCmp)!!.id)
    println("seqMaxWithOrNull:" + seq.maxWithOrNull(posCmp)!!.id)
    println("seqMinByOrNull:" + seq.minByOrNull { it }!!.id)
    println("seqMaxByOrNull:" + seq.maxByOrNull { it }!!.id)
    println("seqMinOfWith:" + seq.minOfWith(posCmp) { it }.id)
    println("seqMaxOfWith:" + seq.maxOfWith(posCmp) { it }.id)

    // Map entry extrema.
    val map = mapOf(p3 to 3, p1 to 1, p2 to 2)
    println("mapMinWith:" + map.minWith(entryCmp).key.id)
    println("mapMaxWith:" + map.maxWith(entryCmp).key.id)
    println("mapMinByOrNull:" + map.minByOrNull { it.key }!!.key.id)
    println("mapMaxByOrNull:" + map.maxByOrNull { it.key }!!.key.id)
    println("mapMinOfWith:" + map.minOfWith(posCmp) { it.key }.id)
    println("mapMaxOfWith:" + map.maxOfWith(posCmp) { it.key }.id)

    // The negative-constant polarity reverses every result above.
    val n1 = NegBox(1)
    val n2 = NegBox(2)
    val n3 = NegBox(3)
    val nlist = listOf(n3, n1, n2)
    println("nVarargMin:" + minOf(n3, n1, n2).id)
    println("nVarargMax:" + maxOf(n3, n1, n2).id)
    println("nMin:" + nlist.min().id)
    println("nMax:" + nlist.max().id)
    println("nSorted:" + nids(nlist.sorted()))
    println("nSortedDesc:" + nids(nlist.sortedDescending()))

    // n > STABLE_SORT_RUN exercises the merge phase, not only insertion runs.
    val big = listOf(3, 0, 7, 1, 5, 2, 8, 4, 6, 9, 10, 12, 11, 15, 13, 19, 14, 18, 16, 17).map { PosBox(it) }
    println("bigSortedWith:" + ids(big.sortedWith(posCmp)))
    println("bigSortedWithNeg:" + ids(big.sortedWith(negCmp)))
}
