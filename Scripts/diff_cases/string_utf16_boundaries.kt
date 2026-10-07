// UTF-16 boundary code-unit reads (first/last/single/OrNull) and lazy string
// comparison must preserve Kotlin code-unit semantics. Exercises both
// flat-string paths: string literals (foreign buffers) and runtime-produced
// strings (concat/substring/Char.toString -> registered storage), including
// isolated-surrogate markers. All outputs printed as Int codes / labels.
fun probe(label: String, body: () -> Char?) {
    val out = try {
        body()?.code?.toString() ?: "null"
    } catch (e: NoSuchElementException) {
        "NSEE:${e.message}"
    } catch (e: IllegalArgumentException) {
        "IAE:${e.message}"
    }
    println("$label=$out")
}

fun main() {
    // first() — literal (foreign-buffer) receivers
    probe("first_empty") { "".first() }
    probe("first_a") { "a".first() }
    probe("first_abc") { "abc".first() }
    probe("first_emoji") { "😀".first() }
    probe("first_emojiA") { "😀a".first() }
    // last() — must return the LAST code unit (low surrogate of a pair)
    probe("last_empty") { "".last() }
    probe("last_abc") { "abc".last() }
    probe("last_emoji") { "😀".last() }
    probe("last_aEmoji") { "a😀".last() }
    probe("last_emojiA") { "😀a".last() }
    // single() — empty -> NSEE, >1 code units -> IAE
    probe("single_empty") { "".single() }
    probe("single_x") { "x".single() }
    probe("single_xy") { "xy".single() }
    probe("single_emoji") { "😀".single() }
    // OrNull variants — null sentinel
    probe("firstOrNull_empty") { "".firstOrNull() }
    probe("firstOrNull_x") { "x".firstOrNull() }
    probe("lastOrNull_empty") { "".lastOrNull() }
    probe("lastOrNull_xy") { "xy".lastOrNull() }
    probe("lastOrNull_emoji") { "😀".lastOrNull() }
    probe("singleOrNull_empty") { "".singleOrNull() }
    probe("singleOrNull_x") { "x".singleOrNull() }
    probe("singleOrNull_xy") { "xy".singleOrNull() }
    probe("singleOrNull_emoji") { "😀".singleOrNull() }
    // Runtime-produced (registered-storage) receivers
    val concat = "a" + "😀" + "z"
    probe("first_concat") { concat.first() }
    probe("last_concat") { concat.last() }
    probe("single_concatOne") { ("x" + "").single() }
    probe("single_concatTwo") { ("x" + "y").single() }
    val emptyConcat = "" + ""
    probe("first_emptyConcat") { emptyConcat.first() }
    probe("firstOrNull_emptyConcat") { emptyConcat.firstOrNull() }
    probe("lastOrNull_emptyConcat") { emptyConcat.lastOrNull() }
    probe("singleOrNull_emptyConcat") { emptyConcat.singleOrNull() }
    // Isolated surrogates (marker-encoded storage): substring of a pair
    // yields unpaired surrogate units; Char.toString of a surrogate literal.
    val loneHigh = "😀".substring(0, 1)
    val loneLow = "😀".substring(1, 2)
    println("loneHigh_length=${loneHigh.length}")
    probe("single_loneHigh") { loneHigh.single() }
    probe("first_loneHigh") { loneHigh.first() }
    probe("last_loneHigh") { loneHigh.last() }
    probe("single_loneLow") { loneLow.single() }
    probe("last_loneLow") { loneLow.last() }
    // Unpaired-surrogate escape in a literal: foreign-buffer marker decode
    probe("first_litLoneHigh") { "\uD83D".first() }
    probe("last_litLoneHigh") { "\uD83D".last() }
    probe("single_litLoneHigh") { "\uD83D".single() }
    probe("single_litLoneLow") { "\uDE00".single() }
    // NB: Char.toString of an unpaired surrogate is intentionally not probed
    // here — KSwiftK currently maps it to "?" (JVM keeps the surrogate unit).
    // compareTo — raw UTF-16 code-unit comparison, NOT normalized to -1/0/1
    println("cmp_eq=${"abc".compareTo("abc")}")
    println("cmp_rem2=${"abcd".compareTo("ab")}")
    println("cmp_remneg2=${"ab".compareTo("abcd")}")
    println("cmp_rem4=${"abcde".compareTo("a")}")
    println("cmp_remneg4=${"a".compareTo("abcde")}")
    println("cmp_c_a=${"c".compareTo("a")}")
    println("cmp_z_a=${"z".compareTo("a")}")
    println("cmp_abc_abd=${"abc".compareTo("abd")}")
    println("cmp_abd_abc=${"abd".compareTo("abc")}")
    println("cmp_empty_a=${"".compareTo("a")}")
    println("cmp_a_empty=${"a".compareTo("")}")
    println("cmp_empty_empty=${"".compareTo("")}")
    println("cmp_concat=${("ab" + "cd").compareTo("ab")}")
    println("cmp_emojiGrin=${"😀".compareTo("😁")}")
    println("cmp_emojiU10000=${"😀".compareTo("𐀀")}")
    println("cmp_emoji_a=${"😀".compareTo("a")}")
    println("cmp_a_emoji=${"a".compareTo("😀")}")
    println("cmp_emojiPrefix=${"😀x".compareTo("😀")}")
    // Operators route through kk_string_compareTo_flat
    println("op_abc_lt_abd=${"abc" < "abd"}")
    println("op_emoji_gt_a=${"😀" > "a"}")
    println("op_empty_lt_a=${"" < "a"}")
    // sorted() through the string comparator (runtimeCompareStrings)
    val words = listOf("banana", "app", "apple", "appliance", "a", "ab", "z", "😀", "")
    val sorted = words.sorted()
    println("sorted_codes=${sorted.joinToString(",") { s -> s.toList().joinToString("-") { c -> c.code.toString() } }}")
    println("sorted_size=${sorted.size}")
}
