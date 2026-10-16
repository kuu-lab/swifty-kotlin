extension DataFlowSemaPhase {
    /// Restore Java's mapped generic arguments only for the bundled facade.
    /// Call-site inference preserves Kotlin/JVM 2.3.10's flexible arguments.
    func javaCollectionsParameterTypes(
        _ parameters: [TypeID],
        fqName: [InternedString],
        types: TypeSystem,
        interner: StringInterner
    ) -> [TypeID] {
        guard parameters.count == 1,
              isJavaCollectionsViewMethod(fqName, interner: interner),
              case let .classType(parameter) = types.kind(of: parameters[0])
        else { return parameters }
        let args = parameter.args.map { argument -> TypeArg in
            switch argument {
            case let .invariant(type):
                return .invariant(javaCollectionsPlatformArgument(type, types: types))
            case let .out(type):
                if interner.resolve(fqName[3]) == "newSetFromMap",
                   case .primitive(.boolean, _) = types.kind(of: type) {
                    return .out(types.withNullability(.platformType, for: type))
                }
                return .out(javaCollectionsPlatformArgument(type, types: types))
            default: return argument
            }
        }
        return [types.make(.classType(ClassType(
            classSymbol: parameter.classSymbol,
            args: args,
            enclosingTypeArgs: parameter.enclosingTypeArgs,
            nullability: parameter.nullability
        )))]
    }

    func javaCollectionsReturnType(
        _ type: TypeID,
        fqName: [InternedString],
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard isJavaCollectionsViewMethod(fqName, interner: interner),
              case let .classType(result) = types.kind(of: type)
        else { return type }
        let args = result.args.map { argument -> TypeArg in
            guard case let .invariant(element) = argument else { return argument }
            return .invariant(javaCollectionsPlatformArgument(element, types: types))
        }
        return types.make(.classType(ClassType(
            classSymbol: result.classSymbol,
            args: args,
            enclosingTypeArgs: result.enclosingTypeArgs,
            nullability: result.nullability
        )))
    }

    private func javaCollectionsPlatformArgument(_ type: TypeID, types: TypeSystem) -> TypeID {
        guard case .typeParam = types.kind(of: type) else { return type }
        return types.withNullability(.platformType, for: type)
    }

    private func isJavaCollectionsViewMethod(_ fqName: [InternedString], interner: StringInterner) -> Bool {
        guard fqName.count == 4,
              ["unmodifiableList", "unmodifiableSet", "unmodifiableMap", "newSetFromMap"].contains(interner.resolve(fqName[3]))
        else { return false }
        return fqName.prefix(3).map { interner.resolve($0) } == ["java", "util", "Collections"]
    }
}
