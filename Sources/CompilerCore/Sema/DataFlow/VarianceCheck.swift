extension DataFlowSemaPhase {
    /// Which subset of the variance surface a pass inspects. Declared type
    /// references are validated in DataFlow before type checking; inferred
    /// member types exist only after TypeCheckSemaPhase has registered the
    /// member signatures, so they are validated in a second pass invoked at
    /// the end of type checking.
    private enum VarianceCheckPhase {
        case explicit
        case inferred
    }

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
        validateDeclarationSiteVariance(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: diagnostics, interner: interner, phase: .explicit
        )
    }

    /// Second pass for inferred member types — expression-body functions and
    /// annotation-less properties. Must run after member signatures and
    /// property types are registered (end of TypeCheckSemaPhase).
    func validateInferredMemberVariance(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        validateDeclarationSiteVariance(
            ast: ast, symbols: symbols, bindings: bindings, types: types,
            diagnostics: diagnostics, interner: interner, phase: .inferred
        )
    }

    private func validateDeclarationSiteVariance(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        phase: VarianceCheckPhase
    ) {
        let env = VarianceCheckEnv(ast: ast, symbols: symbols, bindings: bindings,
                                   types: types, diagnostics: diagnostics, interner: interner)
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateVarianceForDecl(declID: declID, env: env, phase: phase)
            }
        }
    }

    private enum VariancePosition: Hashable {
        case out
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

    private struct VarianceCheckEnv {
        let ast: ASTModule
        let symbols: SymbolTable
        let bindings: BindingTable
        let types: TypeSystem
        let diagnostics: DiagnosticEngine
        let interner: StringInterner
        var ownerFQName: [InternedString] = []
        var ownerSymbol: SymbolID?
    }

    private func validateVarianceForDecl(
        declID: DeclID, env: VarianceCheckEnv,
        outerVarianceMap: [InternedString: TypeVariance] = [:],
        outerVarianceSymbolMap: [SymbolID: TypeVariance] = [:],
        phase: VarianceCheckPhase
    ) {
        guard let decl = env.ast.arena.decl(declID) else { return }
        var env = env
        if let symbolID = env.bindings.declSymbol(for: declID) ?? nominalSymbolID(atDeclSite: declRange(decl), env: env),
           let symbol = env.symbols.symbol(symbolID) {
            env.ownerFQName = symbol.fqName
            env.ownerSymbol = symbolID
        }
        switch decl {
        case let .classDecl(classDecl):
            validateVarianceForClassDecl(classDecl, env: env, outerVarianceMap: outerVarianceMap,
                                         outerVarianceSymbolMap: outerVarianceSymbolMap, phase: phase)
        case let .interfaceDecl(interfaceDecl):
            validateVarianceForInterfaceDecl(interfaceDecl, env: env, outerVarianceMap: outerVarianceMap,
                                             outerVarianceSymbolMap: outerVarianceSymbolMap, phase: phase)
        case let .objectDecl(objectDecl):
            validateVarianceForObjectDecl(objectDecl, env: env, outerVarianceMap: outerVarianceMap,
                                          outerVarianceSymbolMap: outerVarianceSymbolMap, phase: phase)
        default:
            break
        }
    }

    private func declRange(_ decl: Decl) -> SourceRange? {
        switch decl {
        case let .classDecl(d): d.range
        case let .interfaceDecl(d): d.range
        case let .objectDecl(d): d.range
        default: nil
        }
    }

    /// Mirrors `varianceMap` with type-parameter *symbols* as keys. Inferred
    /// member types resolve type parameters to symbols, and a member can
    /// redeclare the enclosing parameter's name (`fun <T> leak() = item`
    /// still returns the class's `T`), so name-keyed lookup cannot
    /// distinguish the two. Built lazily — nominal parameter symbols only
    /// exist once the inferred pass runs.
    private func varianceSymbolMap(
        typeParams: [TypeParamDecl],
        outerVarianceSymbolMap: [SymbolID: TypeVariance],
        env: VarianceCheckEnv
    ) -> [SymbolID: TypeVariance] {
        var map = outerVarianceSymbolMap
        guard let owner = env.ownerSymbol else { return map }
        for (typeParam, symbol) in zip(typeParams, env.types.nominalTypeParameterSymbols(for: owner)) {
            map[symbol] = typeParam.variance == .invariant ? nil : typeParam.variance
        }
        return map
    }

    private func validateVarianceForClassDecl(
        _ classDecl: ClassDecl, env: VarianceCheckEnv,
        outerVarianceMap: [InternedString: TypeVariance] = [:],
        outerVarianceSymbolMap: [SymbolID: TypeVariance] = [:],
        phase: VarianceCheckPhase
    ) {
        var varianceMap = outerVarianceMap
        for typeParam in classDecl.typeParams {
            if typeParam.variance != .invariant {
                varianceMap[typeParam.name] = typeParam.variance
            } else {
                varianceMap.removeValue(forKey: typeParam.name)
            }
        }
        let varianceSymbolMap = phase == .inferred
            ? varianceSymbolMap(typeParams: classDecl.typeParams,
                                outerVarianceSymbolMap: outerVarianceSymbolMap, env: env)
            : [:]
        if phase == .explicit {
            validateSuperTypesAndBounds(classDecl.typeParams,
                                        superTypeRefs: classDecl.superTypeEntries.map(\.typeRef),
                                        declRange: classDecl.range,
                                        varianceMap: varianceMap, env: env)
        }
        validateMemberFunctions(classDecl.memberFunctions, varianceMap: varianceMap,
                                varianceSymbolMap: varianceSymbolMap, env: env, phase: phase)
        validateMemberProperties(classDecl.memberProperties, varianceMap: varianceMap,
                                 varianceSymbolMap: varianceSymbolMap, env: env, phase: phase)

        for nestedDeclID in classDecl.nestedClasses {
            let nestedIsInner = nestedClassIsInner(nestedDeclID, env: env)
            let outerMap = nestedIsInner ? varianceMap : [:]
            let outerSymbolMap = nestedIsInner ? varianceSymbolMap : [:]
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: outerMap,
                                    outerVarianceSymbolMap: outerSymbolMap, phase: phase)
        }
        for nestedDeclID in classDecl.nestedObjects {
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: [:], phase: phase)
        }
        if let companionID = classDecl.companionObject {
            validateVarianceForDecl(declID: companionID, env: env, outerVarianceMap: [:], phase: phase)
        }
    }

    private func validateVarianceForInterfaceDecl(
        _ iface: InterfaceDecl, env: VarianceCheckEnv,
        outerVarianceMap: [InternedString: TypeVariance] = [:],
        outerVarianceSymbolMap: [SymbolID: TypeVariance] = [:],
        phase: VarianceCheckPhase
    ) {
        var varianceMap = outerVarianceMap
        for typeParam in iface.typeParams {
            if typeParam.variance != .invariant {
                varianceMap[typeParam.name] = typeParam.variance
            } else {
                varianceMap.removeValue(forKey: typeParam.name)
            }
        }
        let varianceSymbolMap = phase == .inferred
            ? varianceSymbolMap(typeParams: iface.typeParams,
                                outerVarianceSymbolMap: outerVarianceSymbolMap, env: env)
            : [:]
        if phase == .explicit {
            validateSuperTypesAndBounds(iface.typeParams,
                                        superTypeRefs: iface.superTypes,
                                        declRange: iface.range,
                                        varianceMap: varianceMap, env: env)
        }
        validateMemberFunctions(iface.memberFunctions, varianceMap: varianceMap,
                                varianceSymbolMap: varianceSymbolMap, env: env, phase: phase)
        validateMemberProperties(iface.memberProperties, varianceMap: varianceMap,
                                 varianceSymbolMap: varianceSymbolMap, env: env, phase: phase)

        for nestedDeclID in iface.nestedClasses {
            let nestedIsInner = nestedClassIsInner(nestedDeclID, env: env)
            let outerMap = nestedIsInner ? varianceMap : [:]
            let outerSymbolMap = nestedIsInner ? varianceSymbolMap : [:]
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: outerMap,
                                    outerVarianceSymbolMap: outerSymbolMap, phase: phase)
        }
        for nestedDeclID in iface.nestedObjects {
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: [:], phase: phase)
        }
        if let companionID = iface.companionObject {
            validateVarianceForDecl(declID: companionID, env: env, outerVarianceMap: [:], phase: phase)
        }
    }

    private func validateVarianceForObjectDecl(
        _ objectDecl: ObjectDecl, env: VarianceCheckEnv,
        outerVarianceMap: [InternedString: TypeVariance],
        outerVarianceSymbolMap: [SymbolID: TypeVariance],
        phase: VarianceCheckPhase
    ) {
        // Objects cannot declare type parameters; only the enclosing
        // variance context applies.
        let varianceMap = outerVarianceMap
        if phase == .explicit {
            for superTypeRef in objectDecl.superTypeEntries.map(\.typeRef) {
                checkTypeRefVariance(superTypeRef, position: .out,
                                     varianceMap: varianceMap, env: env, memberRange: objectDecl.range)
            }
        }
        validateMemberFunctions(objectDecl.memberFunctions, varianceMap: varianceMap,
                                varianceSymbolMap: outerVarianceSymbolMap, env: env, phase: phase)
        validateMemberProperties(objectDecl.memberProperties, varianceMap: varianceMap,
                                 varianceSymbolMap: outerVarianceSymbolMap, env: env, phase: phase)

        for nestedDeclID in objectDecl.nestedClasses {
            let nestedIsInner = nestedClassIsInner(nestedDeclID, env: env)
            let outerMap = nestedIsInner ? varianceMap : [:]
            let outerSymbolMap = nestedIsInner ? outerVarianceSymbolMap : [:]
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: outerMap,
                                    outerVarianceSymbolMap: outerSymbolMap, phase: phase)
        }
        for nestedDeclID in objectDecl.nestedObjects {
            validateVarianceForDecl(declID: nestedDeclID, env: env, outerVarianceMap: [:], phase: phase)
        }
    }

    /// Supertypes and type-parameter upper bounds are part of the declared
    /// signature: a `T` written there sits at the supertype/bound's declared
    /// variance position, so `class Source<out T> : Sink<T>` illegally places
    /// `out T` in Sink's `in` position. Delegated supertypes are checked the
    /// same way — the `by` clause does not exempt the type itself.
    private func validateSuperTypesAndBounds(
        _ typeParams: [TypeParamDecl],
        superTypeRefs: [TypeRefID],
        declRange: SourceRange,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        guard !varianceMap.isEmpty else { return }
        for typeParam in typeParams {
            for upperBound in typeParam.upperBounds {
                checkTypeRefVariance(upperBound, position: .out,
                                     varianceMap: varianceMap, env: env, memberRange: declRange)
            }
        }
        for superTypeRef in superTypeRefs {
            checkTypeRefVariance(superTypeRef, position: .out,
                                 varianceMap: varianceMap, env: env, memberRange: declRange)
        }
    }

    private func validateMemberFunctions(
        _ funDeclIDs: [DeclID],
        varianceMap: [InternedString: TypeVariance],
        varianceSymbolMap: [SymbolID: TypeVariance],
        env: VarianceCheckEnv,
        phase: VarianceCheckPhase
    ) {
        for funDeclID in funDeclIDs {
            guard let funDecl = env.ast.arena.decl(funDeclID),
                  case let .funDecl(fun) = funDecl,
                  !fun.modifiers.contains(.private)
            else { continue }
            validateFunctionVariance(fun, varianceMap: varianceMap,
                                     varianceSymbolMap: varianceSymbolMap, env: env, phase: phase)
        }
    }

    private func validateMemberProperties(
        _ propDeclIDs: [DeclID],
        varianceMap: [InternedString: TypeVariance],
        varianceSymbolMap: [SymbolID: TypeVariance],
        env: VarianceCheckEnv,
        phase: VarianceCheckPhase
    ) {
        for propDeclID in propDeclIDs {
            guard let propDecl = env.ast.arena.decl(propDeclID),
                  case let .propertyDecl(prop) = propDecl,
                  !prop.modifiers.contains(.private)
            else { continue }
            validatePropertyVariance(prop, varianceMap: varianceMap,
                                     varianceSymbolMap: varianceSymbolMap, env: env, phase: phase)
        }
    }

    private func nestedClassIsInner(_ declID: DeclID, env: VarianceCheckEnv) -> Bool {
        guard let decl = env.ast.arena.decl(declID),
              case let .classDecl(classDecl) = decl else { return false }
        return classDecl.isInner
    }

    /// Member declarations are lazily bound and never enter `declSymbols`;
    /// the decl-site index is how member symbols are recovered (the same
    /// pattern the constructor checkers use).
    private func memberSymbolID(
        atDeclSite range: SourceRange, kind: SymbolKind, env: VarianceCheckEnv
    ) -> SymbolID? {
        env.symbols.symbols(atDeclSite: range).first {
            env.symbols.symbol($0)?.kind == kind
        }
    }

    /// Nested nominal declarations are likewise absent from `declSymbols`;
    /// recover the nominal symbol through the decl-site index when binding
    /// lookup fails.
    private func nominalSymbolID(atDeclSite range: SourceRange?, env: VarianceCheckEnv) -> SymbolID? {
        guard let range else { return nil }
        return env.symbols.symbols(atDeclSite: range).first {
            switch env.symbols.symbol($0)?.kind {
            case .class, .interface, .enumClass, .annotationClass, .object: true
            default: false
            }
        }
    }

    private func validateFunctionVariance(
        _ funDecl: FunDecl,
        varianceMap: [InternedString: TypeVariance],
        varianceSymbolMap: [SymbolID: TypeVariance],
        env: VarianceCheckEnv,
        phase: VarianceCheckPhase
    ) {
        var effectiveMap = varianceMap
        for typeParam in funDecl.typeParams {
            effectiveMap.removeValue(forKey: typeParam.name)
        }
        if phase == .explicit {
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
        }
        if let returnTypeRef = funDecl.returnType {
            guard phase == .explicit else { return }
            checkTypeRefVariance(returnTypeRef, position: .out,
                                 varianceMap: effectiveMap, env: env, memberRange: funDecl.range)
        } else if phase == .inferred, !varianceSymbolMap.isEmpty,
                  let symbolID = memberSymbolID(atDeclSite: funDecl.range, kind: .function, env: env),
                  let returnType = env.symbols.functionSignature(for: symbolID)?.returnType {
            // Expression-body functions publish an inferred return type; it
            // still leaks the declaration-site parameter into an `out`
            // position (`fun leak() = item` on `Sink<in T>`). The signature's
            // own type-parameter symbols are distinct from the enclosing
            // class's, so shadowed names (`fun <T> …`) resolve correctly.
            checkTypeIDVariance(returnType, position: .out,
                                varianceSymbolMap: varianceSymbolMap, env: env, memberRange: funDecl.range)
        }
    }

    private func validatePropertyVariance(
        _ propertyDecl: PropertyDecl,
        varianceMap: [InternedString: TypeVariance],
        varianceSymbolMap: [SymbolID: TypeVariance],
        env: VarianceCheckEnv,
        phase: VarianceCheckPhase
    ) {
        if phase == .explicit, let receiverTypeRef = propertyDecl.receiverType {
            checkTypeRefVariance(receiverTypeRef, position: .contravariant,
                                 varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
        }
        if let typeRefID = propertyDecl.type {
            guard phase == .explicit else { return }
            if propertyDecl.isVar {
                checkTypeRefVariance(typeRefID, position: .contravariant,
                                     varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
            }
            checkTypeRefVariance(typeRefID, position: .out,
                                 varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
            return
        }
        guard phase == .inferred, !varianceSymbolMap.isEmpty,
              let symbolID = memberSymbolID(atDeclSite: propertyDecl.range, kind: .property, env: env),
              let inferredType = env.symbols.propertyType(for: symbolID) else { return }
        // Annotation-less `val x get() = …` / `var x = …` infer their public
        // type from the initializer or getter; check the inferred type at the
        // same positions a declared one occupies.
        if propertyDecl.isVar {
            checkTypeIDVariance(inferredType, position: .contravariant,
                                varianceSymbolMap: varianceSymbolMap, env: env, memberRange: propertyDecl.range)
        }
        checkTypeIDVariance(inferredType, position: .out,
                            varianceSymbolMap: varianceSymbolMap, env: env, memberRange: propertyDecl.range)
    }

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

    /// TypeID-level twin of `checkTypeRefVariance` for inferred member types —
    /// expression-body functions and annotation-less properties have no
    /// TypeRef, but their inferred signatures are equally part of the
    /// declaration's public surface. Keys are type-parameter symbols, so a
    /// member redeclaring the parameter's name cannot hide a class `T` that
    /// leaks into the inferred type.
    private func checkTypeIDVariance(
        _ typeID: TypeID,
        position: VariancePosition,
        varianceSymbolMap: [SymbolID: TypeVariance],
        env: VarianceCheckEnv,
        memberRange: SourceRange,
        depth: Int = 0
    ) {
        guard depth <= Self.maxStructuralRecursionDepth else { return }
        switch env.types.kind(of: typeID) {
        case let .typeParam(typeParam):
            guard let declaredVariance = varianceSymbolMap[typeParam.symbol] else { return }
            let paramName = env.symbols.symbol(typeParam.symbol)
                .map { env.interner.resolve($0.name) } ?? "T"
            emitVarianceViolation(paramName: paramName,
                                  declaredVariance: declaredVariance,
                                  position: position, diagnostics: env.diagnostics, range: memberRange)
        case let .classType(nominal):
            let declaredVariances = env.types.nominalTypeParameterVariances(for: nominal.classSymbol)
            for (index, argument) in nominal.args.enumerated() {
                let declaredVariance = index < declaredVariances.count ? declaredVariances[index] : .invariant
                switch argument {
                case let .invariant(type):
                    checkTypeIDVariance(type, position: position.composed(with: declaredVariance),
                                        varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
                case let .out(type):
                    checkTypeIDVariance(type, position: position,
                                        varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
                case let .in(type):
                    checkTypeIDVariance(type, position: position.flipped,
                                        varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
                case .star:
                    break
                }
            }
        case let .functionType(function):
            for contextReceiver in function.contextReceivers {
                checkTypeIDVariance(contextReceiver, position: position.flipped,
                                    varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
            }
            if let receiver = function.receiver {
                checkTypeIDVariance(receiver, position: position.flipped,
                                    varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
            }
            for param in function.params {
                checkTypeIDVariance(param, position: position.flipped,
                                    varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
            }
            checkTypeIDVariance(function.returnType, position: position,
                                varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
        case let .intersection(parts):
            for part in parts {
                checkTypeIDVariance(part, position: position,
                                    varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
            }
        case let .kClassType(kClass):
            checkTypeIDVariance(kClass.argument, position: position,
                                varianceSymbolMap: varianceSymbolMap, env: env, memberRange: memberRange, depth: depth + 1)
        default:
            break
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
