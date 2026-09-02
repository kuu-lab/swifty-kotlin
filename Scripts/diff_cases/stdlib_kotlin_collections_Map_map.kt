fun mapToCase(source: Map<String, String?>, destination: MutableList<Any?>): MutableList<Any?> {
    return source.mapTo(destination) { entry -> entry.value }
}

fun mapNotNullToCase(source: Map<String, String?>, destination: MutableSet<Any?>): MutableSet<Any?> {
    return source.mapNotNullTo(destination) { entry -> entry.value }
}

fun mapKeysToCase(source: Map<String, String?>, destination: MutableMap<Any?, Any?>): MutableMap<Any?, Any?> {
    return source.mapKeysTo(destination) { entry -> entry.key }
}

fun mapValuesToCase(source: Map<String, String?>, destination: MutableMap<Any?, Any?>): MutableMap<Any?, Any?> {
    return source.mapValuesTo(destination) { entry -> entry.value }
}

fun main() {
    val source = mapOf("a" to "A", "b" to null)
    val list = mutableListOf<Any?>("existing")
    val set = mutableSetOf<Any?>("existing")
    val keys = mutableMapOf<Any?, Any?>(null to "existing")
    val values = mutableMapOf<Any?, Any?>(null to "existing")

    val mappedList = mapToCase(source, list)
    val mappedSet = mapNotNullToCase(source, set)
    val mappedKeys = mapKeysToCase(source, keys)
    val mappedValues = mapValuesToCase(source, values)
    println("mapTo identity=${mappedList === list} value=$mappedList")
    println("mapNotNullTo identity=${mappedSet === set} value=$mappedSet")
    println("mapKeysTo identity=${mappedKeys === keys} value=$mappedKeys")
    println("mapValuesTo identity=${mappedValues === values} value=$mappedValues")

    val duplicateKeys = mutableMapOf<Any?, Any?>("existing" to "keep")
    mapOf("a" to "A", "same" to "S").mapKeysTo(duplicateKeys) {
        if (it.key == "a") "same" else it.key
    }
    println("duplicateKeys=$duplicateKeys")

    val interrupted = mutableListOf<Any?>("existing")
    try {
        source.mapTo(interrupted) { entry ->
            if (entry.key == "b") throw IllegalStateException("stop")
            entry.value
        }
    } catch (e: IllegalStateException) {
        println("exception=${e.message} partial=$interrupted")
    }
}
