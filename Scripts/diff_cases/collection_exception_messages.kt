// Exception type and message parity for collection access, windowing and
// reduction helpers. JVM behaviour varies by the concrete list
// implementation (EmptyList / SingletonList / Arrays$ArrayList /
// java.util.ArrayList / views), so each factory is probed separately.
fun probe(name: String, f: () -> Any?) {
    try {
        println("$name -> [${f()}]")
    } catch (e: Exception) {
        println("$name -> ${e::class.simpleName}: ${e.message}")
    }
}

fun main() {
    probe("empty.get5") { emptyList<Int>()[5] }
    probe("single.get5") { listOf(1)[5] }
    probe("two.get5") { listOf(1, 2)[5] }
    probe("mut.get5") { mutableListOf(1)[5] }
    probe("asList.get5") { arrayOf(1, 2, 3).asList()[5] }
    probe("single.elementAt") { listOf(1).elementAt(5) }
    probe("empty.elementAt") { emptyList<Int>().elementAt(0) }
    probe("sub.get5") { listOf(1, 2, 3).subList(0, 2)[5] }
    probe("rev.get5") { listOf(1).asReversed()[5] }
    probe("rev2.get5") { listOf(1, 2).asReversed()[5] }

    probe("empty.subList.0.5") { emptyList<Int>().subList(0, 5) }
    probe("subList.-1.1") { listOf(1).subList(-1, 1) }
    probe("subList.1.0") { listOf(1).subList(1, 0) }
    probe("subList.0.5") { listOf(1).subList(0, 5) }
    probe("sub.subList.0.5") { listOf(1, 2, 3).subList(0, 2).subList(0, 5) }
    probe("empty.slice.0..0") { emptyList<Int>().slice(0..0) }
    probe("slice.0..5") { listOf(1).slice(0..5) }
    probe("slice.idx") { listOf(1, 2, 3).slice(listOf(0, 5)) }
    probe("empty.slice.idx") { emptyList<Int>().slice(listOf(0)) }
    probe("arr.slice.0..5") { arrayOf(1).slice(0..5) }
    probe("arr.slice.-1..3") { arrayOf(1, 2, 3, 4, 5).slice(-1..3) }
    probe("iarr.slice.0..5") { intArrayOf(1).slice(0..5) }
    probe("arr.copyOfRange.0.5") { arrayOf(1).copyOfRange(0, 5) }
    probe("arr.copyOfRange.-1.1") { arrayOf(1).copyOfRange(-1, 1) }
    probe("arr.copyOfRange.2.1") { arrayOf(1).copyOfRange(2, 1) }
    probe("iarr.copyOfRange.-1.1") { intArrayOf(1).copyOfRange(-1, 1) }

    probe("empty.first") { emptyList<Int>().first() }
    probe("empty.last") { emptyList<Int>().last() }
    probe("empty.single") { emptyList<Int>().single() }
    probe("two.single") { listOf(1, 2).single() }
    probe("emptySet.first") { emptySet<Int>().first() }
    probe("empty.min") { emptyList<Int>().min() }
    probe("empty.max") { emptyList<Int>().max() }
    probe("empty.minBy") { emptyList<Int>().minBy { it } }
    probe("empty.reduce") { emptyList<Int>().reduce { a, b -> a + b } }
    probe("empty.reduceRight") { emptyList<Int>().reduceRight { a, b -> a + b } }
    probe("mut.removeFirst") { mutableListOf<Int>().removeFirst() }
    probe("mut.removeLast") { mutableListOf<Int>().removeLast() }
    probe("deque.removeFirst") { ArrayDeque<Int>().removeFirst() }
    probe("deque.get5") { val d = ArrayDeque<Int>(); d.add(1); d.add(2); d.add(3); d[5] }
    probe("iter.next") { listOf<Int>().iterator().next() }
    probe("iter.next2") { val it = listOf(1).iterator(); it.next(); it.next() }
    probe("listIter.prev") { listOf<Int>().listIterator().previous() }
    probe("removeAt.5") { mutableListOf(1).removeAt(5) }
    probe("take.-1") { listOf(1).take(-1) }
    probe("dropLast.-1") { listOf(1).dropLast(-1) }

    probe("chunked.0") { listOf(1, 2).chunked(0) }
    probe("chunked.-1") { listOf(1, 2).chunked(-1) }
    probe("chunked.t.0") { listOf(1, 2).chunked(0) { it.size } }
    probe("empty.chunked.0") { emptyList<Int>().chunked(0) }
    probe("windowed.0.1") { listOf(1, 2).windowed(0, 1) }
    probe("windowed.1.0") { listOf(1, 2).windowed(1, 0) }
    probe("windowed.-1.-2") { listOf(1, 2).windowed(-1, -2) }
    probe("windowed.t.0") { listOf(1, 2).windowed(0, 1) { it.size } }

    probe("prog.first") { (5..1).first() }
    probe("charProg.first") { ('z'..'a').first() }
    probe("downTo.first") { (1 downTo 5).first() }
}
