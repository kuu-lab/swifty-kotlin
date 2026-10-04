abstract class ProbeMap : AbstractMap<String?, Int?>()

fun noArg(values: Map<String?, Int?>): Boolean {
    return values.none()
}

fun predicate(values: Map<String?, Int?>): Boolean {
    return values.none { entry -> entry.key == null && entry.value == null }
}

fun projected(values: Map<Any?, Number>): Boolean {
    return values.none()
}

fun memberIsEmpty(values: Map<String?, Int?>): Boolean {
    return values.isEmpty()
}

fun listNone(values: List<Int?>): Boolean {
    return values.none()
}

fun collectionNone(values: Collection<Int?>): Boolean {
    return values.none()
}

fun sequenceNone(values: Sequence<Int?>): Boolean {
    return values.none()
}

fun customMap(values: ProbeMap): Boolean {
    return values.none()
}
