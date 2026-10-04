// KSP-413 x BUG-169: String comparison APIs live in the bundled Kotlin stdlib
// (StringComparison.kt) while `kk_string_equals_flat` distinguishes a null
// aggregate from an empty string. This case pins the full null / "" / value
// matrix for equals(ignoreCase) and contentEquals so the two changes cannot
// disagree with the JVM.

fun sign(value: Int): Int {
    if (value < 0) return -1
    if (value > 0) return 1
    return 0
}

fun main() {
    val nullStr: String? = null
    val emptyStr: String? = ""
    val valueStr: String? = "abc"
    val upperStr: String? = "ABC"

    // --- String?.equals(other, ignoreCase = true) ---
    println(nullStr.equals(nullStr, true))
    println(nullStr.equals(emptyStr, true))
    println(emptyStr.equals(nullStr, true))
    println(emptyStr.equals(emptyStr, true))
    println(nullStr.equals(valueStr, true))
    println(valueStr.equals(nullStr, true))
    println(emptyStr.equals(valueStr, true))
    println(valueStr.equals(emptyStr, true))
    println(valueStr.equals(upperStr, true))

    // --- String?.equals(other, ignoreCase = false) ---
    println(nullStr.equals(nullStr, false))
    println(nullStr.equals(emptyStr, false))
    println(emptyStr.equals(nullStr, false))
    println(emptyStr.equals(emptyStr, false))
    println(nullStr.equals(valueStr, false))
    println(valueStr.equals(nullStr, false))
    println(emptyStr.equals(valueStr, false))
    println(valueStr.equals(emptyStr, false))
    println(valueStr.equals(upperStr, false))

    // --- String.equals(other) : the plain kk_string_equals_flat path ---
    // NOTE: a 1-argument `.equals()` call on a *nullable* String? receiver is
    // not yet supported by kswiftc (KSWIFTK-SEMA-0002, pre-existing), so the
    // receivers below are non-nullable.
    println("".equals(emptyStr))
    println("".equals(nullStr))
    println("abc".equals(emptyStr))
    println("abc".equals(valueStr))
    println("abc".equals(upperStr))

    // --- CharSequence?.contentEquals(other) ---
    val nullSeq: CharSequence? = null
    val emptySeq: CharSequence? = ""
    val valueSeq: CharSequence? = "abc"
    val upperSeq: CharSequence? = "ABC"

    println(nullSeq.contentEquals(nullSeq))
    println(nullSeq.contentEquals(emptySeq))
    println(emptySeq.contentEquals(nullSeq))
    println(emptySeq.contentEquals(emptySeq))
    println(nullSeq.contentEquals(valueSeq))
    println(valueSeq.contentEquals(nullSeq))
    println(emptySeq.contentEquals(valueSeq))
    println(valueSeq.contentEquals(emptySeq))
    println(valueSeq.contentEquals(upperSeq))

    // --- CharSequence?.contentEquals(other, ignoreCase) ---
    println(nullSeq.contentEquals(nullSeq, true))
    println(nullSeq.contentEquals(emptySeq, true))
    println(emptySeq.contentEquals(nullSeq, true))
    println(emptySeq.contentEquals(emptySeq, true))
    println(valueSeq.contentEquals(upperSeq, true))
    println(valueSeq.contentEquals(upperSeq, false))
    println(emptySeq.contentEquals(valueSeq, true))
    println(valueSeq.contentEquals(emptySeq, true))

    // --- compareTo(other, ignoreCase) with empty strings ---
    println(sign("".compareTo("", true)))
    println(sign("".compareTo("", false)))
    println(sign("".compareTo("a", true)))
    println(sign("a".compareTo("", true)))
    println(sign("".compareTo("A", true)))
    println(sign("A".compareTo("", false)))

    // --- StringBuilder as a non-String CharSequence receiver ---
    val builder: CharSequence = StringBuilder("abc")
    println(builder.contentEquals("abc"))
    println(builder.contentEquals("ABC"))
    println(builder.contentEquals("ABC", true))
    println(builder.contentEquals(""))
    println(builder.contentEquals(nullSeq))
}
