extension DataFlowSemaPhase {
    /// Returns the flexible `T!` view of a bundled java.* member's declared
    /// nullable return type when the member's JVM counterpart is an
    /// unannotated Java declaration (KUU-3869).
    ///
    /// Kotlin/JVM resolves these call-site results as platform types, so
    /// `list.pollFirst().member` compiles without `?.`/`!!`. The bundled
    /// bodies keep their `T?` implementations — empty or absent results are
    /// still a genuine null, and the platform contract routes non-null uses
    /// through a runtime null assertion like the JVM intrinsic checks do.
    ///
    /// Restricted to compiler-owned API surfaces: Kotlin declarations a user
    /// adds under java.* retain normal Kotlin nullable rules.
    func javaPlatformNullReturnType(
        _ returnType: TypeID,
        ownerFQName: [String]?,
        memberName: String,
        classTypeParameterSymbols: [SymbolID],
        types: TypeSystem
    ) -> TypeID {
        guard let ownerFQName,
              let memberNames = Self.javaPlatformNullReturningMembers[ownerFQName],
              memberNames.contains(memberName)
        else { return returnType }
        switch types.kind(of: returnType) {
        case let .typeParam(element):
            guard element.nullability == .nullable,
                  classTypeParameterSymbols.contains(element.symbol)
            else { return returnType }
            return types.withNullability(.platformType, for: returnType)
        case let .classType(classType):
            // e.g. `MutableMap.MutableEntry<K, V>?` / `Comparator<in K>?` —
            // Java leaves the reference and every type-variable use inside it
            // unannotated, so the outer reference and its type-parameter
            // arguments are all flexible.
            guard classType.nullability == .nullable else { return returnType }
            return types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: classType.args.map { javaPlatformNullArgument($0, types: types) },
                enclosingTypeArgs: classType.enclosingTypeArgs,
                nullability: .platformType
            )))
        case .stringStruct, .any:
            guard types.nullability(of: returnType) == .nullable else { return returnType }
            return types.withNullability(.platformType, for: returnType)
        default:
            return returnType
        }
    }

    /// Marks a type-variable argument of a platform-returned parameterized
    /// type flexible (`K`/`V` -> `K!`/`V!`), matching Java's unannotated
    /// signature. Non-type-parameter arguments keep Kotlin nullability.
    private func javaPlatformNullArgument(_ argument: TypeArg, types: TypeSystem) -> TypeArg {
        switch argument {
        case let .invariant(type):
            return .invariant(javaPlatformNullTypeArgument(type, types: types))
        case let .in(type):
            return .in(javaPlatformNullTypeArgument(type, types: types))
        case let .out(type):
            return .out(javaPlatformNullTypeArgument(type, types: types))
        case .star:
            return argument
        }
    }

    private func javaPlatformNullTypeArgument(_ type: TypeID, types: TypeSystem) -> TypeID {
        guard case .typeParam = types.kind(of: type) else { return type }
        return types.withNullability(.platformType, for: type)
    }

    /// Bundled java.* owner -> member names whose declared nullable return is
    /// an unannotated reference on the JVM. Entries span the Queue/Deque
    /// poll/peek family (the KUU-3869 surface), the sorted navigable views,
    /// the concurrent-map conditional-update returns, and the same-shaped
    /// nullable utilities (`Properties`, `Objects.toString`, `Matcher.group`).
    private static let javaPlatformNullReturningMembers: [[String]: Set<String>] = [
        ["java", "util", "Queue"]: ["peek", "poll"],
        ["java", "util", "LinkedList"]: ["peek", "peekFirst", "peekLast", "poll", "pollFirst", "pollLast"],
        ["java", "util", "ArrayDeque"]: ["peek", "peekFirst", "peekLast", "poll", "pollFirst", "pollLast"],
        ["java", "util", "PriorityQueue"]: ["comparator", "peek", "poll"],
        ["java", "util", "NavigableSet"]: ["ceiling", "floor", "higher", "lower", "pollFirst", "pollLast"],
        ["java", "util", "NavigableMap"]: [
            "ceilingKey", "firstEntry", "floorKey", "higherKey",
            "lastEntry", "lowerKey", "pollFirstEntry", "pollLastEntry",
        ],
        ["java", "util", "SortedMap"]: ["comparator"],
        ["java", "util", "SortedSet"]: ["comparator"],
        ["java", "util", "Properties"]: ["getProperty", "setProperty"],
        ["java", "util", "Objects"]: ["toString"],
        ["java", "util", "regex", "Matcher"]: ["group"],
        ["java", "util", "concurrent", "ConcurrentLinkedQueue"]: ["peek", "poll"],
        ["java", "util", "concurrent", "ConcurrentMap"]: ["putIfAbsent", "replace"],
        ["java", "util", "concurrent", "ConcurrentHashMap"]: ["computeIfAbsent", "putIfAbsent", "replace"],
    ]
}
