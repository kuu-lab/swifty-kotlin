extension DataFlowSemaPhase {
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
        // kotlinc sees `ConcurrentMap.putIfAbsent`/`replace(K, V)` as `V?`,
        // not `V!`: the Kotlin compiler's JDK nullability data marks the
        // conditional-update returns nullable, so `map.putIfAbsent(k, v)`
        // flows into `println(Any?)` and prints "null" instead of raising the
        // platform null assertion (KUU-3059).
        ["java", "util", "concurrent", "ConcurrentHashMap"]: ["computeIfAbsent"],
    ]
}
