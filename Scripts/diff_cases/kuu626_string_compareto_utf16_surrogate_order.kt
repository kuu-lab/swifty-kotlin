fun main() {
    // Build U+10000 from its UTF-16 surrogate pair and compare it with U+E000.
    // The values match the raw characters in the issue while avoiding source
    // encoding differences in the compiler test harness.
    val supplementary = "\uD800\uDC00"
    val bmp = 0xE000.toChar().toString()

    println(supplementary.compareTo(bmp))
    println(supplementary < bmp)
    println(bmp.compareTo(supplementary))
    println(bmp > supplementary)
}
