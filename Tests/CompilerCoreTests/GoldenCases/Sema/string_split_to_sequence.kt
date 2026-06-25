package golden.sema

// STDLIB-TEXT-FN-070: splitToSequence

fun useSplitToSequenceBasic(): Sequence<String> = "a,b,c".splitToSequence(",")

fun useSplitToSequenceToList(): List<String> = "a,b,c".splitToSequence(",").toList()

fun useSplitToSequenceEmptyDelimiter(): Sequence<String> = "abc".splitToSequence("")
