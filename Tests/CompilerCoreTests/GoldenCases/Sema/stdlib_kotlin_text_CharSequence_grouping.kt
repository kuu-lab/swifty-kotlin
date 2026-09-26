package golden.sema

fun charSequenceGroupingBy(source: CharSequence): Grouping<Char, Int> =
    source.groupingBy { ch -> if (ch == 'a') 0 else 1 }

fun charSequenceGroupingByEachCount(source: CharSequence): Map<Int, Int> =
    source.groupingBy { ch -> if (ch == 'a') 0 else 1 }.eachCount()
