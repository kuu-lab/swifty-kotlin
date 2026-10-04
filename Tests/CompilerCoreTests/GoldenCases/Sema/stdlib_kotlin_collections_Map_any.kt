abstract class ProbeMap : AbstractMap<String?, Int?>()

fun noArg(values: Map<String?, Int?>): Boolean {
    return values.any()
}

fun predicate(values: Map<String?, Int?>): Boolean {
    return values.any { entry -> entry.key == null && entry.value == null }
}

fun customMap(values: ProbeMap): Boolean {
    return values.any()
}
