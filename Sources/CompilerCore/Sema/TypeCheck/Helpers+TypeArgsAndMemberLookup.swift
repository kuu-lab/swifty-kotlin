
extension TypeCheckHelpers {
    private struct MemberDispatchKey: Hashable, CustomStringConvertible {
        let name: InternedString
        let parameterTypes: [TypeID]
        let isSuspend: Bool

        var description: String {
            return "\(name):\(parameterTypes.count)"
        }
    }

    func substituteAliasArg(
        _ arg: TypeArg,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            if case let .typeParam(tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if tp.nullability == .nullable {
                    return applyNullabilityToTypeArg(replacement, types: sema.types)
                }
                return replacement
            }
            return .invariant(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case let .out(inner):
            if case let .typeParam(tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerTypeForCheck(replacement)
                let resolved = tp.nullability == .nullable ? applyNullabilityForTypeCheck(innerType, types: sema.types) : innerType
                return .out(resolved)
            }
            return .out(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case let .in(inner):
            if case let .typeParam(tp) = sema.types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerTypeForCheck(replacement)
                let resolved = tp.nullability == .nullable ? applyNullabilityForTypeCheck(innerType, types: sema.types) : innerType
                return .in(resolved)
            }
            return .in(applyAliasSubstitution(inner, argSubstitution: argSubstitution, sema: sema))
        case .star:
            return .star
        }
    }

