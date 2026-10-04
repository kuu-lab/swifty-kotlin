fun plusPair(source: Map<String, Int>, pair: Pair<String, Int>): Map<String, Int> = source + pair

fun plusMap(source: Map<String, Int>, other: Map<String, Int>): Map<String, Int> = source + other

fun plusIterable(
    source: Map<String, Int>,
    pairs: Iterable<Pair<String, Int>>
): Map<String, Int> = source + pairs

fun plusSequence(
    source: Map<String, Int>,
    pairs: Sequence<Pair<String, Int>>
): Map<String, Int> = source.plus(pairs)

fun plusArray(
    source: Map<String, Int>,
    pairs: Array<out Pair<String, Int>>
): Map<String, Int> = source + pairs

fun minusKey(source: Map<String, Int>, key: String): Map<String, Int> = source - key

fun minusIterable(source: Map<String, Int>, keys: Iterable<String>): Map<String, Int> = source - keys
