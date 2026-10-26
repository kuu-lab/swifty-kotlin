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

/// Resolves a primitive upper bound while preserving whether it may be null.
/// Equality lowering uses this to select the null-aware IEEE path for a
/// `T : Double?`/`T : Float?` operand; arithmetic and relational operators
/// continue to use `resolvePrimitiveArithmeticUpperBound`, which requires
/// non-null evidence.
func resolvePrimitiveValueUpperBound(
    of type: TypeID,
    types: TypeSystem,
    symbols: SymbolTable
) -> TypeID? {
    func resolve(
        _ type: TypeID,
        definitelyNonNull: Bool = false,
        visited: inout Set<SymbolID>
    ) -> TypeID? {
        switch types.kind(of: type) {
        case let .primitive(primitive, nullability):
            return types.make(.primitive(
                primitive,
                definitelyNonNull ? .nonNull : nullability
            ))
        case let .intersection(parts):
            let nonNull = definitelyNonNull || parts.contains(types.anyType)
            let primitiveBounds = parts.compactMap {
                resolve($0, definitelyNonNull: nonNull, visited: &visited)
            }
            let uniqueBounds = Set(primitiveBounds)
            return uniqueBounds.count == 1 ? uniqueBounds.first : nil
        case let .typeParam(parameter):
            let primitiveBounds: [TypeID]
            if let capture = parameter.capture {
                guard let upperBound = resolve(
                    capture.upper,
                    definitelyNonNull: definitelyNonNull,
                    visited: &visited
                ) else {
                    return nil
                }
                primitiveBounds = [upperBound]
            } else {
                guard visited.insert(parameter.symbol).inserted else { return nil }
                primitiveBounds = symbols.typeParameterUpperBounds(for: parameter.symbol)
                    .compactMap {
                        resolve($0, definitelyNonNull: definitelyNonNull, visited: &visited)
                    }
            }
            let uniqueBounds = Set(primitiveBounds)
            guard uniqueBounds.count == 1, let primitiveBound = uniqueBounds.first else {
                return nil
            }
            let withTypeNullability = parameter.nullability == .nullable
                ? types.makeNullable(primitiveBound)
                : primitiveBound
            return definitelyNonNull ? types.makeNonNullable(withTypeNullability) : withTypeNullability
        default:
            return nil
        }
    }

    var visited: Set<SymbolID> = []
    return resolve(type, visited: &visited)
}
