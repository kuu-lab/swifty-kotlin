struct MemberPropertyLookupResult: Sendable {
    let symbol: SymbolID
    let type: TypeID
    let writeSymbol: SymbolID?
}

private struct InheritedMemberPropertyCandidate {
    let symbol: SymbolID
    let owner: SymbolID
    let declaredType: TypeID
}

extension TypeCheckHelpers {
    private struct MemberDispatchKey: Hashable, CustomStringConvertible {
        let name: InternedString
        let extensionReceiverType: TypeID?
        let parameterTypes: [TypeID]
        let methodTypeParameterCount: Int
        let methodUpperBounds: [[TypeID]]
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
                    return replacement.mapTypes { applyNullabilityForTypeCheck($0, types: sema.types) }
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
            return types.make(.classType(ClassType(
                classSymbol: ct.classSymbol,
                args: ct.args,
                enclosingTypeArgs: ct.enclosingTypeArgs,
                nullability: .nullable
            )))
        case let .typeParam(tp):
            return types.make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: .nullable, capture: tp.capture)))
        case let .functionType(ft):
            return types.make(.functionType(FunctionType(contextReceivers: ft.contextReceivers, receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, isCallableReference: ft.isCallableReference, nullability: .nullable)))
        case let .kClassType(kc):
            return types.make(.kClassType(KClassType(argument: kc.argument, nullability: .nullable)))
        case .any, .unit, .nullableUnit, .platformUnit, .nothing:
            let nullable = types.makeNullable(typeID)
            if nullable == typeID {
                return types.isSubtype(types.nullableNothingType, typeID) ? typeID : types.nullableAnyType
            }
            return nullable
        default:
            return types.nullableAnyType
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

    func resolveExplicitTypeArgs(
        _ typeArgRefs: [TypeRefID],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil,
        usageRange: SourceRange? = nil
    ) -> [TypeID] {
        guard !typeArgRefs.isEmpty else { return [] }
        return typeArgRefs.map { typeRefID in
            guard !isExplicitTypeInferencePlaceholder(typeRefID, ast: ast, interner: interner) else {
                // Keep the argument's position while leaving its type variable to normal call inference.
                return TypeID.invalid
            }
            return resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, usageRange: usageRange)
        }
    }

    func isExplicitTypeInferencePlaceholder(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .named(path, args, nullable) = ast.arena.typeRef(typeRefID),
              path.count == 1,
              args.isEmpty,
              !nullable
        else {
            return false
        }
        return interner.resolve(path[0]) == "_"
    }

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
        case .unit, .nullableUnit, .platformUnit:
            return types.unitClassSymbol
        case let .classType(classType):
            return classType.classSymbol
        case let .intersection(parts):
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

    func allNominalSymbols(
        of type: TypeID,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner? = nil
    ) -> [SymbolID] {
        var visited = Set<SymbolID>()
        return allNominalSymbolsImpl(
            of: type, types: types, symbols: symbols, interner: interner, visited: &visited
        )
    }

    private func allNominalSymbolsImpl(
        of type: TypeID,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner?,
        visited: inout Set<SymbolID>
    ) -> [SymbolID] {
        switch types.kind(of: type) {
        case .unit, .nullableUnit, .platformUnit:
            return types.unitClassSymbol.map { [$0] } ?? []
        case .any:
            // `Any` and `Any?` are canonical builtin types without a classType
            // wrapper, but `toString`/`hashCode`/`equals` are their members.
            // Other builtin kinds deliberately stay rootless here: mapping
            // e.g. `.stringStruct` to `kotlin.String` would also expose the
            // whole CharSequence member surface and rebind existing calls.
            return types.anyClassSymbol.map { [$0] } ?? []
        case let .classType(classType):
            return [classType.classSymbol]
        case let .functionType(functionType):
            return functionType.isCallableReference
                ? types.kFunctionInterfaceSymbol.map { [$0] } ?? []
                : []
        case let .primitive(primitive, _):
            // Primitive values use dedicated TypeIDs, but their synthetic class
            // symbols carry the compiler-owned Comparable conformance and source
            // member surface needed for ordinary member lookup.
            // `kotlin.UInt`/`kotlin.ULong`/`kotlin.UByte`/`kotlin.UShort` are
            // shared with the bundled constructor helpers (`fun UInt(data: Int)`);
            // an imported-library index can materialize the function ahead of the
            // class, so resolve the nominal symbol explicitly (KUU-3143).
            guard let interner,
                  let primitiveSymbol = symbols.lookupNominal(fqName: [
                interner.intern("kotlin"),
                interner.intern(primitive.kotlinName)
            ]) else {
                return []
            }
            return [primitiveSymbol]
        case .kClassType:
            if let kClassSymbol = types.kClassInterfaceSymbol {
                return [kClassSymbol]
            }
            return []
        case let .intersection(parts):
            return parts.flatMap {
                allNominalSymbolsImpl(
                    of: $0, types: types, symbols: symbols, interner: interner, visited: &visited
                )
            }
        case let .typeParam(typeParam):
            if let capture = typeParam.capture {
                return allNominalSymbolsImpl(
                    of: capture.upper, types: types, symbols: symbols, interner: interner, visited: &visited
                )
            }
            // Guard against cycles (e.g. T : U, U : T).
            guard visited.insert(typeParam.symbol).inserted else { return [] }
            let bounds = symbols.typeParameterUpperBounds(for: typeParam.symbol)
            if bounds.isEmpty {
                // A type parameter always has `Any?` as its implicit upper
                // bound, so its members remain callable when no bound was
                // recorded (e.g. unbounded `T` declarations).
                return types.anyClassSymbol.map { [$0] } ?? []
            }
            return bounds.flatMap {
                allNominalSymbolsImpl(
                    of: $0, types: types, symbols: symbols, interner: interner, visited: &visited
                )
            }
        default:
            return []
        }
    }

    private func actualImplementationNominalSymbols(
        of receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard case let .classType(classType) = sema.types.kind(of: receiverType),
              let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return []
        }

        let aliasID: SymbolID?
        if receiverSymbol.kind == .typeAlias {
            aliasID = receiverSymbol.id
        } else if receiverSymbol.flags.contains(.expectDeclaration),
                  let actualID = sema.symbols.actualSymbol(for: receiverSymbol.id),
                  let actualSymbol = sema.symbols.symbol(actualID)
        {
            if actualSymbol.kind == .class {
                return [actualID]
            }
            aliasID = actualSymbol.kind == .typeAlias ? actualID : nil
        } else {
            aliasID = nil
        }
        guard let aliasID,
              let expandedType = expandTypeAlias(
                  aliasID,
                  typeArgs: classType.args,
                  sema: sema,
                  visited: [],
                  depth: 0
              )
        else {
            return []
        }

        return allNominalSymbols(
            of: expandedType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner
        )
    }

    func collectMemberFunctionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        allowedOwnerSymbols: Set<SymbolID>? = nil,
        includeUnattachedPackageExtensions: Bool = false,
        interner: StringInterner
    ) -> [SymbolID] {
        // Super lookup filters implementations, but defaults still belong to
        // the receiver's inherited callable scope. Populate it even on a cold
        // lookup so optional varargs cannot bypass the super-call prohibition.
        if allowedOwnerSymbols != nil {
            _ = collectMemberFunctionCandidates(
                named: calleeName, receiverType: receiverType, sema: sema,
                includeUnattachedPackageExtensions: includeUnattachedPackageExtensions,
                interner: interner
            )
        }
        let nominalRoots = allNominalSymbols(
            of: receiverType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner
        ) + actualImplementationNominalSymbols(
            of: receiverType,
            sema: sema,
            interner: interner
        )

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

        // `toString`/`hashCode`/`equals` are callable on every Kotlin receiver
        // (they are members of `Any?`). Receivers whose nominal roots cannot
        // reach `kotlin.Any` through supertype edges — builtin-disguised types
        // or synthetic primitive shells whose only edge is `Comparable` —
        // still expose them, so keep `kotlin.Any` as the deepest owner.
        if let anyClassSymbol = sema.types.anyClassSymbol,
           !visitedOwners.contains(anyClassSymbol),
           allowedOwnerSymbols?.contains(anyClassSymbol) ?? true
        {
            let fallbackDepth = (ownersInLookupOrder.map(\.depth).max() ?? -1) + 1
            ownersInLookupOrder.append((anyClassSymbol, fallbackDepth))
        }

        var candidatesByKey: [MemberDispatchKey: [(symbol: SymbolID, owner: SymbolID, depth: Int)]] = [:]
        var keyOrder: [MemberDispatchKey] = []
        var methodParametersByKey: [MemberDispatchKey: [SymbolID]] = [:]
        var seenCandidates: Set<SymbolID> = []

        func dispatchTypes(
            _ declaredTypes: [TypeID],
            owner: SymbolID,
            from receiver: TypeID? = nil
        ) -> [TypeID] {
            let nonNullReceiver = sema.types.makeNonNullable(receiver ?? receiverType)
            guard case let .classType(classType) = sema.types.kind(of: nonNullReceiver),
                  sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: owner),
                  let ownerTypeArgs = sema.types.liftedNominalSupertypeArgs(
                      from: classType,
                      to: owner
                  )
            else {
                return declaredTypes
            }

            let ownerTypeParamSymbols = sema.types.allTypeParameterSymbols(for: owner)
            guard !ownerTypeParamSymbols.isEmpty else {
                return declaredTypes
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
                return declaredTypes
            }
            return declaredTypes.map {
                sema.types.substituteTypeParameters(
                    in: $0,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
        }

        func mostSpecificIntersectionReturnCandidates(
            _ candidates: [(symbol: SymbolID, owner: SymbolID, depth: Int)],
            alignedMethodParameters: [SymbolID]
        ) -> [(symbol: SymbolID, owner: SymbolID, depth: Int)] {
            // Type parameters expose members through the full upper-bound intersection,
            // so use its parts just like for a narrowed intersection receiver.
            let intersectionParts: [TypeID]
            switch sema.types.kind(of: receiverType) {
            case let .intersection(parts):
                intersectionParts = parts
            case let .typeParam(typeParameter):
                let upperBounds = typeParameter.capture.map { [$0.upper] }
                    ?? sema.symbols.typeParameterUpperBounds(for: typeParameter.symbol)
                let parts = upperBounds.flatMap { bound -> [TypeID] in
                    if case let .intersection(nested) = sema.types.kind(of: bound) {
                        return nested
                    }
                    return [bound]
                }
                guard parts.count > 1 else {
                    return candidates
                }
                intersectionParts = parts
            default:
                return candidates
            }
            guard candidates.count > 1 else { return candidates }

            let returnTypes: [(symbol: SymbolID, type: TypeID)] = candidates.compactMap { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate.symbol) else {
                    return nil
                }
                let matchingParts = intersectionParts.filter {
                    allNominalSymbols(of: $0, types: sema.types, symbols: sema.symbols, interner: interner)
                        .contains(candidate.owner)
                }
                guard matchingParts.count == 1,
                      let specializedReturnType = dispatchTypes(
                          [signature.returnType], owner: candidate.owner, from: matchingParts[0]
                      ).first
                else {
                    return nil
                }
                let methodParameters = Array(
                    signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
                )
                guard methodParameters.count == alignedMethodParameters.count else {
                    return nil
                }
                let alignedReturnType = alphaAlignedMethodType(
                    specializedReturnType,
                    sourceParameters: methodParameters,
                    targetParameters: alignedMethodParameters,
                    types: sema.types
                )
                return (candidate.symbol, alignedReturnType)
            }
            guard returnTypes.count == candidates.count else {
                return candidates
            }

            // Intersection members with the same parameter signature are ordered by
            // covariant return type, so a String-returning member beats an Any?-returning one.
            let lessSpecificSymbols = Set(returnTypes.compactMap { candidate -> SymbolID? in
                let hasMoreSpecificReturn = returnTypes.contains { other in
                    other.symbol != candidate.symbol
                        && sema.types.isSubtype(other.type, candidate.type)
                        && !sema.types.isSubtype(candidate.type, other.type)
                }
                return hasMoreSpecificReturn ? candidate.symbol : nil
            })
            let filtered = candidates.filter { !lessSpecificSymbols.contains($0.symbol) }
            return filtered.isEmpty ? candidates : filtered
        }

        func appendCandidates(
            owner: SymbolID,
            ownerFQName: [InternedString],
            depth: Int,
            requireReceiverSubtype: Bool
        ) {
            let memberFQName = ownerFQName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let signatureReceiverType = signature.receiverType
                else {
                    continue
                }
                // Kotlin member scope: a `private` member is not inherited, so
                // it is only a member candidate on the nominal that declares
                // it (depth 0). An inherited private member must not win the
                // receiver over an outer `this` that owns the same name — e.g.
                // a private method of the superclass called inside
                // `object : Super()` targets the enclosing instance
                // (KUU-3212).
                if symbol.visibility == .private, depth > 0 {
                    continue
                }
                let parentMatchesOwner = sema.symbols.parentSymbol(for: candidate) == owner
                let isUnattachedPackageExtension = includeUnattachedPackageExtensions
                    && sema.symbols.parentSymbol(for: candidate) == nil
                    && sema.symbols.symbol(owner)?.kind == .package
                guard parentMatchesOwner || isUnattachedPackageExtension else {
                    continue
                }
                guard seenCandidates.insert(candidate).inserted else {
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
                let methodParameters = Array(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount))
                let extensionReceiverType: TypeID? = if sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil {
                    nil
                } else {
                    dispatchTypes([signatureReceiverType], owner: owner).first
                }
                let parameterTypes = dispatchTypes(signature.parameterTypes, owner: owner)
                let upperBounds = methodTypeParameterBounds(signature, types: sema.types).map {
                    dispatchTypes($0, owner: owner)
                }
                var key = MemberDispatchKey(
                    name: calleeName,
                    extensionReceiverType: extensionReceiverType,
                    parameterTypes: parameterTypes,
                    methodTypeParameterCount: methodParameters.count,
                    methodUpperBounds: upperBounds,
                    isSuspend: signature.isSuspend
                )
                if !methodParameters.isEmpty, let alignedKey = keyOrder.first(where: { existing in
                    guard existing.isSuspend == signature.isSuspend,
                          existing.methodTypeParameterCount == methodParameters.count,
                          let targetParameters = methodParametersByKey[existing]
                    else { return false }
                    func aligned(_ type: TypeID) -> TypeID {
                        alphaAlignedMethodType(type, sourceParameters: methodParameters,
                                               targetParameters: targetParameters, types: sema.types)
                    }
                    let extensionReceiverMatches: Bool
                    if let extensionReceiverType, let existingReceiverType = existing.extensionReceiverType {
                        extensionReceiverMatches = methodIdentityParameterTypesMatch(
                            candidateParameterTypes: [existingReceiverType],
                            interfaceParameterTypes: [aligned(extensionReceiverType)],
                            types: sema.types
                        )
                    } else {
                        extensionReceiverMatches = extensionReceiverType == nil && existing.extensionReceiverType == nil
                    }
                    guard extensionReceiverMatches else { return false }
                    return methodIdentityParameterTypesMatch(candidateParameterTypes: existing.parameterTypes,
                                                             interfaceParameterTypes: parameterTypes.map(aligned), types: sema.types)
                        && methodUpperBoundSetsMatch(upperBounds.map { $0.map(aligned) }, existing.methodUpperBounds, types: sema.types)
                }) {
                    key = alignedKey
                }
                if candidatesByKey[key] == nil {
                    keyOrder.append(key)
                    methodParametersByKey[key] = methodParameters
                }
                candidatesByKey[key, default: []].append((candidate, owner, depth))
            }
        }

        let receiverKind = sema.types.kind(of: receiverType)
        if case .primitive = receiverKind {
            // Primitive receivers may also have a nominal compatibility symbol (for
            // example the compiler-owned Comparable conformance). Probe the synthetic
            // stdlib packages as well so extension overloads remain visible.
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
        // Overrides hide inherited declarations only for the same dispatch key;
        // arity alone would drop unrelated overloads with the same parameter count.
        var overrideDepthByKey: [MemberDispatchKey: Int] = [:]
        for key in keyOrder {
            guard let grouped = candidatesByKey[key] else { continue }
            for candidate in grouped {
                guard sema.symbols.symbol(candidate.symbol)?.flags.contains(.overrideMember) == true,
                      sema.symbols.functionSignature(for: candidate.symbol) != nil
                else {
                    continue
                }
                overrideDepthByKey[key] = min(overrideDepthByKey[key] ?? candidate.depth, candidate.depth)
            }
        }
        for key in keyOrder {
            guard let grouped = candidatesByKey[key], !grouped.isEmpty else {
                continue
            }
            if let overrideDepth = overrideDepthByKey[key],
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
            let winners = mostSpecificIntersectionReturnCandidates(
                classBacked.isEmpty ? mostSpecificAtDepth : classBacked,
                alignedMethodParameters: methodParametersByKey[key] ?? []
            )
            // A superclass can implement an interface without a declaration in
            // the leaf class. Keep its concrete candidate, but project the
            // interface defaults into this receiver's use-site scope only.
            if allowedOwnerSymbols == nil,
               case .classType = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
               winners.count == 1, let implementation = classBacked.first,
               implementation.depth > 0,
               sema.symbols.symbol(implementation.symbol)?.flags.contains(.abstractType) == false,
               sema.symbols.memberExtensionOwnerSymbol(for: implementation.symbol) == nil,
               let implementationSignature = sema.symbols.functionSignature(for: implementation.symbol),
               !implementationSignature.valueParameterHasDefaultValues.contains(true)
            {
                let defaultOwners = Set(grouped.compactMap { candidate -> SymbolID? in
                    guard sema.symbols.symbol(candidate.owner)?.kind == .interface,
                          sema.symbols.memberExtensionOwnerSymbol(for: candidate.symbol) == nil,
                          let signature = sema.symbols.functionSignature(for: candidate.symbol),
                          signature.valueParameterHasDefaultValues.contains(true),
                          OverloadResolver.normalizeFlags(signature.valueParameterIsVararg, count: key.parameterTypes.count)
                            == OverloadResolver.normalizeFlags(implementationSignature.valueParameterIsVararg, count: key.parameterTypes.count)
                    else { return nil }
                    return sema.symbols.overrideDefaultsBaseSymbol(for: candidate.symbol) ?? candidate.symbol
                })
                sema.symbols.setInheritedDefaultsOwner(
                    defaultOwners.count == 1 ? defaultOwners.first : nil,
                    for: implementation.symbol,
                    receiver: sema.types.makeNonNullable(receiverType)
                )
            }
            candidates.append(contentsOf: winners.map(\.symbol))
        }
        return candidates
    }

    func collectInnerClassConstructorCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        matchingInnerClass: SymbolID? = nil
    ) -> [SymbolID] {
        guard let receiverNominal = nominalSymbol(of: receiverType, types: sema.types) else {
            return []
        }
        // Inner classes are inherited members, so walk the supertype chain too.
        var ownerQueue: [SymbolID] = [receiverNominal]
        var visited: Set<SymbolID> = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let nestedFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: nestedFQName) {
                guard let sym = sema.symbols.symbol(candidate),
                      sym.kind == .class,
                      sym.flags.contains(.innerClass),
                      matchingInnerClass == nil || matchingInnerClass == candidate
                else {
                    continue
                }
                let initName = interner.intern("<init>")
                let ctorFQName = nestedFQName + [initName]
                return sema.symbols.lookupAll(fqName: ctorFQName).filter { ctorID in
                    guard let ctorSym = sema.symbols.symbol(ctorID),
                          ctorSym.kind == .constructor else { return false }
                    return true
                }
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return []
    }

    func collectInnerClassTypeAliasConstructorCandidates(
        named aliasName: InternedString,
        receiverType: TypeID,
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext,
        interner: StringInterner
    ) -> (candidates: [SymbolID], typeAliasConstructor: TypeAliasConstructorContext)? {
        let sema = ctx.sema
        var aliases = ctx.cachedScopeLookup(aliasName).filter {
            ctx.cachedSymbol($0)?.kind == .typeAlias
        }
        for candidate in ctx.scope.lookupClassifier(aliasName, matching: {
            ctx.cachedSymbol($0)?.kind == .typeAlias
        }) where !aliases.contains(candidate) {
            aliases.append(candidate)
        }
        for aliasSymbol in ctx.filterByVisibility(aliases).visible {
            let parameters = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
            let typeArgs: [TypeArg] = parameters.enumerated().map { index, parameter in
                let argument = explicitTypeArgs.indices.contains(index) && explicitTypeArgs[index] != TypeID.invalid
                    ? explicitTypeArgs[index]
                    : sema.types.make(.typeParam(TypeParamType(symbol: parameter, nullability: .nonNull)))
                return .invariant(argument)
            }
            guard let expanded = expandTypeAlias(
                aliasSymbol,
                typeArgs: typeArgs,
                sema: sema,
                visited: [],
                depth: 0,
                diagnostics: sema.diagnostics
            ),
               case let .classType(classType) = sema.types.kind(of: expanded)
            else {
                continue
            }
            let classSymbol = sema.symbols.actualSymbol(for: classType.classSymbol) ?? classType.classSymbol
            guard sema.symbols.symbol(classSymbol)?.flags.contains(.innerClass) == true else {
                continue
            }
            // The alias's expanded type may carry the enclosing inner-class
            // arguments either in `enclosingTypeArgs` (type-check resolver)
            // or flattened into `args` (header-collection resolver).
            // `typeAliasConstructorSignature` reads only `args`, so keep the
            // combined argument list there (KUU-3840).
            let constructorType = sema.types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: sema.types.allTypeArguments(for: classType),
                nullability: .nonNull
            )))
            guard let outerReceiverType = innerClassOuterReceiverType(
                for: constructorType,
                receiverType: receiverType,
                sema: sema
            ) else {
                continue
            }
            let className = sema.symbols.symbol(classSymbol)?.name ?? aliasName
            let constructors = collectInnerClassConstructorCandidates(
                named: className,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                matchingInnerClass: classSymbol
            )
            guard !constructors.isEmpty else {
                continue
            }
            return (
                constructors,
                TypeAliasConstructorContext(
                    typeParameterSymbols: parameters,
                    expandedType: constructorType,
                    typeAliasSymbol: aliasSymbol,
                    innerOuterReceiverType: outerReceiverType,
                    outerTypeParameterSymbols: innerTypeAliasOuterTypeParameters(
                        of: aliasSymbol,
                        sema: sema
                    )
                )
            )
        }
        return nil
    }

    /// The inner class type stores only its own type arguments.
    func innerTypeAliasOuterTypeParameters(of aliasSymbol: SymbolID, sema: SemaModule) -> [SymbolID] {
        let parameters = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
        guard !parameters.isEmpty else { return [] }
        let typeArgs = parameters.map { parameter in
            TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(
                symbol: parameter,
                nullability: .nonNull
            ))))
        }
        guard let expanded = expandTypeAlias(
            aliasSymbol,
            typeArgs: typeArgs,
            sema: sema,
            visited: [],
            depth: 0
        ), case let .classType(innerClass) = sema.types.kind(of: expanded) else {
            return []
        }
        // Enclosing arguments lead the combined argument list. Alias
        // parameters that appear there fill the outer class's parameters;
        // the remainder belong to the inner class itself. The underlying
        // type may store them flat in `args` when it was recorded before
        // enclosing-parameter metadata was available, so classify by
        // position rather than by which field holds them.
        let enclosingCount = sema.types.enclosingTypeParameterSymbols(for: innerClass.classSymbol).count
        let enclosingArguments = Array(sema.types.allTypeArguments(for: innerClass).prefix(enclosingCount))
        return parameters.filter { parameter in
            enclosingArguments.contains { argument in
                switch argument {
                case let .invariant(type), let .out(type), let .in(type):
                    sema.types.typeContainsTypeParam(type, symbol: parameter)
                case .star:
                    false
                }
            }
        }
    }

    func innerClassOuterReceiverType(
        for innerClassType: TypeID,
        receiverType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        guard case let .classType(innerClass) = sema.types.kind(of: innerClassType),
              sema.symbols.symbol(innerClass.classSymbol)?.flags.contains(.innerClass) == true,
              let outerOwner = sema.symbols.parentSymbol(for: innerClass.classSymbol),
              let receiverSymbol = nominalSymbol(of: receiverType, types: sema.types),
              sema.types.isNominalSubtypeSymbol(receiverSymbol, of: outerOwner)
        else {
            return nil
        }
        return sema.types.makeNonNullable(receiverType)
    }

    func lookupMemberProperty(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols)
        guard !nominalRoots.isEmpty else {
            return nil
        }
        // Kotlin member scope: a `private` member is not inherited, so it is
        // only reachable on the nominal that declares it. Skipping inherited
        // private members lets implicit-receiver resolution continue outward
        // to an enclosing `this` that legitimately owns them — e.g. a
        // `private val` of the superclass read inside `object : Super()`
        // binds the enclosing instance, not the object's own field (KUU-3212).
        let nominalRootSet = Set(nominalRoots)
        var ownerQueue: [SymbolID] = nominalRoots
        var visited: Set<SymbolID> = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visited.insert(owner).inserted else { continue }
            guard let ownerSymbol = sema.symbols.symbol(owner) else { continue }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let sym = sema.symbols.symbol(candidate),
                      // Expect and actual members share an FQName, so retain
                      // only the declaration owned by the nominal currently
                      // being searched.
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sym.kind == .property || sym.kind == .field,
                      // A `.static` member (the enum class's synthetic
                      // `entries` EnumEntries stub) is a classifier-scope
                      // member, not an instance member: it is invisible to an
                      // instance-typed receiver — the same rule that keeps
                      // companion members unreachable through `c.x`. It must
                      // not shadow an inherited interface member of the same
                      // name, which BFS finds on a later supertype owner
                      // (KUU-3891).
                      !sym.flags.contains(.static),
                      // A member extension shares the owner's member FQName
                      // but is not part of the receiver's member scope:
                      // `r.name` supplies only one receiver, while the
                      // extension needs both the dispatch instance and a
                      // matching extension receiver. Member extensions
                      // resolve through the implicit-receiver machinery
                      // instead (KUU-3746).
                      sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                      sym.visibility != .private || nominalRootSet.contains(owner),
                      let propType = sema.symbols.propertyType(for: candidate)
                else {
                    continue
                }
                return (
                    candidate,
                    resolveMemberPropertyType(
                        propertyReadType(for: candidate, declaredType: propType, sema: sema) ?? propType,
                        receiverType: receiverType,
                        ownerSymbol: owner,
                        sema: sema
                    )
                )
            }
            ownerQueue.append(contentsOf: memberPropertyLookupSupertypes(of: owner, sema: sema))
        }
        return nil
    }

    /// A `private` nested classifier declared on a supertype is likewise not
    /// inherited — it never enters the member scope's candidate set — but an
    /// unqualified reference must still report it as inaccessible rather than
    /// unresolved, matching kotlinc (KUU-3798). Probe the implicit receiver
    /// tower's nominal hierarchies and every nominal enclosing the use site
    /// for a same-named `private` classifier for the unresolved fallbacks.
    /// Nested classifiers inherit through the superclass chain only
    /// (KUU-3637), so interfaces end the walk.
    func inaccessiblePrivateNestedClassifier(
        named name: InternedString,
        ctx: TypeInferenceContext
    ) -> SemanticSymbol? {
        let sema = ctx.sema
        let classifierKinds: Set<SymbolKind> = [
            .class, .interface, .object, .enumClass, .annotationClass, .typeAlias,
        ]
        var roots = ctx.implicitReceiverMemberLookupEntries().flatMap { entry in
            allNominalSymbols(of: entry.type, types: sema.types, symbols: sema.symbols)
        }
        var ancestor = ctx.enclosingClassSymbol
        var seenAncestors: Set<SymbolID> = []
        while let current = ancestor, seenAncestors.insert(current).inserted {
            roots.append(current)
            ancestor = sema.symbols.parentSymbol(for: current)
        }
        var visited: Set<SymbolID> = []
        var index = 0
        while index < roots.count {
            let owner = roots[index]
            index += 1
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            for candidate in sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]) {
                guard let member = sema.symbols.symbol(candidate),
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      member.visibility == .private,
                      classifierKinds.contains(member.kind),
                      !ctx.visibilityChecker.isAccessible(
                          member,
                          fromFile: ctx.currentFileID,
                          enclosingClass: ctx.enclosingClassSymbol
                      )
                else {
                    continue
                }
                return member
            }
            roots.append(contentsOf: sema.symbols.directSupertypes(for: owner).filter {
                sema.symbols.symbol($0)?.kind == .class
            })
        }
        return nil
    }

    /// Member-scope lookup keeps `private` members out of the inherited
    /// candidate set because they are not inherited, but a member access
    /// must still report them as inaccessible rather than unresolved
    /// (KUU-3751). Find a same-named `private` member anywhere in the
    /// receiver's nominal hierarchy for the unresolved-member fallback.
    func privateMemberSymbolInHierarchy(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule
    ) -> SemanticSymbol? {
        var ownerQueue = allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols)
        var visited: Set<SymbolID> = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let member = sema.symbols.symbol(candidate),
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      member.visibility == .private,
                      member.kind == .function || member.kind == .property || member.kind == .field
                else {
                    continue
                }
                return member
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }

    /// Inherited `private` members are not members of an implicit receiver
    /// (they are not inherited), so an unqualified reference reports them as
    /// unresolved where kotlinc reports an inaccessible member (KUU-3766).
    /// Probe the implicit receiver tower — which includes companion objects —
    /// for a same-named `private` member so the unresolved-function and
    /// unresolved-reference fallbacks can emit the matching visibility
    /// diagnostic instead.
    func inaccessiblePrivateImplicitReceiverMember(
        named name: InternedString,
        ctx: TypeInferenceContext
    ) -> SemanticSymbol? {
        var probeTypes = ctx.implicitReceiverMemberLookupEntries().map(\.type)
        // A class's companion object contributes its inherited members to the
        // unqualified scope, but is not itself a receiver-tower entry. Probe
        // the companion of every receiver root and of each nominal enclosing
        // the use site: a companion's member scope also reaches lexically
        // nested classes.
        var companionOwners = ctx.implicitReceiverMemberLookupEntries().flatMap { entry in
            allNominalSymbols(of: entry.type, types: ctx.sema.types, symbols: ctx.sema.symbols)
        }
        var ancestor = ctx.enclosingClassSymbol
        var seenAncestors: Set<SymbolID> = []
        while let current = ancestor, seenAncestors.insert(current).inserted {
            companionOwners.append(current)
            ancestor = ctx.sema.symbols.parentSymbol(for: current)
        }
        for owner in companionOwners {
            guard let companion = ctx.sema.symbols.companionObjectSymbol(for: owner) else {
                continue
            }
            probeTypes.append(ctx.sema.types.make(.classType(ClassType(
                classSymbol: companion, args: [], nullability: .nonNull
            ))))
        }
        for type in probeTypes {
            guard let member = privateMemberSymbolInHierarchy(
                named: name, receiverType: type, sema: ctx.sema
            ), !ctx.visibilityChecker.isAccessible(
                member,
                fromFile: ctx.currentFileID,
                enclosingClass: ctx.enclosingClassSymbol
            )
            else {
                continue
            }
            return member
        }
        return nil
    }

    /// The companion scope receiver types a class-name `Owner.member` can
    /// reach, in the read path's order: the hidden `$CompanionBlocks` object
    /// first, then the source `companion object`. A class with both returns
    /// both so a member fallback can probe each scope the read path visits.
    func companionScopeProbeTypes(
        for ownerNominalSymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> [TypeID] {
        let sema = ctx.sema
        let actualOwner = sema.symbols.actualSymbol(for: ownerNominalSymbol)
        let blockObject = sema.symbols.companionBlockObjectSymbol(
            for: ownerNominalSymbol, interner: ctx.interner
        ) ?? actualOwner.flatMap {
            sema.symbols.companionBlockObjectSymbol(for: $0, interner: ctx.interner)
        }
        let sourceCompanion = sema.symbols.companionObjectSymbol(for: ownerNominalSymbol)
            ?? actualOwner.flatMap { sema.symbols.companionObjectSymbol(for: $0) }
        return [blockObject, sourceCompanion].compactMap { $0 }.map { companion in
            sema.symbols.propertyType(for: companion) ?? sema.types.make(.classType(ClassType(
                classSymbol: companion, args: [], nullability: .nonNull
            )))
        }
    }

    /// The companion object type through which a class-name receiver's
    /// `Owner.member` shorthand resolves its member scope — including the
    /// platform-module `$CompanionBlocks` object and expect/actual pairing.
    func companionScopeType(
        for ownerNominalSymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let companion = sema.symbols.companionBlockObjectSymbol(
            for: ownerNominalSymbol,
            interner: ctx.interner
        ) ?? sema.symbols.companionObjectSymbol(for: ownerNominalSymbol)
            ?? sema.symbols.actualSymbol(for: ownerNominalSymbol).flatMap {
                sema.symbols.companionBlockObjectSymbol(for: $0, interner: ctx.interner)
                    ?? sema.symbols.companionObjectSymbol(for: $0)
            }
        guard let companion else { return nil }
        return sema.symbols.propertyType(for: companion)
            ?? sema.types.make(.classType(ClassType(
                classSymbol: companion, args: [], nullability: .nonNull
            )))
    }

    /// Inherited `private` members are filtered out of qualified member
    /// lookup (they are not inherited), so `receiver.member` and the
    /// `Owner.member` companion shorthand report them as unresolved where
    /// kotlinc reports an inaccessible member (KUU-3762). Probe each
    /// receiver surface for a same-named `private` member so the
    /// unresolved-member fallbacks can emit the matching visibility
    /// diagnostic instead.
    func inaccessiblePrivateQualifiedMember(
        named calleeName: InternedString,
        probeReceiverTypes: [TypeID],
        ctx: TypeInferenceContext
    ) -> SemanticSymbol? {
        for probeType in probeReceiverTypes {
            guard let member = privateMemberSymbolInHierarchy(
                named: calleeName,
                receiverType: probeType,
                sema: ctx.sema
            ), !ctx.visibilityChecker.isAccessible(
                member,
                fromFile: ctx.currentFileID,
                enclosingClass: ctx.enclosingClassSymbol
            )
            else {
                continue
            }
            return member
        }
        return nil
    }

    /// A paired expect class keeps its semantic supertype edge, but members
    /// declared only by the actual class still participate in platform-side
    /// member lookup. Visit that implementation before the expect class's own
    /// supertypes, matching the actual class's runtime member surface.
    private func memberPropertyLookupSupertypes(of owner: SymbolID, sema: SemaModule) -> [SymbolID] {
        var supertypes: [SymbolID] = []
        if let expectSymbol = sema.symbols.symbol(owner),
           expectSymbol.kind == .class,
           expectSymbol.flags.contains(.expectDeclaration),
           let actualSymbolID = sema.symbols.actualSymbol(for: owner),
           sema.symbols.symbol(actualSymbolID)?.kind == .class
        {
            supertypes.append(actualSymbolID)
        }
        supertypes.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        return supertypes
    }

    /// Resolve the effective setter for an inherited property intersection
    /// without changing the symbol selected for ordinary reads.
    func lookupMemberPropertyForWrite(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule
    ) -> MemberPropertyLookupResult? {
        guard let readResult = lookupMemberProperty(
            named: calleeName, receiverType: receiverType, sema: sema
        ) else {
            return nil
        }

        let nominalRoots = allNominalSymbols(of: receiverType, types: sema.types, symbols: sema.symbols)
        // Same member-scope rule as `lookupMemberProperty`: inherited `private`
        // members are not writable members of this receiver (KUU-3212).
        let nominalRootSet = Set(nominalRoots)
        var ownerQueue = nominalRoots
        var visited: Set<SymbolID> = []
        var candidates: [InheritedMemberPropertyCandidate] = []
        while !ownerQueue.isEmpty {
            let owner = ownerQueue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let property = sema.symbols.symbol(candidate),
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      property.kind == .property || property.kind == .field,
                      // Same member-scope rule as `lookupMemberProperty`:
                      // `.static` members are classifier-scope, never
                      // writable through an instance receiver (KUU-3891).
                      !property.flags.contains(.static),
                      // Same member-scope rule as `lookupMemberProperty`:
                      // a member extension is not a writable member of the
                      // receiver — its setter resolves through the implicit
                      // receiver member-extension machinery (KUU-3746).
                      sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                      property.visibility != .private || nominalRootSet.contains(owner),
                      let declaredType = sema.symbols.propertyType(for: candidate)
                else {
                    continue
                }
                candidates.append(InheritedMemberPropertyCandidate(
                    symbol: candidate,
                    owner: owner,
                    declaredType: resolveMemberPropertyType(
                        declaredType,
                        receiverType: receiverType,
                        ownerSymbol: owner,
                        sema: sema
                    )
                ))
            }
            ownerQueue.append(contentsOf: memberPropertyLookupSupertypes(of: owner, sema: sema))
        }

        // A matched expect/actual property is one contract, not two unrelated
        // inherited declarations. Keep the expect-side type for expect-class
        // receivers: the actual class has distinct type-parameter symbols,
        // which cannot be substituted from the expect receiver type.
        let pairedActualMembers = Set(candidates.compactMap { candidate -> SymbolID? in
            guard sema.symbols.symbol(candidate.symbol)?.flags.contains(.expectDeclaration) == true else {
                return nil
            }
            return sema.symbols.actualSymbol(for: candidate.symbol)
        })
        let logicalCandidates = candidates.filter { candidate in
            guard sema.symbols.symbol(candidate.symbol)?.flags.contains(.actualDeclaration) == true else {
                return true
            }
            return !pairedActualMembers.contains(candidate.symbol)
        }

        // A declaration on a subtype shadows the same member inherited from
        // its ancestors. Keep declarations from unrelated branches so their
        // property and setter contracts can be checked together.
        let effectiveCandidates = logicalCandidates.filter { candidate in
            !logicalCandidates.contains { other in
                other.owner != candidate.owner
                    && sema.types.isNominalSubtypeSymbol(other.owner, of: candidate.owner)
            }
        }
        let mutableCandidates = effectiveCandidates.filter {
            sema.symbols.symbol($0.symbol)?.flags.contains(.mutable) == true
        }
        guard let firstMutable = mutableCandidates.first else {
            return MemberPropertyLookupResult(
                symbol: readResult.symbol, type: readResult.type, writeSymbol: nil
            )
        }

        // A fake override can expose a setter only when its writable type is
        // valid for every inherited read contract. Multiple var declarations
        // must agree on that writable type; otherwise assignment is ambiguous.
        let hasCompatibleSetter = mutableCandidates.allSatisfy { candidate in
            sema.types.isSubtype(firstMutable.declaredType, candidate.declaredType)
                && sema.types.isSubtype(candidate.declaredType, firstMutable.declaredType)
        } && effectiveCandidates.allSatisfy { candidate in
            sema.types.isSubtype(firstMutable.declaredType, candidate.declaredType)
        }
        guard hasCompatibleSetter else {
            return MemberPropertyLookupResult(
                symbol: readResult.symbol, type: readResult.type, writeSymbol: nil
            )
        }

        return MemberPropertyLookupResult(
            symbol: readResult.symbol, type: readResult.type, writeSymbol: firstMutable.symbol
        )
    }

    /// Probes a classifier's *static scope*: `.static` members only. Kotlin
    /// keeps them out of the instance member scope (they are unreachable
    /// through `instance.name`) but still exposes them to unqualified
    /// references inside the class body, interleaved into the implicit
    /// receiver tower after that classifier's own `this` receiver (KUU-3891).
    /// Statics are not inherited, so only each nominal's own declarations are
    /// probed; the lexical parent chain is walked because a nested
    /// classifier's scope also surfaces its enclosing nominals' statics (for
    /// example an enum entry's anonymous class body sees `Enum.entries`).
    private func lookupStaticPropertyFromClassifierScope(
        named name: InternedString,
        startingAt nominal: SymbolID,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        var owner: SymbolID? = nominal
        var visited: Set<SymbolID> = []
        while let current = owner, visited.insert(current).inserted {
            owner = sema.symbols.parentSymbol(for: current)
            guard let ownerSymbol = sema.symbols.symbol(current) else {
                continue
            }
            for candidate in sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]) {
                guard let sym = sema.symbols.symbol(candidate),
                      sema.symbols.parentSymbol(for: candidate) == current,
                      sym.kind == .property || sym.kind == .field,
                      sym.flags.contains(.static),
                      sym.visibility != .private,
                      let propType = sema.symbols.propertyType(for: candidate)
                else {
                    continue
                }
                let ownerType = sema.types.make(.classType(ClassType(
                    classSymbol: current,
                    args: [],
                    nullability: .nonNull
                )))
                return (
                    candidate,
                    resolveMemberPropertyType(
                        propertyReadType(for: candidate, declaredType: propType, sema: sema) ?? propType,
                        receiverType: ownerType,
                        ownerSymbol: current,
                        sema: sema
                    )
                )
            }
        }
        return nil
    }

    /// Static-scope member of an enclosing classifier, for implicit-receiver
    /// member lookup: fires only when `receiverType` is a classifier that
    /// lexically encloses the use site, so an extension or `with` receiver
    /// does not import the enclosing class's statics ahead of its own tower
    /// position (KUU-3891).
    func lookupStaticPropertyInClassScope(
        named name: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> (symbol: SymbolID, type: TypeID)? {
        let sema = ctx.sema
        guard let receiverNominal = nominalSymbol(of: receiverType, types: sema.types) else {
            return nil
        }
        var ancestor = ctx.enclosingClassSymbol
        var seenAncestors: Set<SymbolID> = []
        while let current = ancestor, seenAncestors.insert(current).inserted {
            if current == receiverNominal {
                return lookupStaticPropertyFromClassifierScope(
                    named: name, startingAt: receiverNominal, sema: sema
                )
            }
            ancestor = sema.symbols.parentSymbol(for: current)
        }
        return nil
    }

    /// Static-scope member anywhere on the enclosing classifier chain — the
    /// use-site-level counterpart of `lookupStaticPropertyInClassScope` for
    /// paths that have already exhausted the implicit receiver tower
    /// (KUU-3891).
    func lookupStaticPropertyInEnclosingClassScope(
        named name: InternedString,
        ctx: TypeInferenceContext
    ) -> (symbol: SymbolID, type: TypeID)? {
        guard let enclosing = ctx.enclosingClassSymbol else {
            return nil
        }
        return lookupStaticPropertyFromClassifierScope(
            named: name, startingAt: enclosing, sema: ctx.sema
        )
    }

    /// An immutable property with a synthesized getter keeps the declared
    /// property type for its API while its explicit backing field can retain a
    /// more specific initializer type for reads in the same compilation.
    func propertyReadType(
        for property: SymbolID,
        declaredType: TypeID? = nil,
        sema: SemaModule
    ) -> TypeID? {
        guard let propertySymbol = sema.symbols.symbol(property),
              propertySymbol.kind == .property,
              !propertySymbol.flags.contains(.mutable),
              !propertySymbol.flags.contains(.openType),
              !propertySymbol.flags.contains(.abstractType),
              !propertySymbol.flags.contains(.importedLibrary),
              !sema.symbols.propertyHasCustomGetter(for: property),
              let declaredType = declaredType ?? sema.symbols.propertyType(for: property)
        else {
            return declaredType
        }
        guard let backingField = sema.symbols.backingFieldSymbol(for: property),
              let backingFieldType = sema.symbols.propertyType(for: backingField),
              sema.types.isSubtype(backingFieldType, declaredType)
        else {
            return declaredType
        }
        return backingFieldType
    }

    /// The entry field owns the declaration, while the receiver still has the
    /// containing enum's runtime type.
    func lookupEnumEntryMemberProperty(
        named calleeName: InternedString,
        entrySymbol: SymbolID,
        receiverType: TypeID,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        guard let entryInfo = sema.symbols.symbol(entrySymbol),
              entryInfo.kind == .field,
              let enumOwner = sema.symbols.parentSymbol(for: entrySymbol),
              sema.symbols.symbol(enumOwner)?.kind == .enumClass
        else {
            return nil
        }
        for candidate in sema.symbols.lookupAll(fqName: entryInfo.fqName + [calleeName]) {
            guard sema.symbols.parentSymbol(for: candidate) == entrySymbol,
                  let candidateInfo = sema.symbols.symbol(candidate),
                  candidateInfo.kind == .property || candidateInfo.kind == .field,
                  let propertyType = sema.symbols.propertyType(for: candidate)
            else {
                continue
            }
            return (
                candidate,
                resolveMemberPropertyType(
                    propertyType,
                    receiverType: receiverType,
                    ownerSymbol: enumOwner,
                    sema: sema
                )
            )
        }
        return nil
    }

    func resolveMemberPropertyType(
        _ propertyType: TypeID,
        receiverType: TypeID,
        ownerSymbol: SymbolID,
        sema: SemaModule
    ) -> TypeID {
        let nonNullReceiver = nominalReceiverThroughTypeParameterBounds(
            receiverType,
            ownerSymbol: ownerSymbol,
            sema: sema
        )
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiver),
              sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: ownerSymbol)
        else {
            return propertyType
        }

        guard let ownerTypeArgs = sema.types.liftedNominalSupertypeArgs(
            from: classType,
            to: ownerSymbol
        ) else {
            return propertyType
        }

        let ownerTypeParamSymbols = sema.types.allTypeParameterSymbols(for: ownerSymbol)
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
                substitution[typeVar] = sema.types.capturedTypeForStarProjection(
                    parameter: typeParamSymbol,
                    ownerTypeParameters: ownerTypeParamSymbols
                )
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

    /// Walks a (possibly chained) type-parameter receiver such as `H : Holder<C>` to the
    /// declared upper bound that is a nominal subtype of `ownerSymbol`, so owner type
    /// arguments can be substituted into generic member property types.
    private func nominalReceiverThroughTypeParameterBounds(
        _ receiverType: TypeID,
        ownerSymbol: SymbolID,
        sema: SemaModule
    ) -> TypeID {
        // A nominal already conforming to `ownerSymbol` resolves to itself; a
        // type parameter walks its declared bounds to that nominal.
        func nominalSubtypeOfOwner(in start: TypeID) -> TypeID? {
            var current = sema.types.makeNonNullable(
                sema.types.capturedReadableUpperBound(of: start)
            )
            var visited: Set<SymbolID> = []
            while case let .typeParam(parameter) = sema.types.kind(of: current),
                  visited.insert(parameter.symbol).inserted
            {
                var next: TypeID?
                for bound in sema.types.declaredUpperBounds(for: parameter.symbol) {
                    let candidate = sema.types.makeNonNullable(
                        sema.types.capturedReadableUpperBound(of: bound)
                    )
                    switch sema.types.kind(of: candidate) {
                    case let .classType(classType)
                        where sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: ownerSymbol):
                        return candidate
                    case .typeParam:
                        next = next ?? candidate
                    default:
                        continue
                    }
                }
                guard let next else { break }
                current = next
            }
            guard case let .classType(classType) = sema.types.kind(of: current),
                  sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: ownerSymbol)
            else {
                return nil
            }
            return current
        }

        let nonNullReceiver = sema.types.makeNonNullable(
            sema.types.capturedReadableUpperBound(of: receiverType)
        )
        // A smart cast keeps the declared type as one intersection conjunct and
        // the concrete target as another (`Feature<T> & BooleanFeature`). A
        // member declared on the generic conjunct substitutes owner type
        // arguments through the concrete implementation
        // (`BooleanFeature : Feature<Boolean>`) — the read is
        // `Feature<Boolean>.default`, not `T` (KUU-3129).
        if case let .intersection(parts) = sema.types.kind(of: nonNullReceiver) {
            var conjuncts: [(type: TypeID, symbol: SymbolID)] = []
            for part in parts {
                guard let partReceiver = nominalSubtypeOfOwner(in: part),
                      case let .classType(classType) = sema.types.kind(of: partReceiver)
                else {
                    continue
                }
                conjuncts.append((partReceiver, classType.classSymbol))
            }
            // Prefer the most-derived conjunct (`BooleanFeature` over
            // `Feature<T>`): it is a nominal subtype of every other conjunct.
            if let mostDerived = conjuncts.first(where: { conjunct in
                conjuncts.allSatisfy { other in
                    other.symbol == conjunct.symbol
                        || sema.types.isNominalSubtypeSymbol(conjunct.symbol, of: other.symbol)
                }
            }) {
                return mostDerived.type
            }
            // Without a single most-derived conjunct the smart-cast target is
            // still appended after the declared type, so the last qualifying
            // conjunct is the concrete implementation.
            if let lastConjunct = conjuncts.last {
                return lastConjunct.type
            }
            return nonNullReceiver
        }
        return nominalSubtypeOfOwner(in: receiverType) ?? nonNullReceiver
    }
}
