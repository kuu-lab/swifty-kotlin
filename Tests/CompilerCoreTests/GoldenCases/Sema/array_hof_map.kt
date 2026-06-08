fun transform(values: Array<String>) {
    val mapped = values.map { it.uppercase() }
    val filtered = values.filter { it.length > 3 }
    val found = values.find { it.startsWith("a") }
    val any = values.any { it.isEmpty() }
    val all = values.all { it.isNotEmpty() }
    val folded = values.fold("") { acc, v -> acc + v }
}