    /// Apply nullability to a type, handling function types, primitives, and special types
    /// that `TypeSystem.makeNullable` may not wrap correctly.
    /// Mirrors `DataFlowSemaPhase.applyNullability`.
    func applyNullabilityForTypeCheck(_ typeID: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: typeID) {
        case let .primitive(p, _):
            return types.make(.primitive(p, .nullable))
        case .stringStruct:
            return types.makeNullable(typeID)
        case let .classType(ct):
            return types.make(.classType(ClassType(classSymbol: ct.classSymbol, args: ct.args, nullability: .nullable)))
        case let .typeParam(tp):
            return types.make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: .nullable)))
        case let .functionType(ft):
            return types.make(.functionType(FunctionType(contextReceivers: ft.contextReceivers, receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, nullability: .nullable)))
        case let .kClassType(kc):
            return types.make(.kClassType(KClassType(argument: kc.argument, nullability: .nullable)))
        case .any, .unit, .nothing:
            let nullable = types.makeNullable(typeID)
            if nullable == typeID {
                return types.isSubtype(types.nullableNothingType, typeID) ? typeID : types.nullableAnyType
            }
            return nullable
        default:
            return types.nullableAnyType
        }
    }

    func applyNullabilityToTypeArg(_ arg: TypeArg, types: TypeSystem) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            .invariant(applyNullabilityForTypeCheck(inner, types: types))
        case let .out(inner):
            .out(applyNullabilityForTypeCheck(inner, types: types))
        case let .in(inner):
            .in(applyNullabilityForTypeCheck(inner, types: types))
        case .star:
            .star
        }
    }

    func typeArgInnerTypeForCheck(_ arg: TypeArg) -> TypeID {
        switch arg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            inner
        case .star:
            TypeID.invalid
        }
    }

    /// Variance position when walking a type for use-site projection checks.
    private enum AliasVariancePosition {
        case out
        case contravariant

        var flipped: AliasVariancePosition {
            switch self {
            case .out: .contravariant
            case .contravariant: .out
            }
        }
    }

    /// Validate that use-site variance projections on a typealias instantiation are
    /// sound with respect to occurrences of the alias type parameters in the
    /// underlying type.
    ///
    /// Kotlin: typealias type parameters are always invariant (declaration-site
    /// `out`/`in` are not permitted on the alias itself), but callers may apply
    /// use-site projections (`out T`, `in T`, `*`). A projection is rejected when
    /// the substituted parameter occurs in the expanded underlying type at an
    /// incompatible variance position — the same rule as for class/interface type
    /// parameters, except the effective variance comes from the use-site projection
    /// rather than a declaration-site modifier.
    func validateVarianceAfterExpansion(
        _: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        sema: SemaModule,
        diagnostics: DiagnosticEngine? = nil
    ) {
        let typeParamSymbols = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
        guard !typeParamSymbols.isEmpty, typeArgs.count == typeParamSymbols.count else {
            return
        }
        guard let underlying = sema.symbols.typeAliasUnderlyingType(for: aliasSymbol) else {
            return
        }

        var projectionMap: [SymbolID: TypeVariance] = [:]
        for (index, paramSymbol) in typeParamSymbols.enumerated() {
            guard index < typeArgs.count else { break }
            switch typeArgs[index] {
            case .out:
                projectionMap[paramSymbol] = .out
            case .in:
                projectionMap[paramSymbol] = .in
            case .invariant, .star:
                break
            }
        }
        guard !projectionMap.isEmpty else { return }

        let declSite = sema.symbols.symbol(aliasSymbol)?.declSite
        checkAliasUnderlyingTypeVariance(
            underlying,
            projectionMap: projectionMap,
            position: .out,
            sema: sema,
            diagnostics: diagnostics,
            range: declSite
        )
    }

    private func checkAliasUnderlyingTypeVariance(
        _ typeID: TypeID,
        projectionMap: [SymbolID: TypeVariance],
        position: AliasVariancePosition,
        sema: SemaModule,
        diagnostics: DiagnosticEngine?,
        range: SourceRange?
    ) {
        switch sema.types.kind(of: typeID) {
        case let .typeParam(typeParam):
            guard let projection = projectionMap[typeParam.symbol] else { return }
            emitAliasUseSiteVarianceViolation(
                projection: projection,
                position: position,
                diagnostics: diagnostics,
                range: range
            )
        case let .classType(classType):
            for arg in classType.args {
                let (innerType, innerPosition) = projectedAliasTypeArg(arg, position: position)
                guard let innerType else { continue }
                checkAliasUnderlyingTypeVariance(
                    innerType,
                    projectionMap: projectionMap,
                    position: innerPosition,
                    sema: sema,
                    diagnostics: diagnostics,
                    range: range
                )
            }
        case let .functionType(functionType):
            for contextReceiver in functionType.contextReceivers {
                checkAliasUnderlyingTypeVariance(
                    contextReceiver,
                    projectionMap: projectionMap,
                    position: position.flipped,
                    sema: sema,
                    diagnostics: diagnostics,
                    range: range
                )
            }
            if let receiver = functionType.receiver {
                checkAliasUnderlyingTypeVariance(
                    receiver,
                    projectionMap: projectionMap,
                    position: position.flipped,
                    sema: sema,
                    diagnostics: diagnostics,
                    range: range
                )
            }
            for param in functionType.params {
                checkAliasUnderlyingTypeVariance(
                    param,
                    projectionMap: projectionMap,
                    position: position.flipped,
                    sema: sema,
                    diagnostics: diagnostics,
                    range: range
                )
            }
            checkAliasUnderlyingTypeVariance(
                functionType.returnType,
                projectionMap: projectionMap,
                position: position,
                sema: sema,
                diagnostics: diagnostics,
                range: range
            )
        case let .kClassType(kClassType):
            checkAliasUnderlyingTypeVariance(
                kClassType.argument,
                projectionMap: projectionMap,
                position: position,
                sema: sema,
                diagnostics: diagnostics,
                range: range
            )
        case let .intersection(parts):
            for part in parts {
                checkAliasUnderlyingTypeVariance(
                    part,
                    projectionMap: projectionMap,
                    position: position,
                    sema: sema,
                    diagnostics: diagnostics,
                    range: range
                )
            }
        case .error, .unit, .nothing, .any, .primitive, .stringStruct:
            break
        }
    }

    private func projectedAliasTypeArg(
        _ arg: TypeArg,
        position: AliasVariancePosition
    ) -> (TypeID?, AliasVariancePosition) {
        switch arg {
        case let .invariant(type):
            (type, position)
        case let .out(type):
            (type, position)
        case let .in(type):
            (type, position.flipped)
        case .star:
            (nil, position)
        }
    }

    private func emitAliasUseSiteVarianceViolation(
        projection: TypeVariance,
        position: AliasVariancePosition,
        diagnostics: DiagnosticEngine?,
        range: SourceRange?
    ) {
        let violation: (code: String, message: String)? = switch (projection, position) {
        case (.out, .contravariant):
            ("KSWIFTK-SEMA-VARIANCE", "Type parameter is projected as 'out' but occurs in 'in' position")
        case (.in, .out):
            ("KSWIFTK-SEMA-VARIANCE", "Type parameter is projected as 'in' but occurs in 'out' position")
        default:
            nil
        }
        guard let violation else { return }
        diagnostics?.error(violation.code, violation.message, range: range)
    }

    func resolveExplicitTypeArgs(
        _ typeArgRefs: [TypeRefID],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil
    ) -> [TypeID] {
        guard !typeArgRefs.isEmpty else { return [] }
        return typeArgRefs.map { typeRefID in
            resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics)
        }
    }

    /// Check if an expression is a terminating expression (return/throw) for elvis guard narrowing.
    func isTerminatingExpr(_ expr: Expr) -> Bool {
        switch expr {
        case .returnExpr:
            true
        case .throwExpr:
            true
        default:
            false
        }
    }

    func compoundAssignToBinaryOp(_ op: CompoundAssignOp) -> BinaryOp {
        switch op {
        case .plusAssign: .add
        case .minusAssign: .subtract
        case .timesAssign: .multiply
        case .divAssign: .divide
        case .modAssign: .modulo
        }
    }

    func nominalSymbol(of type: TypeID, types: TypeSystem) -> SymbolID? {
        switch types.kind(of: type) {
        case let .classType(classType):
            return classType.classSymbol
        case let .intersection(parts):
            // For intersection types, return the first nominal part
            for part in parts {
                if let symbol = nominalSymbol(of: part, types: types) {
                    return symbol
                }
            }
            return nil
        default:
            return nil
        }
    }

    /// Collects all nominal symbols from a type, including all parts of an intersection.
    /// For type parameters, follows upper bounds to discover interface symbols.
    func allNominalSymbols(of type: TypeID, types: TypeSystem, symbols: SymbolTable) -> [SymbolID] {
        var visited = Set<SymbolID>()
        return allNominalSymbolsImpl(of: type, types: types, symbols: symbols, visited: &visited)
    }

    private func allNominalSymbolsImpl(
        of type: TypeID,
        types: TypeSystem,
        symbols: SymbolTable,
        visited: inout Set<SymbolID>
    ) -> [SymbolID] {
        switch types.kind(of: type) {
        case let .classType(classType):
            return [classType.classSymbol]
        case .kClassType:
            if let kClassSymbol = types.kClassInterfaceSymbol {
                return [kClassSymbol]
            }
            return []
        case let .intersection(parts):
            return parts.flatMap { allNominalSymbolsImpl(of: $0, types: types, symbols: symbols, visited: &visited) }
        case let .typeParam(typeParam):
            // Guard against cycles (e.g. T : U, U : T).
            guard visited.insert(typeParam.symbol).inserted else { return [] }
            let bounds = symbols.typeParameterUpperBounds(for: typeParam.symbol)
            return bounds.flatMap { allNominalSymbolsImpl(of: $0, types: types, symbols: symbols, visited: &visited) }
        default:
            return []
        }
    }

    func collectMemberFunctionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        allowedOwnerSymbols: Set<SymbolID>? = nil,
        interner: StringInterner
    ) -> [SymbolID] {
        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols)

        var ownerQueue: [(owner: SymbolID, depth: Int)] = nominalRoots.map { ($0, 0) }
        var visitedOwners: Set<SymbolID> = []
        var ownersInLookupOrder: [(owner: SymbolID, depth: Int)] = []
        while !ownerQueue.isEmpty {
            let (owner, depth) = ownerQueue.removeFirst()
            guard visitedOwners.insert(owner).inserted else {
                continue
            }
            if let allowedOwnerSymbols {
                if allowedOwnerSymbols.contains(owner) {
                    ownersInLookupOrder.append((owner, depth))
                }
            } else {
                ownersInLookupOrder.append((owner, depth))
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner).map { ($0, depth + 1) })
        }

        var candidatesByKey: [MemberDispatchKey: [(symbol: SymbolID, owner: SymbolID, depth: Int)]] = [:]
        var keyOrder: [MemberDispatchKey] = []
        var seenCandidates: Set<SymbolID> = []

        func dispatchParameterTypes(
            for signature: FunctionSignature,
            owner: SymbolID
        ) -> [TypeID] {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            guard case let .classType(classType) = sema.types.kind(of: nonNullReceiver),
                  sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: owner),
                  let ownerTypeArgs = sema.types.liftedNominalSupertypeArgs(
                      from: classType.classSymbol,
                      childArgs: classType.args,
                      to: owner
                  )
            else {
                return signature.parameterTypes
            }

            let ownerTypeParamSymbols = sema.types.nominalTypeParameterSymbols(for: owner)
            guard !ownerTypeParamSymbols.isEmpty else {
                return signature.parameterTypes
            }

            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(ownerTypeParamSymbols)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, typeParamSymbol) in ownerTypeParamSymbols.enumerated() {
                guard index < ownerTypeArgs.count,
                      let typeVar = typeVarBySymbol[typeParamSymbol]
                else {
                    continue
                }
                switch ownerTypeArgs[index] {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    substitution[typeVar] = inner
                case .star:
                    substitution[typeVar] = sema.types.nullableAnyType
                }
            }

            guard !substitution.isEmpty else {
                return signature.parameterTypes
            }
            return signature.parameterTypes.map {
                sema.types.substituteTypeParameters(
                    in: $0,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
        }

        func appendCandidates(
            owner: SymbolID,
            ownerFQName: [InternedString],
            depth: Int,
            requireReceiverSubtype: Bool
        ) {
            let memberFQName = ownerFQName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard seenCandidates.insert(candidate).inserted,
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let signatureReceiverType = signature.receiverType
                else {
                    continue
                }
                if requireReceiverSubtype,
                   !sema.types.isSubtype(receiverType, signatureReceiverType)
                {
                    let isRangeUntil = calleeName == interner.intern("rangeUntil")
                        && ownerFQName == [interner.intern("kotlin"), interner.intern("ranges")]
                    let genericReceiver = if isRangeUntil,
                                             case .typeParam = sema.types.kind(of: sema.types.makeNonNullable(signatureReceiverType)) {
                        true
                    } else {
                        false
                    }
                    if !genericReceiver {
                        continue
                    }
                }
                let key = MemberDispatchKey(
                    name: calleeName,
                    parameterTypes: dispatchParameterTypes(for: signature, owner: owner),
                    isSuspend: signature.isSuspend
                )
                if candidatesByKey[key] == nil {
                    keyOrder.append(key)
                }
                candidatesByKey[key, default: []].append((candidate, owner, depth))
            }
        }

        let receiverKind = sema.types.kind(of: receiverType)
        if ownersInLookupOrder.isEmpty, case .primitive = receiverKind {
            // Primitive receivers have no nominal owners, so probe the synthetic stdlib
            // packages that host their extension members.
            let primitiveExtensionPackages: [[InternedString]] = [
                [interner.intern("kotlin")],
                [interner.intern("kotlin"), interner.intern("ranges")],
                [interner.intern("kotlin"), interner.intern("text")],
            ]
            for packageFQName in primitiveExtensionPackages {
                guard let packageSymbol = sema.symbols.lookup(fqName: packageFQName) else {
                    continue
                }
                appendCandidates(
                    owner: packageSymbol,
                    ownerFQName: packageFQName,
                    depth: 0,
                    requireReceiverSubtype: true
                )
            }
        }

        for (owner, depth) in ownersInLookupOrder {
            guard let ownerSymbol = sema.symbols.symbol(owner) else {
                continue
            }
            appendCandidates(
                owner: owner,
                ownerFQName: ownerSymbol.fqName,
                depth: depth,
                requireReceiverSubtype: false
            )
        }

        var candidates: [SymbolID] = []
        var overrideDepthByShape: [String: Int] = [:]
        for grouped in candidatesByKey.values {
            for candidate in grouped {
                guard sema.symbols.symbol(candidate.symbol)?.flags.contains(.overrideMember) == true,
                      let signature = sema.symbols.functionSignature(for: candidate.symbol)
                else {
                    continue
                }
                let shape = "\(signature.parameterTypes.count)#\(signature.isSuspend)"
                overrideDepthByShape[shape] = min(overrideDepthByShape[shape] ?? candidate.depth, candidate.depth)
            }
        }
        for key in keyOrder {
            guard let grouped = candidatesByKey[key], !grouped.isEmpty else {
                continue
            }
            let shape = "\(key.parameterTypes.count)#\(key.isSuspend)"
            if let overrideDepth = overrideDepthByShape[shape],
               grouped.allSatisfy({ $0.depth > overrideDepth })
            {
                continue
            }
            let minDepth = grouped.map(\.depth).min() ?? 0
            let mostSpecificAtDepth = grouped.filter { $0.depth == minDepth }
            let classBacked = mostSpecificAtDepth.filter { candidate in
                guard let ownerSymbol = sema.symbols.symbol(candidate.owner) else {
                    return false
                }
                return ownerSymbol.kind == .class || ownerSymbol.kind == .enumClass || ownerSymbol.kind == .object
            }
            let winners = classBacked.isEmpty ? mostSpecificAtDepth : classBacked
            candidates.append(contentsOf: winners.map(\.symbol))
        }
        return candidates
    }

    /// When `receiver.InnerClassName(...)` is called, look up the inner class
    /// nested inside the receiver's nominal type and return its constructor(s).
    func collectInnerClassConstructorCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let receiverNominal = nominalSymbol(of: receiverType, types: sema.types),
              let receiverSymbol = sema.symbols.symbol(receiverNominal)
        else {
            return []
        }
        // Look for a nested class with the given name whose symbol has the innerClass flag.
        let nestedFQName = receiverSymbol.fqName + [calleeName]
        for candidate in sema.symbols.lookupAll(fqName: nestedFQName) {
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .class,
                  sym.flags.contains(.innerClass)
            else {
                continue
            }
            // Found the inner class – collect its constructors.
            let initName = interner.intern("<init>")
            let ctorFQName = nestedFQName + [initName]
            return sema.symbols.lookupAll(fqName: ctorFQName).filter { ctorID in
                guard let ctorSym = sema.symbols.symbol(ctorID),
                      ctorSym.kind == .constructor else { return false }
                return true
            }
        }
        return []
    }

    /// Look up a member property (or field) named `calleeName` on the receiver's
    /// nominal type, walking the supertype chain. Returns the symbol and its type
    /// if found, or `nil` otherwise.
    func lookupMemberProperty(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols)
        guard !nominalRoots.isEmpty else {
            return nil
        }
        var ownerQueue: [SymbolID] = nominalRoots
        var visited: Set<SymbolID> = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visited.insert(owner).inserted else { continue }
            guard let ownerSymbol = sema.symbols.symbol(owner) else { continue }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let sym = sema.symbols.symbol(candidate),
                      sym.kind == .property || sym.kind == .field,
                      let propType = sema.symbols.propertyType(for: candidate)
                else {
                    continue
                }
                return (
                    candidate,
                    resolveMemberPropertyType(
                        propType,
                        receiverType: receiverType,
                        ownerSymbol: owner,
                        sema: sema
                    )
                )
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }

    private func resolveMemberPropertyType(
        _ propertyType: TypeID,
        receiverType: TypeID,
        ownerSymbol: SymbolID,
        sema: SemaModule
    ) -> TypeID {
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiver),
              sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: ownerSymbol)
        else {
            return propertyType
        }

        guard let ownerTypeArgs = sema.types.liftedNominalSupertypeArgs(
            from: classType.classSymbol,
            childArgs: classType.args,
            to: ownerSymbol
        ) else {
            return propertyType
        }

        let ownerTypeParamSymbols = sema.types.nominalTypeParameterSymbols(for: ownerSymbol)
        guard !ownerTypeParamSymbols.isEmpty else {
            return propertyType
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(ownerTypeParamSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (index, typeParamSymbol) in ownerTypeParamSymbols.enumerated() {
            guard index < ownerTypeArgs.count,
                  let typeVar = typeVarBySymbol[typeParamSymbol]
            else {
                continue
            }
            switch ownerTypeArgs[index] {
            case let .invariant(inner), let .out(inner), let .in(inner):
                substitution[typeVar] = inner
            case .star:
                substitution[typeVar] = sema.types.nullableAnyType
            }
        }

        guard !substitution.isEmpty else {
            return propertyType
        }
        return sema.types.substituteTypeParameters(
            in: propertyType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    func enumOwnerSymbol(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2
        else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }
}
