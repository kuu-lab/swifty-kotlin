// KSP-652: ClosedRange / ClosedFloatingPointRange / OpenEndRange の interface 宣言は
// Sources/CompilerCore/Stdlib/kotlin/ranges/Ranges.kt にソース化されている。
// interface 型で受けた range のメンバ呼び出しと、具象 IntRange / LongRange / CharRange の
// conformance、`..` / `..<` 演算子の挙動を kotlinc に対して固定する。
//
// 具象 range を `ClosedRange<T>` パラメータに渡すのは KSWIFTK-TYPE-0001 になる既知の
// 制約（具象 conformance 配線は KSP-451 の担当）なので、ここでは扱わない。

fun openBounds(range: OpenEndRange<Int>): Boolean = range.start < range.endExclusive

fun openMembers(range: OpenEndRange<Int>): Boolean = range.contains(3) && !range.isEmpty()

fun main() {
    val intRange = 1..5
    println(intRange.start)
    println(intRange.endInclusive)
    println(intRange.contains(3))
    println(intRange.isEmpty())

    val charRange = 'a'..'e'
    println(charRange.start)
    println(charRange.endInclusive)
    println(charRange.contains('c'))

    val longRange = 1L..5L
    println(longRange.start)
    println(longRange.endInclusive)
    println(longRange.isEmpty())

    val open: OpenEndRange<Int> = 1..<5
    println(open.start)
    println(open.endExclusive)
    println(openBounds(open))
    println(openMembers(open))

    val empty = 5..1
    println(empty.isEmpty())

    for (x in 1..3) println(x)
    for (x in 1..<3) println(x)
}
