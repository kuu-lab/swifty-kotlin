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
