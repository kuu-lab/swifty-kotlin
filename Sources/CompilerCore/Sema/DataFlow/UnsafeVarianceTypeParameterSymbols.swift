extension DataFlowSemaPhase {
    func unsafeVarianceTypeParameterSymbols(
        in typeRefID: TypeRefID?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        sourceManager: SourceManager?,
        localTypeParameters: [InternedString: SymbolID],
        relativeOwnerFQName: [InternedString]?,
        currentPackageFQName: [InternedString]?,
        imports: [ImportDecl],
        diagnostics: DiagnosticEngine?,
        usageRange: SourceRange?
    ) -> Set<SymbolID> {
        var result: Set<SymbolID> = []
        let localTypeParameterSymbols = Set(localTypeParameters.values)

        func visit(_ typeRefID: TypeRefID) {
            guard let typeRef = ast.arena.typeRef(typeRefID) else { return }
            switch typeRef {
            case let .named(_, args, _):
                for arg in args {
                    switch arg {
                    case let .invariant(inner), let .out(inner), let .in(inner):
                        visit(inner)
                    case .star:
                        break
                    }
                }
            case let .functionType(contextReceivers, receiver, params, returnType, _, _):
                for contextReceiver in contextReceivers {
                    visit(contextReceiver)
                }
                if let receiver {
                    visit(receiver)
                }
                for param in params {
                    visit(param)
                }
                visit(returnType)
            case let .intersection(parts):
                for part in parts {
                    visit(part)
                }
            case let .annotated(base, annotations):
                if annotations.contains(where: { KnownCompilerAnnotation.unsafeVariance.matches($0.name) }),
                   let annotatedType = resolveTypeRef(
                       base,
                       ast: ast,
                       symbols: symbols,
                       types: types,
                       interner: interner,
                       sourceManager: sourceManager,
                       localTypeParameters: localTypeParameters,
                       relativeOwnerFQName: relativeOwnerFQName,
                       currentPackageFQName: currentPackageFQName,
                       imports: imports,
                       diagnostics: diagnostics,
                       usageRange: usageRange
                   )
                {
                    for typeParameter in localTypeParameterSymbols
                    where types.typeContainsTypeParam(annotatedType, symbol: typeParameter) {
                        result.insert(typeParameter)
                    }
                }
                visit(base)
            }
        }

        if let typeRefID {
            visit(typeRefID)
        }
        return result
    }
}
