// KSP-441: source 実装の transform をネストさせたケース。内側の map/flatMap は
// 外側のラムダ本体が inline 展開された後に初めて現れるため、inline lowering を
// 1 回しか回さないと `undefined reference to 'map'` でリンクに失敗していた。
// 併せて遅延評価（消費した分しか transform が走らない）も固定する。
fun main() {
    val base = sequenceOf(1, 2)
    println(base.map { x -> sequenceOf(x).map { y -> y + 1 }.toList() }.toList())
    println(base.flatMap { x -> sequenceOf(x).flatMap { y -> sequenceOf(y, y + 100) } }.toList())
    println(base.flatMap { x -> sequenceOf(x).map { y -> y * 10 } }.toList())

    var mapped = 0
    val lazyMapped = generateSequence(1) { it + 1 }.map { mapped++; it * 2 }
    println(lazyMapped.take(3).toList())
    println(mapped)

    var flattened = 0
    val lazyFlatMapped = generateSequence(1) { it + 1 }.flatMap { flattened++; sequenceOf(it, -it) }
    println(lazyFlatMapped.take(4).toList())
    println(flattened)

    var filtered = 0
    val lazyFiltered = generateSequence(1) { it + 1 }.filter { filtered++; it % 2 == 0 }
    println(lazyFiltered.take(2).toList())
    println(filtered)
}
