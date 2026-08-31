package golden.sema

fun unzipEmpty(): Pair<List<Int>, List<String>> =
    emptyList<Pair<Int, String>>().unzip()

fun unzipSingle(): Pair<List<Int>, List<String>> =
    listOf(Pair(7, "single")).unzip()

fun unzipMultipleWithDuplicates(): Pair<List<Int>, List<String>> =
    listOf(Pair(2, "x"), Pair(2, "x"), Pair(1, "y")).unzip()

fun unzipNullable(values: Iterable<Pair<Int?, String?>>): Pair<List<Int?>, List<String?>> =
    values.unzip()

fun <T, R> unzipGeneric(values: Iterable<Pair<T, R>>): Pair<List<T>, List<R>> =
    values.unzip()

fun unzipListSpecific(values: List<Pair<Int, String>>): Pair<List<Int>, List<String>> =
    values.unzip()

fun unzipSequenceSpecific(values: Sequence<Pair<Int, String>>): Pair<List<Int>, List<String>> =
    values.unzip()

fun unzipIterableUpcast(values: List<Pair<Int, String>>): Pair<List<Int>, List<String>> {
    val iterable: Iterable<Pair<Int, String>> = values
    return iterable.unzip()
}
