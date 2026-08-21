package golden.sema

fun makePair(first: Int, second: String): Pair<Int, String> = Pair(first, second)

fun makeNullablePair(first: String?, second: Int?): Pair<String?, Int?> = Pair(first, second)
