
extension DataFlowSemaPhase {
    func validateConstPropertyDeclaration(
        _ propertyDecl: PropertyDecl,
        propertySymbol: SymbolID,
        resolvedType: TypeID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard propertyDecl.modifiers.contains(.const) else {
            return
        }

        if propertyDecl.isVar {
            diagnostics.error(
                "KSWIFTK-SEMA-0080",
                "'const' modifier is not applicable to 'var'.",
                range: propertyDecl.range
            )
        }
        if propertyDecl.initializer == nil {
            diagnostics.error(
                "KSWIFTK-SEMA-0081",
                "'const val' must have an initializer.",
                range: propertyDecl.range
            )
        }
        // When we have an explicit type annotation, validate that the resolved
        // type is a non-null primitive or String.  For inferred types the
        // header phase still has `Any?` as a placeholder, so we only run the
        // check when a concrete annotated type is available.
        if propertyDecl.type != nil {
            let isConstCompatible = switch types.kind(of: resolvedType) {
            case let .primitive(_, nullability):
                nullability == .nonNull
            case let .stringStruct(nullability):
                nullability == .nonNull
            default:
                false
            }
            if !isConstCompatible {
                diagnostics.error(
                    "KSWIFTK-SEMA-0082",
                    "'const val' type must be a primitive type or String.",
                    range: propertyDecl.range
                )
            }
        }
        // Seed literal values for type inference. References are evaluated
        // after type checking has bound all initializers to their symbols.
        if let initExpr = propertyDecl.initializer {
            let constCollector = ConstantCollector()
            if let constKind = constCollector.literalConstantExpr(initExpr, ast: ast, interner: interner) {
                symbols.setConstValueExprKind(
                    constCollector.convertConstant(constKind, to: resolvedType, types: types),
                    for: propertySymbol
                )
            }
        }
    }
}
