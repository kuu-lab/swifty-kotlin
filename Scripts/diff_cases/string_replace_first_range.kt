fun main() {
    // replaceFirst
    println("abcabc".replaceFirst("abc", "X"))
    println("hello".replaceFirst("l", "L"))

    // replaceRange(range) — IntRange, inclusive end
    println("hello".replaceRange(0..2, "HE"))
    println("kotlin".replaceRange(1..4, "ava"))

    // replaceRange(startIndex, endIndex) — exclusive end (STDLIB-TEXT-FN-062)
    println("hello".replaceRange(0, 3, "HE"))
    println("kotlin".replaceRange(1, 5, "ava"))
}
