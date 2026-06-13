package golden.sema

fun useFilter(): String = "hello".filter { it != 'l' }

fun useFilterNot(): String = "hello".filterNot { it == 'l' }

fun useFilterIndexed(): String = "abcde".filterIndexed { i, _ -> i % 2 == 0 }

fun useTakeWhile(): String = "abcXYZ".takeWhile { it.isLowerCase() }

fun useDropWhile(): String = "aaabbb".dropWhile { it == 'a' }

fun useTakeLastWhile(): String = "abcDEF".takeLastWhile { it.isUpperCase() }

fun useFind(): Char? = "hello".find { it == 'l' }

fun useFindLast(): Char? = "hello".findLast { it == 'l' }

fun useReduce(): Char = "abc".reduce { acc, c -> if (c > acc) c else acc }

fun useReduceOrNull(): Char? = "abc".reduceOrNull { acc, c -> if (c > acc) c else acc }

fun useReduceRightOrNull(): Char? = "abc".reduceRightOrNull { c, acc -> if (c > acc) c else acc }

fun usePartition(): Pair<String, String> = "hello".partition { it == 'l' }

fun useMap(): List<Int> = "abc".map { it.code }

fun useMapIndexed(): List<String> = "abc".mapIndexed { i, c -> "$i:$c" }

fun useMapNotNull(): List<Char> = "a1b2".mapNotNull { if (it.isLetter()) it else null }

fun useFold(): String = "abc".fold("") { acc, c -> acc + c }

fun useFoldIndexed(): String = "abc".foldIndexed("") { i, acc, c -> acc + "$i$c" }

fun useScan(): List<String> = "abc".scan("") { acc, c -> acc + c }

fun useRunningFold(): List<String> = "ab".runningFold("") { acc, c -> acc + c }
