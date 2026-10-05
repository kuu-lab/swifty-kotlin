extension DataFlowSemaPhase {
    /// Validates declaration-site variance constraints for all classes and interfaces.
    /// Kotlin rules:
    /// - `out T` (covariant): T may only appear in out positions (return types, val property types).
    /// - `in T` (contravariant): T may only appear in in positions (function parameters).
    /// - Private members are exempt from variance checks (Kotlin spec).
    /// - Constructor parameters are exempt from variance checks.
    func validateDeclarationSiteVariance(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let env = VarianceCheckEnv(ast: ast, symbols: symbols, bindings: bindings,
                                   types: types, diagnostics: diagnostics, interner: interner)
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateVarianceForDecl(declID: declID, env: env)
            }
        }
    }

    /// Represents the expected position for variance checking.
    private enum VariancePosition: Hashable {
        /// Covariant position: return types, val property types, out type args
        case out
        /// Contravariant position: function parameters, in type args
        case contravariant
        case invariant

        var flipped: VariancePosition {
            switch self {
            case .out: .contravariant
            case .contravariant: .out
            case .invariant: .invariant
            }
        }

        func composed(with variance: TypeVariance) -> VariancePosition {
            switch variance {
            case .out: self
            case .in: flipped
            case .invariant: .invariant
            }
        }
    }

    /// Bundles the immutable context needed by every variance-check helper.
    private struct VarianceCheckEnv {
        let ast: ASTModule
        let symbols: SymbolTable
        let bindings: BindingTable
        let types: TypeSystem
        let diagnostics: DiagnosticEngine
        let interner: StringInterner
        var ownerFQName: [InternedString] = []
    }

    // MARK: - Declaration dispatch

    private func validateVarianceForDecl(
        declID: DeclID, env: VarianceCheckEnv,
        outerVarianceMap: [InternedString: TypeVariance] = [:]
    ) {
        guard let decl = env.ast.arena.decl(declID) else { return }
        var env = env
        if let symbolID = env.bindings.declSymbol(for: declID),
           let symbol = env.symbols.symbol(symbolID) {
            env.ownerFQName = symbol.fqName
        }
        switch decl {
        case let .classDecl(classDecl):
            validateVarianceForClassDecl(classDecl, env: env, outerVarianceMap: outerVarianceMap)
        case let .interfaceDecl(interfaceDecl):
            validateVarianceForInterfaceDecl(interfaceDecl, env: env, outerVarianceMap: outerVarianceMap)
        default:
            break
        }
    }

    private func validateVarianceForClassDecl(
        _ classDecl: ClassDecl, env: VarianceCheckEnv,
        outerVarianceMap: [InternedString: TypeVariance] = [:]
    ) {
        var varianceMap = outerVarianceMap
        for typeParam in classDecl.typeParams {
            if typeParam.variance != .invariant {
                varianceMap[typeParam.name] = typeParam.variance
            } else {
                varianceMap.removeValue(forKey: typeParam.name)
            }
        }
        validateMemberFunctions(classDecl.memberFunctions, varianceMap: varianceMap, env: env)
        validateMemberProperties(classDecl.memberProperties, varianceMap: varianceMap, env: env)

        for nestedDeclID in classDecl.nestedClasses {
            let nestedIsInner = nestedClassIsInner(nestedDeclID, env: env)
            let outerMap = nestedIsInner ? varianceMap : [:]
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: outerMap)
        }
    }

    private func validateVarianceForInterfaceDecl(
        _ iface: InterfaceDecl, env: VarianceCheckEnv,
        outerVarianceMap: [InternedString: TypeVariance] = [:]
    ) {
        var varianceMap = outerVarianceMap
        for typeParam in iface.typeParams {
            if typeParam.variance != .invariant {
                varianceMap[typeParam.name] = typeParam.variance
            } else {
                varianceMap.removeValue(forKey: typeParam.name)
            }
        }
        validateMemberFunctions(iface.memberFunctions, varianceMap: varianceMap, env: env)
        validateMemberProperties(iface.memberProperties, varianceMap: varianceMap, env: env)

        for nestedDeclID in iface.nestedClasses {
            let nestedIsInner = nestedClassIsInner(nestedDeclID, env: env)
            let outerMap = nestedIsInner ? varianceMap : [:]
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: outerMap)
        }
    }

    // MARK: - Member iteration

    private func validateMemberFunctions(
        _ funDeclIDs: [DeclID],
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        for funDeclID in funDeclIDs {
            guard let funDecl = env.ast.arena.decl(funDeclID),
                  case let .funDecl(fun) = funDecl,
                  !fun.modifiers.contains(.private)
            else { continue }
            validateFunctionVariance(fun, varianceMap: varianceMap, env: env)
        }
    }

    private func validateMemberProperties(
        _ propDeclIDs: [DeclID],
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        for propDeclID in propDeclIDs {
            guard let propDecl = env.ast.arena.decl(propDeclID),
                  case let .propertyDecl(prop) = propDecl,
                  !prop.modifiers.contains(.private)
            else { continue }
            validatePropertyVariance(prop, varianceMap: varianceMap, env: env)
        }
    }

    private func nestedClassIsInner(_ declID: DeclID, env: VarianceCheckEnv) -> Bool {
        guard let decl = env.ast.arena.decl(declID),
              case let .classDecl(classDecl) = decl else { return false }
        return classDecl.isInner
    }

    private func validateFunctionVariance(
        _ funDecl: FunDecl,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        var effectiveMap = varianceMap
        for typeParam in funDecl.typeParams {
            effectiveMap.removeValue(forKey: typeParam.name)
        }
        guard !effectiveMap.isEmpty else { return }
        for valueParam in funDecl.valueParams {
            if let typeRefID = valueParam.type {
                checkTypeRefVariance(typeRefID, position: .contravariant,
                                     varianceMap: effectiveMap, env: env, memberRange: funDecl.range)
            }
        }
        if let receiverTypeRef = funDecl.receiverType {
            checkTypeRefVariance(receiverTypeRef, position: .contravariant,
                                 varianceMap: effectiveMap, env: env, memberRange: funDecl.range)
        }
        if let returnTypeRef = funDecl.returnType {
            checkTypeRefVariance(returnTypeRef, position: .out,
                                 varianceMap: effectiveMap, env: env, memberRange: funDecl.range)
        }
    }

    private func validatePropertyVariance(
        _ propertyDecl: PropertyDecl,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        if let receiverTypeRef = propertyDecl.receiverType {
            checkTypeRefVariance(receiverTypeRef, position: .contravariant,
                                 varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
        }
        guard let typeRefID = propertyDecl.type else { return }
        if propertyDecl.isVar {
            checkTypeRefVariance(typeRefID, position: .contravariant,
                                 varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
        }
        checkTypeRefVariance(typeRefID, position: .out,
                             varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
    }

    // MARK: - Type reference variance checking

    private func checkTypeRefVariance(
        _ typeRefID: TypeRefID,
        position: VariancePosition,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv,
        memberRange: SourceRange
    ) {
        guard let typeRef = env.ast.arena.typeRef(typeRefID) else { return }
        switch typeRef {
        case let .named(path, typeArgs, _):
            checkNamedTypeVariance(typeRefID: typeRefID, path: path, typeArgs: typeArgs, position: position,
                                   varianceMap: varianceMap, env: env, memberRange: memberRange)
        case let .functionType(contextReceiverTypeRefs, receiverTypeRef, paramTypeRefs, returnTypeRef, _, _):
            for contextReceiverTypeRef in contextReceiverTypeRefs {
                checkTypeRefVariance(contextReceiverTypeRef, position: position.flipped,
                                     varianceMap: varianceMap, env: env, memberRange: memberRange)
            }
            if let receiverTypeRef {
                checkTypeRefVariance(receiverTypeRef, position: position.flipped,
                                     varianceMap: varianceMap, env: env, memberRange: memberRange)
            }
            checkFunctionTypeVariance(params: paramTypeRefs, ret: returnTypeRef,
                                      position: position, varianceMap: varianceMap,
                                      env: env, memberRange: memberRange)
        case let .intersection(parts):
            for partRef in parts {
                checkTypeRefVariance(partRef, position: position,
                                     varianceMap: varianceMap, env: env, memberRange: memberRange)
            }
        case let .annotated(base, annotations):
            if annotations.contains(where: { KnownCompilerAnnotation.unsafeVariance.matches($0.name) }) {
                return
            }
            checkTypeRefVariance(base, position: position,
                                 varianceMap: varianceMap, env: env, memberRange: memberRange)
        }
    }

    private func checkNamedTypeVariance(
        typeRefID: TypeRefID,
        path: [InternedString],
        typeArgs: [TypeArgRef],
        position: VariancePosition,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv,
        memberRange: SourceRange
    ) {
        if path.count == 1, let name = path.first, let declaredVariance = varianceMap[name] {
            emitVarianceViolation(paramName: env.interner.resolve(name),
                                  declaredVariance: declaredVariance,
                                  position: position, diagnostics: env.diagnostics, range: memberRange)
        }
        guard !typeArgs.isEmpty else { return }
        let file = env.ast.file(for: memberRange.start.file)
        let resolvedType = resolveTypeRef(
            typeRefID, ast: env.ast, symbols: env.symbols, types: env.types,
            interner: env.interner, relativeOwnerFQName: env.ownerFQName,
            currentPackageFQName: file?.packageFQName, imports: file?.imports ?? [],
            expandTypeAlias: false
        )
        let declaredVariances: [TypeVariance?]
        if let resolvedType, case let .classType(nominal) = env.types.kind(of: resolvedType) {
            if let underlying = env.symbols.typeAliasUnderlyingType(for: nominal.classSymbol) {
                declaredVariances = env.symbols.typeAliasTypeParameters(for: nominal.classSymbol).map { parameter in
                    let positions = aliasParameterPositions(parameter, in: underlying, position: .out, env: env)
                    if positions.isEmpty { return nil }
                    if positions == [.out] { return .out }
                    if positions == [.contravariant] { return .in }
                    return .invariant
                }
            } else {
                declaredVariances = env.types.nominalTypeParameterVariances(for: nominal.classSymbol).map { $0 }
            }
        } else if let resolvedType, case .kClassType = env.types.kind(of: resolvedType) {
            declaredVariances = [.out]
        } else {
            declaredVariances = []
        }
        for (index, typeArg) in typeArgs.enumerated() {
            guard let declaredVariance = index < declaredVariances.count ? declaredVariances[index] : .invariant else { continue }
            let (innerRefID, innerPosition) = typeArgProjection(
                typeArg, declaredVariance: declaredVariance, position: position
            )
            guard let refID = innerRefID else { continue }
            checkTypeRefVariance(refID, position: innerPosition,
                                 varianceMap: varianceMap, env: env, memberRange: memberRange)
        }
    }

    private func aliasParameterPositions(
        _ parameter: SymbolID, in type: TypeID, position: VariancePosition,
        env: VarianceCheckEnv, depth: Int = 0
    ) -> Set<VariancePosition> {
        guard depth <= Self.maxStructuralRecursionDepth else { return [.invariant] }
        switch env.types.kind(of: type) {
        case let .typeParam(typeParam):
            return typeParam.symbol == parameter ? [position] : []
        case let .classType(nominal):
            let variances = env.types.nominalTypeParameterVariances(for: nominal.classSymbol)
            var positions: Set<VariancePosition> = []
            for (index, argument) in nominal.args.enumerated() {
                let innerType: TypeID
                let innerPosition: VariancePosition
                switch argument {
                case let .invariant(type):
                    innerType = type
                    innerPosition = position.composed(with: index < variances.count ? variances[index] : .invariant)
                case let .out(type):
                    innerType = type
                    innerPosition = position
                case let .in(type):
                    innerType = type
                    innerPosition = position.flipped
                case .star:
                    continue
                }
                positions.formUnion(aliasParameterPositions(parameter, in: innerType, position: innerPosition, env: env, depth: depth + 1))
            }
            return positions
        case let .functionType(function):
            var positions = aliasParameterPositions(parameter, in: function.returnType, position: position, env: env, depth: depth + 1)
            let inputs = function.contextReceivers + (function.receiver.map { [$0] } ?? []) + function.params
            for input in inputs {
                positions.formUnion(aliasParameterPositions(parameter, in: input, position: position.flipped, env: env, depth: depth + 1))
            }
            return positions
        case let .kClassType(kClass):
            return aliasParameterPositions(parameter, in: kClass.argument, position: position, env: env, depth: depth + 1)
        case let .intersection(parts):
            return parts.reduce(into: []) { positions, part in
                positions.formUnion(aliasParameterPositions(parameter, in: part, position: position, env: env, depth: depth + 1))
            }
        default:
            return []
        }
    }

    private func typeArgProjection(
        _ typeArg: TypeArgRef, declaredVariance: TypeVariance, position: VariancePosition
    ) -> (TypeRefID?, VariancePosition) {
        switch typeArg {
        case let .invariant(ref): (ref, position.composed(with: declaredVariance))
        case let .out(ref): (ref, position)
        case let .in(ref): (ref, position.flipped)
        case .star: (nil, position)
        }
    }

    private func checkFunctionTypeVariance(
        params: [TypeRefID],
        ret: TypeRefID,
        position: VariancePosition,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv,
        memberRange: SourceRange
    ) {
        for paramRef in params {
            checkTypeRefVariance(paramRef, position: position.flipped,
                                 varianceMap: varianceMap, env: env, memberRange: memberRange)
        }
        checkTypeRefVariance(ret, position: position,
                             varianceMap: varianceMap, env: env, memberRange: memberRange)
    }

    private func emitVarianceViolation(
        paramName: String,
        declaredVariance: TypeVariance,
        position: VariancePosition,
        diagnostics: DiagnosticEngine,
        range: SourceRange?
    ) {
        switch (declaredVariance, position) {
        case (.out, .contravariant), (.out, .invariant):
            diagnostics.error(
                "KSWIFTK-SEMA-VARIANCE",
                "Type parameter \(paramName) is declared as 'out' but occurs in '\(position == .invariant ? "invariant" : "in")' position",
                range: range
            )
        case (.in, .out), (.in, .invariant):
            diagnostics.error(
                "KSWIFTK-SEMA-VARIANCE",
                "Type parameter \(paramName) is declared as 'in' but occurs in '\(position == .invariant ? "invariant" : "out")' position",
                range: range
            )
        default:
            break
        }
    }
}
