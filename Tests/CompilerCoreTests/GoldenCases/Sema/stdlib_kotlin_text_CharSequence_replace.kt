package golden.sema

fun charSequenceReplaceRegex(source: CharSequence): String =
    source.replace(Regex("a+"), "X")

fun charSequenceReplaceRegexLambda(source: CharSequence): String =
    source.replace(Regex("a+")) { match -> "[${match.value}]" }

fun charSequenceReplaceFirstRegex(source: CharSequence): String =
    source.replaceFirst(Regex("a+"), "X")

fun charSequenceReplaceRangeIndices(
    source: CharSequence,
    replacement: CharSequence
): CharSequence = source.replaceRange(1, 3, replacement)

fun charSequenceReplaceRangeIntRange(
    source: CharSequence,
    replacement: CharSequence
): CharSequence = source.replaceRange(1..2, replacement)

fun charSequenceReplaceRangeEmpty(source: CharSequence): CharSequence =
    source.replaceRange(2, 2, "X")
