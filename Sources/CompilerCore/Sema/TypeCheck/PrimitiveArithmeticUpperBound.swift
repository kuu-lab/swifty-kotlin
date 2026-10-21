func resolvePrimitiveArithmeticUpperBound(
    of type: TypeID,
    types: TypeSystem,
    symbols: SymbolTable
) -> TypeID? {
    func resolve(_ type: TypeID, definitelyNonNull: Bool = false, visited: inout Set<SymbolID>) -> TypeID? {
        switch types.kind(of: type) {
        case let .primitive(_, nullability) where nullability == .nonNull || definitelyNonNull:
            return types.makeNonNullable(type)
        case let .intersection(parts):
            // Null assertions and non-null flow checks represent T as T & Any.
            // That evidence removes nullability from T's declared upper bound.
            let nonNull = definitelyNonNull || parts.contains(types.anyType)
            let primitiveBounds = parts.compactMap { resolve($0, definitelyNonNull: nonNull, visited: &visited) }
            let uniqueBounds = Set(primitiveBounds)
            return uniqueBounds.count == 1 ? uniqueBounds.first : nil
        case let .typeParam(parameter):
            guard parameter.nullability == .nonNull || definitelyNonNull else { return nil }
            if let capture = parameter.capture {
                return resolve(capture.upper, definitelyNonNull: definitelyNonNull, visited: &visited)
            }
            guard visited.insert(parameter.symbol).inserted else { return nil }
            let primitiveBounds = symbols.typeParameterUpperBounds(for: parameter.symbol)
                .compactMap { resolve($0, definitelyNonNull: definitelyNonNull, visited: &visited) }
            let uniqueBounds = Set(primitiveBounds)
            return uniqueBounds.count == 1 ? uniqueBounds.first : nil
        default:
            return nil
        }
    }

    var visited: Set<SymbolID> = []
    return resolve(type, visited: &visited)
}
