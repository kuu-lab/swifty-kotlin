extension DeclTypeChecker {
    /// Anonymous implementation details remain visible through private/local
    /// declarations. Exposed APIs also approximate nested type arguments and
    /// function results, so their metadata never leaks anonymous member types.
    func exposedAnonymousType(_ type: TypeID, symbol: SymbolID, range: SourceRange, ctx: TypeInferenceContext) -> TypeID {
        let sema = ctx.sema
        guard sema.symbols.symbol(symbol)?.visibility != .private else { return type }
        func expose(_ id: TypeID) -> TypeID {
            switch sema.types.kind(of: id) {
            case let .functionType(f):
                return sema.types.make(.functionType(FunctionType(contextReceivers: f.contextReceivers.map(expose), receiver: f.receiver.map(expose), params: f.params.map(expose), returnType: expose(f.returnType), isSuspend: f.isSuspend, isCallableReference: f.isCallableReference, nullability: f.nullability, throws: f.throws.map(expose))))
            case let .classType(c):
                let arguments = c.args.map { $0.mapTypes(expose) }
                // An `inner` class carries its enclosing owner's type
                // arguments in `enclosingTypeArgs`; rebuilding the nominal
                // without them erases the capture (`G<T>.It` -> bare `It`)
                // and later member calls fail to bind (KUU-3874).
                let enclosingArguments = c.enclosingTypeArgs.map { $0.mapTypes(expose) }
                guard let info = sema.symbols.symbol(c.classSymbol), info.kind == .class, info.flags.contains(.synthetic), ctx.interner.resolve(info.name).hasPrefix("__ObjectLiteral_") else {
                    return sema.types.make(.classType(ClassType(classSymbol: c.classSymbol, args: arguments, enclosingTypeArgs: enclosingArguments, nullability: c.nullability)))
                }
                let parents = sema.symbols.directSupertypes(for: c.classSymbol).filter {
                    sema.symbols.symbol($0)?.fqName.map(ctx.interner.resolve) != ["kotlin", "Any"]
                }
                guard parents.count <= 1 else {
                    sema.diagnostics.error("KSWIFTK-SEMA-0001", "An exposed anonymous object with multiple supertypes requires an explicit type.", range: range)
                    return sema.types.errorType
                }
                if let parent = parents.first {
                    // Supertype type args are stored flat (enclosing first,
                    // then own) so an inner-class supertype keeps its capture;
                    // `classType(for:)` splits them back out.
                    return sema.types.make(.classType(sema.types.classType(
                        for: parent,
                        arguments: sema.symbols.supertypeTypeArgs(for: c.classSymbol, supertype: parent).map { $0.mapTypes(expose) },
                        nullability: c.nullability
                    )))
                }
                return c.nullability == .nonNull ? sema.types.anyType : sema.types.nullableAnyType
            default: return id
            }
        }
        return expose(type)
    }
}
