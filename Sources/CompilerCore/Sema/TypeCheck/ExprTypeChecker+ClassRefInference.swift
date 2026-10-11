
extension ExprTypeChecker {
    /// Resolve bare classifier paths without interpreting a segment as a constructor call.
    func inferQualifiedClassRefExpr(
        _ id: ExprID,
        receiver: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let ast = ctx.ast
        var segments: [(expr: ExprID, name: InternedString)] = []
        func collect(_ expr: ExprID) -> Bool {
            switch ast.arena.expr(expr) {
            case let .nameRef(name, _):
                segments.append((expr, name))
                return true
            case let .memberCall(owner, name, typeArguments, arguments, _):
                guard arguments.isEmpty, typeArguments.isEmpty,
                      !ast.arena.isExplicitCall(expr), collect(owner) else { return false }
                segments.append((expr, name))
                return true
            default:
                return false
            }
        }
        guard collect(receiver), segments.count > 1,
              let first = segments.first
        else { return nil }
        if let local = locals[first.name], sema.symbols.symbol(local.symbol)?.kind != .function {
            return nil
        }
        if let implicitReceiver = ctx.implicitReceiverType,
           driver.helpers.lookupMemberProperty(
               named: first.name, receiverType: sema.types.makeNonNullable(implicitReceiver), sema: sema
           ) != nil {
            return nil
        }

        func isClassifier(_ symbol: SemanticSymbol) -> Bool {
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass: true
            default: false
            }
        }
        // Values retain lexical priority; uninvoked functions do not qualify a type path.
        let roots = ctx.scope.lookup(first.name, matching: { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind != .function && symbol.kind != .constructor
        })
        var path: [InternedString] = []
        var resolved: [(ExprID, SymbolID)] = []
        for (index, segment) in segments.enumerated() {
            let candidates: [SymbolID]
            if index == 0, !roots.isEmpty {
                candidates = roots
            } else {
                candidates = sema.symbols.lookupAll(fqName: path + [segment.name])
            }
            let symbols = candidates.compactMap { ctx.cachedSymbol($0) }
            if symbols.contains(where: { !isClassifier($0) && $0.kind != .package
                && $0.kind != .function && $0.kind != .constructor }) {
                return nil
            }
            if let classifier = symbols.first(where: isClassifier) {
                path = classifier.fqName
                resolved.append((segment.expr, classifier.id))
            } else {
                // Package prefixes need no runtime receiver or expression binding.
                guard resolved.isEmpty else { return nil }
                path.append(segment.name)
            }
        }
        guard let target = resolved.last, target.0 == receiver else { return nil }
        for (expr, symbolID) in resolved {
            guard let symbol = ctx.cachedSymbol(symbolID) else { return nil }
            guard ctx.visibilityChecker.isAccessible(
                symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
            ) else {
                driver.helpers.emitVisibilityError(
                    for: symbol, name: ctx.interner.resolve(symbol.name), range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            driver.helpers.checkDeprecation(
                for: symbolID, sema: sema, interner: ctx.interner, range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: symbolID, ctx: ctx, range: range, diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindIdentifier(expr, symbol: symbolID)
            sema.bindings.bindExprType(expr, type: sema.types.make(.classType(ClassType(classSymbol: symbolID))))
        }
        let targetType = sema.types.make(.classType(ClassType(classSymbol: target.1)))
        sema.bindings.bindClassRefTargetType(id, type: targetType)
        let result = sema.types.makeKClassType(argument: targetType)
        sema.bindings.bindExprType(id, type: result)
        return result
    }

    func inferClassRefExpr(
        _ id: ExprID,
        receiver: ExprID,
        receiverName: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let allCandidateIDs = ctx.cachedScopeLookup(receiverName)
        for candidateID in allCandidateIDs {
            guard let sym = ctx.cachedSymbol(candidateID),
                  sym.kind == .typeParameter else { continue }
            if !sym.flags.contains(.reifiedTypeParameter) {
                let name = interner.resolve(sym.name)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-REIFIED",
                    "Cannot use 'T::class' on non-reified type parameter '\(name)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let resolved = sema.types.make(.typeParam(TypeParamType(symbol: sym.id)))
            sema.bindings.bindClassRefTargetType(id, type: resolved)
            let kClassType = sema.types.makeKClassType(argument: resolved)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        for candidateID in allCandidateIDs {
            guard let sym = ctx.cachedSymbol(candidateID),
                  sym.kind == .class || sym.kind == .interface
                  || sym.kind == .object || sym.kind == .enumClass
                  || sym.kind == .annotationClass
            else { continue }
            let classType = sema.types.make(.classType(ClassType(classSymbol: sym.id)))
            sema.bindings.bindClassRefTargetType(id, type: classType)
            let kClassType = sema.types.makeKClassType(argument: classType)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        // REFL-002: Handle builtin/primitive type names (Int, String, Boolean, etc.)
        // These are not class symbols in the symbol table but still support ::class.
        let builtinNames = driver.builtinTypeNamesCache
        if let builtinType = builtinNames.resolveBuiltinType(receiverName, types: sema.types) {
            sema.bindings.bindClassRefTargetType(id, type: builtinType)
            let kClassType = sema.types.makeKClassType(argument: builtinType)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        // KUU-1084: `FunctionN::class`. The synthetic `kotlin.Function.FunctionN`
        // interfaces live outside ordinary scope lookup, but `FunctionN::class`
        // is the classifier of every arity-N function type in Kotlin.
        let receiverNameString = interner.resolve(receiverName)
        if receiverNameString.hasPrefix("Function"),
           let arity = Int(receiverNameString.dropFirst("Function".count)),
           arity >= 0 {
            let functionFQName = [
                interner.intern("kotlin"), interner.intern("Function"), receiverName,
            ]
            if let functionSymbol = sema.symbols.lookupAll(fqName: functionFQName)
                .compactMap({ sema.symbols.symbol($0) })
                .first(where: { $0.kind == .interface })?.id {
                let classType = sema.types.make(.classType(ClassType(classSymbol: functionSymbol)))
                sema.bindings.bindClassRefTargetType(id, type: classType)
                let kClassType = sema.types.makeKClassType(argument: classType)
                sema.bindings.bindExprType(id, type: kClassType)
                _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
                return kClassType
            }
        }
        return nil
    }

    func inferExprReceiverClassRef(
        _ id: ExprID,
        receiver: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let receiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        if receiverType == sema.types.errorType {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        // A qualified classifier such as `Outer.Nested` is a static class
        // literal, even when Outer has a companion value. Do not evaluate it
        // as a bound receiver; constructor calls and properties stay bound.
        if case let .memberCall(_, _, _, args, _) = ctx.ast.arena.expr(receiver),
           args.isEmpty, !ctx.ast.arena.isExplicitCall(receiver),
           let symbolID = sema.bindings.identifierSymbol(for: receiver),
           let symbol = sema.symbols.symbol(symbolID),
           symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass
               || symbol.kind == .annotationClass || symbol.kind == .object
        {
            let targetType = sema.types.makeNonNullable(receiverType)
            sema.bindings.bindClassRefTargetType(id, type: targetType)
            let kClassType = sema.types.makeKClassType(argument: targetType)
            sema.bindings.bindExprType(id, type: kClassType)
            return kClassType
        }
        var visited: Set<TypeID> = []
        let isFlowNonNull: Bool
        if case let .nameRef(name, _) = ctx.ast.arena.expr(receiver),
           let local = locals[name],
           let flow = ctx.flowState.variables[local.symbol] {
            isFlowNonNull = flow.isStable && flow.nullability == .nonNull
        } else {
            isFlowNonNull = false
        }
        if !isFlowNonNull, classRefReceiverCanBeNull(receiverType, sema: sema, visited: &visited) {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-CLASS-REF-NULLABLE",
                "Expression in a class literal has a nullable type. Use '!!' to make it non-nullable.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let targetType = sema.types.makeNonNullable(receiverType)
        sema.bindings.bindClassRefTargetType(id, type: targetType)
        sema.bindings.bindBoundClassRef(id)
        let kClassType = sema.types.makeKClassType(argument: targetType)
        sema.bindings.bindExprType(id, type: kClassType)
        return kClassType
    }

    private func classRefReceiverCanBeNull(_ type: TypeID, sema: SemaModule, visited: inout Set<TypeID>) -> Bool {
        guard visited.insert(type).inserted else {
            return true
        }
        switch sema.types.kind(of: type) {
        case let .typeParam(parameter):
            if parameter.nullability == .nullable {
                return true
            }
            let bounds = sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
            return bounds.allSatisfy { classRefReceiverCanBeNull($0, sema: sema, visited: &visited) }
        case let .intersection(parts):
            return parts.allSatisfy { classRefReceiverCanBeNull($0, sema: sema, visited: &visited) }
        default:
            return sema.types.nullability(of: type) == .nullable
        }
    }
}
