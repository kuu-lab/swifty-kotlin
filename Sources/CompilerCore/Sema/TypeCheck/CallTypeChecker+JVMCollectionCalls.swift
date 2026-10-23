extension CallTypeChecker {
    static func jvmSequenceAggregateResultType(
        member: String,
        elementType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        guard case let .primitive(primitive, .nonNull) = sema.types.kind(of: elementType) else { return nil }
        return switch member {
        case "sum":
            switch primitive {
            case .byte, .short, .int: sema.types.intType
            case .long: sema.types.longType
            case .float: sema.types.floatType
            case .double: sema.types.doubleType
            case .ubyte, .ushort, .uint: sema.types.uintType
            case .ulong: sema.types.ulongType
            case .boolean, .char: nil
            }
        case "average":
            switch primitive {
            case .byte, .short, .int, .long, .float, .double: sema.types.doubleType
            case .boolean, .char, .ubyte, .ushort, .uint, .ulong: nil
            }
        default: nil
        }
    }

    /// These APIs have complete JVM support declarations; keep their real
    /// receiver, generic, default, and inline/crossinline contracts in Sema.
    static let jvmSourceCollectionCalls: Set<String> = [
        "groupBy", "associate", "associateBy", "associateWith", "partition", "zip", "zipWithNext", "joinToString",
        "map", "mapIndexed", "mapNotNull", "mapIndexedNotNull", "filter", "filterNot", "filterIndexed", "filterNotNull",
        "flatMap", "flatten", "forEach", "fold", "any", "all", "none", "count", "first", "firstOrNull",
        "asSequence", "asIterable", "constrainOnce", "onEach", "onEachIndexed", "take", "drop", "takeWhile", "dropWhile",
        "distinct", "distinctBy", "sorted", "sortedDescending", "sortedBy", "sortedByDescending", "toMap",
        "toList", "toMutableList", "toSet", "toMutableSet", "chunked", "windowed", "reversed",
        "elementAt", "elementAtOrNull", "minOrNull", "maxOrNull", "last", "lastOrNull", "single", "singleOrNull",
    ]
}
