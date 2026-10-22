// KUU-3018: runtime hot-path benchmark. Exercises primitive boxing/unboxing
// (List<Int>.map/filter/sum), registry membership checks and StringBuilder.append.
// Rounds are tunable through the first command-line argument (default 3000).
// The lambdas intentionally capture nothing: capturing a `for` loop variable in
// a lambda currently crashes at runtime, which is unrelated to this benchmark.
fun main(args: Array<String>) {
    val rounds = if (args.size > 0) args[0].toInt() else 3000
    val source = (0 until 1000).toList()
    var checksum = 0L
    var builderLength = 0
    for (round in 0 until rounds) {
        val mapped = source.map { it * 2 + 1 }
        val filtered = mapped.filter { it % 3 == 0 }
        checksum += filtered.sum()
        val builder = StringBuilder()
        for (i in 0 until 200) {
            builder.append(i)
            builder.append(',')
        }
        builderLength += builder.length
    }
    println("checksum=$checksum builderLength=$builderLength")
}
