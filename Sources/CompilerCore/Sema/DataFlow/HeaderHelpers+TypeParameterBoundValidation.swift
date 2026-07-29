/// DEBT-SEMA-002: declaration-site consistency check for type parameter upper bounds.
///
/// Kotlin classes have single inheritance, so a `where` clause combining two or more
/// class-kind upper bounds (as opposed to interfaces) that share no subtype relationship
/// in either direction is unsatisfiable by any concrete type (e.g. `where T : Int, T :
/// String`). Unlike the call-site check (`KSWIFTK-SEMA-BOUND` in Resolution+Inference.swift),
/// which validates that a given type *argument* satisfies a type parameter's bounds, this
/// flags the *declaration* itself as unsatisfiable regardless of how it is ever used.
extension DataFlowSemaPhase {
    func checkConflictingClassUpperBounds(
        typeParamName: InternedString,
        bounds: [TypeID],
        declSite: SourceRange?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) {
        guard bounds.count > 1 else {
            return
        }
        let classLikeBounds = bounds.filter { bound in
            switch types.kind(of: bound) {
            case .primitive, .stringStruct:
                true
            case let .classType(classType):
                symbols.symbol(classType.classSymbol)?.kind != .interface
            default:
                false
            }
        }
        guard classLikeBounds.count > 1 else {
            return
        }
        for i in 0 ..< (classLikeBounds.count - 1) {
            for j in (i + 1) ..< classLikeBounds.count {
                let lhs = classLikeBounds[i]
                let rhs = classLikeBounds[j]
                guard !types.isSubtype(lhs, rhs), !types.isSubtype(rhs, lhs) else {
                    continue
                }
                let lhsName = types.displayName(of: lhs, symbols: symbols, interner: interner)
                let rhsName = types.displayName(of: rhs, symbols: symbols, interner: interner)
                diagnostics.error(
                    "KSWIFTK-SEMA-0305",
                    "Type parameter '\(interner.resolve(typeParamName))' has conflicting upper bounds: " +
                        "'\(lhsName)' and '\(rhsName)' cannot both be satisfied by any single type.",
                    range: declSite
                )
                return
            }
        }
    }
}
