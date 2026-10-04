// KSP-441: Sequence の遅延 transform は bundled Kotlin source（object 式による
// Sequence/Iterator パイプライン）で実装される。sequenceOf / asSequence /
// generateSequence の各生成元に対して transform 群が同じ結果を返すことを固定する。
fun checkAll(name: String, s: Sequence<Int>) {
    println(name + ".map=" + s.map { it * 2 }.toList())
    println(name + ".mapIndexed=" + s.mapIndexed { i, v -> i * 100 + v }.toList())
    println(name + ".mapNotNull=" + s.mapNotNull { if (it > 1) it else null }.toList())
    println(name + ".mapIndexedNotNull=" + s.mapIndexedNotNull { i, v -> if (i > 0) v else null }.toList())
    println(name + ".filter=" + s.filter { it > 1 }.toList())
    println(name + ".filterNot=" + s.filterNot { it > 1 }.toList())
    println(name + ".filterIndexed=" + s.filterIndexed { i, _ -> i > 0 }.toList())
    println(name + ".onEach=" + s.onEach { }.toList())
    println(name + ".onEachIndexed=" + s.onEachIndexed { _, _ -> }.toList())
    println(name + ".withIndex=" + s.withIndex().toList())
    println(name + ".flatMap=" + s.flatMap { sequenceOf(it, it) }.toList())
    println(name + ".flatMapIterable=" + s.flatMap { listOf(it, -it) }.toList())
    println(name + ".flatMapIndexed=" + s.flatMapIndexed { i, v -> sequenceOf(i, v) }.toList())
    println(name + ".flatMapIndexedIterable=" + s.flatMapIndexed { i, v -> listOf(i, v) }.toList())
    println(name + ".chain=" + s.map { it + 1 }.filter { it % 2 == 0 }.flatMap { sequenceOf(it) }.toList())
}

fun main() {
    checkAll("sequenceOf", sequenceOf(1, 2, 3))
    checkAll("asSequence", listOf(1, 2, 3).asSequence())
    checkAll("generateSequence", generateSequence(1) { if (it < 3) it + 1 else null })

    println(sequenceOf(1, null, 3).filterNotNull().toList())
    println(sequenceOf(1, 2).requireNoNulls().toList())
    println(sequenceOf(sequenceOf(1), sequenceOf(2)).flatten().toList())
    println(emptySequence<Int>().flatMap { sequenceOf(it) }.toList())
    println(sequenceOf(1, 2).flatMap { emptySequence<Int>() }.toList())
}
