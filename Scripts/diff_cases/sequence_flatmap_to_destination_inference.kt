fun sequenceDestinationSize(): Int {
    return "a,b\n#skip\n".lineSequence().flatMapTo(ArrayList(4)) { line ->
        val trimmed = line.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#")) return@flatMapTo emptySequence()
        val (mime, extensions) = trimmed.split(",", limit = 2)
        extensions.splitToSequence(" ").map { ext -> ext to mime }
    }.size
}

fun iterableDestinationSize(): Int {
    return "x,y z".lineSequence().flatMapTo(ArrayList<Pair<String, String>>()) { line ->
        if (line.isEmpty()) return@flatMapTo emptyList()
        line.split(" ").flatMap { word -> listOf(word to word) }
    }.size
}

fun main() {
    println(sequenceDestinationSize())
    println(iterableDestinationSize())
}
