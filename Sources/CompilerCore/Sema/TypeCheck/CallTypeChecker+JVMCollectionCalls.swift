extension CallTypeChecker {
    /// These APIs have complete JVM support declarations; keep their real
    /// receiver, generic, default, and inline/crossinline contracts in Sema.
    static let jvmSourceCollectionCalls: Set<String> = [
        "groupBy", "associate", "associateBy", "associateWith", "partition", "zip", "zipWithNext", "joinToString",
        "map", "mapIndexed", "mapNotNull", "mapIndexedNotNull", "filter", "filterNot", "filterIndexed", "filterNotNull",
        "flatMap", "flatten", "forEach", "fold", "any", "all", "none", "count", "first", "firstOrNull",
        "asSequence", "asIterable", "constrainOnce", "onEach", "onEachIndexed", "take", "takeLast", "takeWhile",
        "drop", "dropWhile", "dropLastWhile",
        "distinct", "distinctBy", "sorted", "sortedDescending", "sortedBy", "sortedByDescending", "toMap",
        "toList", "toMutableList", "toSet", "toMutableSet", "chunked", "windowed", "reversed",
        "elementAt", "elementAtOrNull", "minOrNull", "maxOrNull", "last", "lastOrNull", "single", "singleOrNull",
    ]
}
