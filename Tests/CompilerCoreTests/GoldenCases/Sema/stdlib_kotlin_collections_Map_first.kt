fun mapFirst(values: Map<String?, Int?>): String {
    return values.firstNotNullOf<String> { entry ->
        if (entry.value != null) entry.key ?: "missing" else null
    }
}

fun mapFirstOrNull(values: Map<String?, Int?>): String? {
    return values.firstNotNullOfOrNull<String> { entry ->
        if (entry.key == null) "null-key" else null
    }
}
