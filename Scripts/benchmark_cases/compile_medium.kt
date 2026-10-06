data class BenchmarkRecord(
    val id: Int,
    val values: List<Int>,
    val label: String,
)

fun score(record: BenchmarkRecord): Int {
    return record.values
        .filter { value -> value % 2 == 0 }
        .map { value -> value * record.id }
        .sum()
}

fun main() {
    val records = listOf(
        BenchmarkRecord(1, listOf(1, 2, 3, 4, 5), "alpha"),
        BenchmarkRecord(2, listOf(2, 4, 6, 8, 10), "beta"),
        BenchmarkRecord(3, listOf(3, 6, 9, 12, 15), "gamma"),
        BenchmarkRecord(4, listOf(4, 8, 12, 16, 20), "delta"),
        BenchmarkRecord(5, listOf(5, 10, 15, 20, 25), "epsilon"),
        BenchmarkRecord(6, listOf(6, 12, 18, 24, 30), "zeta"),
        BenchmarkRecord(7, listOf(7, 14, 21, 28, 35), "eta"),
        BenchmarkRecord(8, listOf(8, 16, 24, 32, 40), "theta"),
    )

    val summary = records
        .filter { record -> record.values.isNotEmpty() }
        .map { record -> record.label to score(record) }
        .sortedBy { pair -> pair.second }
        .joinToString(separator = ",") { pair -> "${pair.first}:${pair.second}" }
    println(summary)
}
