func resolvePrimitiveArithmeticUpperBound(
    of type: TypeID,
    types: TypeSystem,
    symbols: SymbolTable
) -> TypeID? {
    func resolve(_ type: TypeID, visited: inout Set<SymbolID>) -> TypeID? {
        switch types.kind(of: type) {
        case .primitive(_, .nonNull):
            return type
        case let .intersection(parts):
            let primitiveBounds = parts.compactMap { resolve($0, visited: &visited) }
            let uniqueBounds = Set(primitiveBounds)
            return uniqueBounds.count == 1 ? uniqueBounds.first : nil
        case let .typeParam(parameter):
            guard parameter.nullability == .nonNull else { return nil }
            if let capture = parameter.capture {
                return resolve(capture.upper, visited: &visited)
            }
            guard visited.insert(parameter.symbol).inserted else { return nil }
            let primitiveBounds = symbols.typeParameterUpperBounds(for: parameter.symbol)
                .compactMap { resolve($0, visited: &visited) }
            let uniqueBounds = Set(primitiveBounds)
            return uniqueBounds.count == 1 ? uniqueBounds.first : nil
        default:
            return nil
        }
    }

    var visited: Set<SymbolID> = []
    return resolve(type, visited: &visited)
}
