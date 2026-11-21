extension TypeSystem {
    public func isSubtype(_ subtype: TypeID, _ supertype: TypeID) -> Bool {
        attribution?.increment(.subtypeChecks)
        let (subtype, lhs) = normalizedBuiltinDisguisedClassTypeAndKind(subtype)
        let (supertype, rhs) = normalizedBuiltinDisguisedClassTypeAndKind(supertype)
        if subtype == supertype {
            return true
        }

        if case let .typeParam(left) = lhs, case let .typeParam(right) = rhs,
           let capture = left.capture,
           let rightCapture = right.capture,
           capture.isSameProjectedCapture(as: rightCapture)
        {
            return nullabilitySubtype(left.nullability, right.nullability)
        }
        if case let .typeParam(parameter) = rhs, let capture = parameter.capture {
            return nullabilitySubtype(nullability(of: subtype), parameter.nullability)
                && isSubtype(subtype, withNullability(parameter.nullability, for: capture.lower))
        }
        if case let .typeParam(parameter) = lhs, let capture = parameter.capture {
            return isSubtype(withNullability(parameter.nullability, for: capture.upper), supertype)
        }

        if case .nothing(.nonNull) = lhs {
            return true
        }
        if case .nothing(.nullable) = lhs {
            switch rhs {
            case .nullableUnit, .platformUnit:
                return true
            case .error:
                return true
            case let .any(n):
                return nullabilitySubtype(.nullable, n)
            case let .nothing(n):
                return nullabilitySubtype(.nullable, n)
            case let .stringStruct(n):
                return nullabilitySubtype(.nullable, n)
            case let .primitive(_, n):
                return nullabilitySubtype(.nullable, n)
            case let .classType(ct):
                return nullabilitySubtype(.nullable, ct.nullability)
            case let .typeParam(tp):
                return nullabilitySubtype(.nullable, tp.nullability)
            case let .functionType(ft):
                return nullabilitySubtype(.nullable, ft.nullability)
            case let .kClassType(kc):
                return nullabilitySubtype(.nullable, kc.nullability)
            case let .intersection(parts):
                return parts.allSatisfy { isSubtype(subtype, $0) }
            default:
                return false
            }
        }
        if [.unit, .nullableUnit, .platformUnit].contains(lhs),
           [.unit, .nullableUnit, .platformUnit].contains(rhs)
        {
            return nullabilitySubtype(nullability(of: subtype), nullability(of: supertype))
        }
        // Must come before LHS decomposition so that intersection-vs-intersection
        // decomposes the RHS first, allowing each part to then match via LHS rule.
        if case let .intersection(parts) = rhs {
            return parts.allSatisfy { isSubtype(subtype, $0) }
        }
        if case let .intersection(parts) = lhs {
            return parts.contains { isSubtype($0, supertype) }
        }
        if case .error = lhs {
            return true
        }
        if case .error = rhs {
            return true
        }
        if case .any(.nullable) = rhs {
            return true
        }
        if case .any(.platformType) = rhs {
            return true
        }
        if case .any(.nonNull) = rhs {
            switch lhs {
            case .any(.nonNull), .any(.platformType), .unit, .platformUnit, .nothing(.nonNull):
                return true
            case let .stringStruct(nullability):
                return nullabilitySubtype(nullability, .nonNull)
            case let .primitive(_, nullability):
                return nullabilitySubtype(nullability, .nonNull)
            case let .classType(classType):
                return nullabilitySubtype(classType.nullability, .nonNull)
            case let .functionType(functionType):
                return nullabilitySubtype(functionType.nullability, .nonNull)
            case let .typeParam(typeParam):
                return nullabilitySubtype(typeParam.nullability, .nonNull)
            case let .kClassType(kClassType):
                return nullabilitySubtype(kClassType.nullability, .nonNull)
            case .intersection:
                return isSubtype(subtype, supertype)
            default:
                return false
            }
        }

        if case let .stringStruct(lhsNullability) = lhs,
           case let .classType(rhsClass) = rhs,
           let charSequenceSym = charSequenceInterfaceSymbol,
           rhsClass.classSymbol == charSequenceSym
        {
            return nullabilitySubtype(lhsNullability, rhsClass.nullability)
        }

        if case let .classType(rhsClass) = rhs,
           let serializableSymbol = serializableInterfaceSymbol,
           rhsClass.classSymbol == serializableSymbol
        {
            switch lhs {
            case let .stringStruct(leftNullability):
                return nullabilitySubtype(leftNullability, rhsClass.nullability)
            case let .primitive(primitive, leftNullability):
                switch primitive {
                case .boolean, .char, .int, .long, .float, .double, .byte, .short:
                    return nullabilitySubtype(leftNullability, rhsClass.nullability)
                case .uint, .ulong, .ubyte, .ushort:
                    break
                }
            default:
                break
            }
        }

        if case let .typeParam(typeParam) = lhs {
            let upperBounds = declaredUpperBounds(for: typeParam.symbol)
            if !upperBounds.isEmpty {
                if upperBounds.contains(where: { isSubtype($0, supertype) }) {
                    return true
                }
            }
        }

        if case let .classType(rhsClass) = rhs, let annotationSym = annotationInterfaceSymbol, rhsClass.classSymbol == annotationSym {
            if case .nothing(.nonNull) = lhs { return true }
            if case let .classType(lhsClass) = lhs {
                guard nullabilitySubtype(lhsClass.nullability, rhsClass.nullability) else {
                    return false
                }
                if lhsClass.classSymbol == annotationSym { return true }
                if let symbol = symbolTable?.symbol(lhsClass.classSymbol), symbol.kind == .annotationClass {
                    return true
                }
            }
        }

        if case let .classType(rightClass) = rhs,
           let comparableSym = comparableInterfaceSymbol,
           rightClass.classSymbol == comparableSym,
           rightClass.args.count == 1
        {
            switch lhs {
            case let .primitive(_, leftNullability), let .stringStruct(leftNullability):
                guard nullabilitySubtype(leftNullability, rightClass.nullability) else { break }
                switch rightClass.args[0] {
                case let .in(argType), let .invariant(argType):
                    return argType == makeNonNullable(subtype)
                case .star:
                    return true
                case .out:
                    return false
                }
            default:
                break
            }
        }

        if case let .primitive(leftPrimitive, leftNullability) = lhs,
           case let .classType(rightClass) = rhs,
           let numberSym = numberClassSymbol,
           rightClass.classSymbol == numberSym
        {
            switch leftPrimitive {
            case .int, .long, .float, .double, .byte, .short:
                return nullabilitySubtype(leftNullability, rightClass.nullability)
            default:
                break
            }
        }

        switch (lhs, rhs) {
        case (.any(.nonNull), .any(.nullable)):
            return true

        case let (.typeParam(leftParam), .typeParam(rightParam)):
            return leftParam.symbol == rightParam.symbol
                && nullabilitySubtype(leftParam.nullability, rightParam.nullability)

        case let (.primitive(leftPrimitive, leftNullability), .primitive(rightPrimitive, rightNullability)):
            return leftPrimitive == rightPrimitive && nullabilitySubtype(leftNullability, rightNullability)

        case let (.stringStruct(leftNullability), .stringStruct(rightNullability)):
            return nullabilitySubtype(leftNullability, rightNullability)

        case let (.classType(leftClass), .classType(rightClass)):
            guard nullabilitySubtype(leftClass.nullability, rightClass.nullability) else {
                return false
            }
            let isLinkedExpectActualPair = areLinkedExpectActualClassSymbols(
                leftClass.classSymbol,
                rightClass.classSymbol
            )
            if leftClass.classSymbol != rightClass.classSymbol && !isLinkedExpectActualPair {
                guard isNominalSubtypeSymbol(leftClass.classSymbol, of: rightClass.classSymbol) else {
                    return false
                }
                let mappedArgs = liftedNominalSupertypeArgs(from: leftClass, to: rightClass.classSymbol) ?? []
                if mappedArgs.count == allTypeArguments(for: rightClass).count, !mappedArgs.isEmpty {
                    let liftedSupertype = make(.classType(classType(
                        for: rightClass.classSymbol,
                        arguments: mappedArgs,
                        nullability: leftClass.nullability
                    )))
                    return isSubtype(liftedSupertype, supertype)
                }
                return allTypeArguments(for: rightClass).isEmpty || allTypeArguments(for: rightClass).allSatisfy { arg in
                    if case .star = arg {
                        return true
                    }
                    return false
                }
            }
            let leftArguments = allTypeArguments(for: leftClass)
            let rightArguments = allTypeArguments(for: rightClass)
            if leftArguments.count != rightArguments.count {
                return false
            }
            if leftClass.classSymbol == kClassInterfaceSymbol,
               leftClass.args.count == 1,
               {
                   switch leftClass.args[0] {
                   case .in, .star: true
                   case .invariant, .out: false
                   }
               }(),
               case let .out(upperBound) = rightClass.args[0]
            {
                return isSubtype(anyType, upperBound)
            }
            let nominalOwner = symbolTable?.actualSymbol(for: leftClass.classSymbol)
                ?? symbolTable?.actualSymbol(for: rightClass.classSymbol)
                ?? leftClass.classSymbol
            let typeParameterSymbols = allTypeParameterSymbols(for: nominalOwner)
            let declarationVariances = allTypeParameterVariances(
                for: nominalOwner,
                fallbackArity: leftClass.args.count
            )
            for index in 0 ..< leftArguments.count {
                let lhsProjection: Projection
                if case .star = leftArguments[index] {
                    let bounds = typeParameterSymbols.indices.contains(index)
                        ? declaredUpperBounds(for: typeParameterSymbols[index]) : []
                    let variables = makeTypeVarBySymbol(typeParameterSymbols)
                    var substitution: [TypeVarID: TypeID] = [:]
                    var unresolvedStars: [SymbolID: TypeVarID] = [:]
                    for (parameter, argument) in zip(typeParameterSymbols, leftArguments) {
                        guard let variable = variables[parameter] else { continue }
                        switch argument {
                        case let .invariant(type), let .out(type): substitution[variable] = type
                        case .in, .star: unresolvedStars[parameter] = variable
                        }
                    }
                    let upperBound = substituteTypeParameters(
                        in: bounds.isEmpty ? nullableAnyType : make(.intersection(bounds)),
                        substitution: substitution, typeVarBySymbol: variables
                    )
                    if declarationVariances.indices.contains(index), declarationVariances[index] == .in
                        || OverloadResolver().containsTypeVariable(upperBound, typeVarBySymbol: unresolvedStars, typeSystem: self)
                    {
                        lhsProjection = .star
                    } else {
                        lhsProjection = .out(upperBound)
                    }
                } else {
                    lhsProjection = composedProjection(
                        declarationVariance: declarationVariances.indices.contains(index)
                            ? declarationVariances[index] : .invariant,
                        useSite: leftArguments[index]
                    )
                }
                let rhsProjection = composedProjection(
                    declarationVariance: declarationVariances.indices.contains(index)
                        ? declarationVariances[index] : .invariant,
                    useSite: rightArguments[index]
                )
                if !isProjectionSubtype(lhsProjection, rhsProjection) {
                    return false
                }
            }
            return true

        case let (.functionType(leftFunction), .functionType(rightFunction)):
            if rightFunction.isCallableReference && !leftFunction.isCallableReference {
                return false
            }
            let leftParams = leftFunction.contextReceivers
                + (leftFunction.receiver.map { [$0] } ?? []) + leftFunction.params
            let rightParams = rightFunction.contextReceivers
                + (rightFunction.receiver.map { [$0] } ?? []) + rightFunction.params
            guard leftParams.count == rightParams.count else {
                return false
            }
            guard leftFunction.isSuspend == rightFunction.isSuspend else {
                return false
            }
            guard nullabilitySubtype(leftFunction.nullability, rightFunction.nullability) else {
                return false
            }
            for (leftParam, rightParam) in zip(leftParams, rightParams) where !isSubtype(rightParam, leftParam) {
                return false
            }
            return isSubtype(leftFunction.returnType, rightFunction.returnType)

        case let (.functionType(leftFunction), .classType(rightClass)):
            if leftFunction.isCallableReference, let kFunctionSymbol = kFunctionInterfaceSymbol {
                let reflectiveType = make(.classType(ClassType(
                    classSymbol: kFunctionSymbol,
                    args: [.out(leftFunction.returnType)],
                    nullability: leftFunction.nullability
                )))
                if isSubtype(reflectiveType, supertype) {
                    return true
                }
                let arity = leftFunction.contextReceivers.count
                    + (leftFunction.receiver.map { [$0] } ?? []).count + leftFunction.params.count
                if let inheritedFunction = inheritedFunctionInterfaceClassType(
                    of: rightClass,
                    arity: arity,
                    isSuspend: false
                ), isSubtype(makeNonNullable(make(.classType(rightClass))), reflectiveType),
                   functionTypeSubtypeOfFunctionN(leftFunction, inheritedFunction)
                {
                    return true
                }
                if leftFunction.isSuspend,
                   let inheritedSuspendFunction = inheritedFunctionInterfaceClassType(
                       of: rightClass,
                       arity: arity,
                       isSuspend: true
                   ), isSubtype(makeNonNullable(make(.classType(rightClass))), reflectiveType),
                   functionTypeSubtypeOfFunctionN(leftFunction, inheritedSuspendFunction)
                {
                    return true
                }
            }
            guard rightClass.classSymbol == functionInterfaceSymbol
                || (leftFunction.isCallableReference
                    && (rightClass.classSymbol == kFunctionInterfaceSymbol
                        || rightClass.classSymbol == kCallableInterfaceSymbol))
            else {
                return functionTypeSubtypeOfFunctionN(leftFunction, rightClass)
            }
            guard nullabilitySubtype(leftFunction.nullability, rightClass.nullability) else {
                return false
            }
            if rightClass.args.isEmpty { return true }
            guard rightClass.args.count == 1 else { return false }
            let returnArg = rightClass.args[0]
            switch returnArg {
            case .star: return true
            case let .out(argType): return isSubtype(leftFunction.returnType, argType)
            case let .invariant(argType): return isSubtype(leftFunction.returnType, argType)
            case .in: return true
            }

        case let (.classType(leftClass), .functionType(rightFunction)):
            guard nullabilitySubtype(leftClass.nullability, rightFunction.nullability) else {
                return false
            }
            if functionInterfaceArity(of: leftClass.classSymbol, isSuspend: rightFunction.isSuspend) != nil {
                return functionNSubtypeOfFunctionType(leftClass, rightFunction)
            }
            if let liftedFunctionInterface = inheritedFunctionInterfaceClassType(
                of: leftClass,
                arity: rightFunction.contextReceivers.count
                    + (rightFunction.receiver.map { [$0] } ?? []).count + rightFunction.params.count,
                isSuspend: rightFunction.isSuspend
            ), functionNSubtypeOfFunctionType(liftedFunctionInterface, rightFunction) {
                return true
            }
            guard let symbols = symbolTable else { return false }
            guard let sym = symbols.symbol(leftClass.classSymbol),
                  sym.kind == .interface,
                  sym.flags.contains(.funInterface)
            else {
                return false
            }
            let children = symbols.declaredChildren(of: leftClass.classSymbol)
            var abstractSignatures: [(SymbolID, FunctionSignature)] = []
            for childID in children {
                guard let childSym = symbols.symbol(childID),
                      childSym.kind == .function,
                      childSym.flags.contains(.abstractType),
                      let signature = symbols.functionSignature(for: childID)
                else {
                    continue
                }
                abstractSignatures.append((childID, signature))
            }
            guard abstractSignatures.count == 1 else { return false }
            let samSignature = abstractSignatures[0].1
            let typeParamSymbols = nominalTypeParameterSymbols(for: leftClass.classSymbol)
            guard typeParamSymbols.count == leftClass.args.count else { return false }
            let typeVarBySymbol = makeTypeVarBySymbol(typeParamSymbols)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, arg) in leftClass.args.enumerated() {
                guard index < typeParamSymbols.count else { break }
                let tpSymbol = typeParamSymbols[index]
                guard let typeVar = typeVarBySymbol[tpSymbol] else { continue }
                switch arg {
                case let .invariant(type): substitution[typeVar] = type
                case let .out(type): substitution[typeVar] = type
                case .in, .star: substitution[typeVar] = anyType
                }
            }
            let samParamTypes = samSignature.parameterTypes.map {
                substituteTypeParameters(in: $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
            }
            let samReturnType = substituteTypeParameters(
                in: samSignature.returnType,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            guard samParamTypes.count == rightFunction.params.count else { return false }
            guard samSignature.isSuspend == rightFunction.isSuspend else { return false }
            for (samParam, rightParam) in zip(samParamTypes, rightFunction.params) {
                // swiftlint:disable:next for_where
                if !isSubtype(rightParam, samParam) { return false }
            }
            return isSubtype(samReturnType, rightFunction.returnType)

        case let (.any(leftNullability), .any(rightNullability)):
            return nullabilitySubtype(leftNullability, rightNullability)

        case let (.kClassType(leftKClass), .kClassType(rightKClass)):
            guard nullabilitySubtype(leftKClass.nullability, rightKClass.nullability) else {
                return false
            }
            return isProjectionSubtype(.invariant(leftKClass.argument), .invariant(rightKClass.argument))

        case let (.kClassType(leftKClass), .classType(rightClass)):
            guard let kClassSymbol = kClassInterfaceSymbol,
                  nullabilitySubtype(leftKClass.nullability, rightClass.nullability)
            else {
                return false
            }
            if rightClass.classSymbol == kClassSymbol {
                if rightClass.args.isEmpty { return true }
                guard rightClass.args.count == 1 else { return false }
                return isProjectionSubtype(.invariant(leftKClass.argument), projection(from: rightClass.args[0]))
            }
            guard isNominalSubtypeSymbol(kClassSymbol, of: rightClass.classSymbol) else {
                return false
            }
            return rightClass.args.isEmpty || rightClass.args.allSatisfy {
                if case .star = $0 { return true }
                return false
            }

        case let (.classType(leftClass), .kClassType(rightKClass)):
            guard let kClassSymbol = kClassInterfaceSymbol,
                  nullabilitySubtype(leftClass.nullability, rightKClass.nullability)
            else {
                return false
            }
            if leftClass.classSymbol == kClassSymbol {
                guard leftClass.args.count == 1 else { return false }
                return isProjectionSubtype(projection(from: leftClass.args[0]), .invariant(rightKClass.argument))
            }
            return false

        default:
            return false
        }
    }

    /// Normalizes a `.classType` wrapping one of the synthetic `kotlin.<Name>`
    /// disguise symbols (`stringClassSymbol`/`charClassSymbol`/`anyClassSymbol`
    /// — see their doc comments on `TypeSystem`) back to the canonical builtin
    /// `TypeID`, preserving nullability, and returns its (already-known) kind
    /// alongside it — `isSubtype` needs both anyway, and computing the kind
    /// directly here instead of via a second `kind(of:)` call keeps this at
    /// exactly one lookup per input, same as before this normalization
    /// existed.
    ///
    /// Without this, `String::class`'s `classRefTargetType` (which resolves to
    /// the disguised nominal form via scope lookup — see `inferClassRefExpr`)
    /// compares as unrelated to the canonical `stringType` that an ordinary
    /// `is String` check uses, so e.g. inferring `KClass<T>.cast(): T` with a
    /// `String::class` receiver against an explicit `String`-typed call site
    /// reports "Conflicting bounds for type variable" even though both bounds
    /// mean the same type.
    private func normalizedBuiltinDisguisedClassTypeAndKind(_ type: TypeID) -> (TypeID, TypeKind) {
        let kind = kind(of: type)
        guard case let .classType(classType) = kind else {
            return (type, kind)
        }
        let nullability = classType.nullability
        if let stringClassSymbol, classType.classSymbol == stringClassSymbol {
            return (withNullability(nullability, for: stringType), .stringStruct(nullability))
        }
        if let charClassSymbol, classType.classSymbol == charClassSymbol {
            return (withNullability(nullability, for: charType), .primitive(.char, nullability))
        }
        if let unitClassSymbol, classType.classSymbol == unitClassSymbol {
            let canonical = withNullability(nullability, for: unitType)
            return (canonical, self.kind(of: canonical))
        }
        if let anyClassSymbol, classType.classSymbol == anyClassSymbol {
            return (withNullability(nullability, for: anyType), .any(nullability))
        }
        return (type, kind)
    }

    public func lub(_ types: [TypeID]) -> TypeID {
        lub(types, retainingCommonIntersection: false)
    }

    private func lub(_ types: [TypeID], retainingCommonIntersection: Bool) -> TypeID {
        let hasNullableNothing = types.contains { kind(of: $0) == .nothing(.nullable) }
        let filtered = types.filter { kind(of: $0) != .error && kind(of: $0) != .nothing(.nonNull) && kind(of: $0) != .nothing(.nullable) }
        guard let first = filtered.first else {
            let hasNothing = types.contains { kind(of: $0) == .nothing(.nonNull) || kind(of: $0) == .nothing(.nullable) }
            if hasNullableNothing { return nullableNothingType }
            return hasNothing ? nothingType : errorType
        }
        let result: TypeID = if filtered.dropFirst().allSatisfy({ $0 == first }) {
            first
        } else if let commonTypeParameter = filtered.first(where: { candidate in
            guard case .typeParam = kind(of: candidate) else { return false }
            return filtered.allSatisfy { isSubtype($0, candidate) }
        }) {
            commonTypeParameter
        } else if let kClassLub = lubKClassTypes(filtered) {
            kClassLub
        } else {
            lubReapplyingNullability(filtered, retainingCommonIntersection: retainingCommonIntersection)
        }
        if hasNullableNothing {
            let nullable = makeNullable(result)
            if nullable == result {
                if isSubtype(nullableNothingType, result) {
                    return result
                }
                return nullableAnyType
            }
            return nullable
        }
        return result
    }

    func inferenceLubRetainingSharedSupertypes(
        _ types: [TypeID],
        integerLiterals: [TypeID: IntegerLiteralProvenance] = [:]
    ) -> TypeID {
        let filtered = types.filter {
            kind(of: $0) != .error
                && kind(of: $0) != .nothing(.nonNull)
                && kind(of: $0) != .nothing(.nullable)
        }
        if filtered.count > 1,
           filtered.allSatisfy(isIntegerFamilyJoinInput),
           Set(filtered.map { makeNonNullable($0) }).count > 1,
           let verdict = integerOnlyJoinResult(filtered, integerLiterals: integerLiterals) {
            return verdict
        }
        let fallback = lub(types, retainingCommonIntersection: true)
        guard fallback == anyType || fallback == nullableAnyType else {
            return platformNumericJoinIntersection(fallback: fallback, from: filtered) ?? fallback
        }

        guard filtered.count > 1 else {
            return fallback
        }

        if let sharedUpperBound = inferenceLubRetainingCommonTypeParameterUpperBounds(filtered) {
            return sharedUpperBound
        }

        let resultNullability: Nullability = types.contains { nullability(of: $0) == .nullable }
            ? .nullable
            : .nonNull
        guard let comparableSymbol = comparableInterfaceSymbol else {
            return fallback
        }
        let comparable = make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.star],
            nullability: resultNullability
        )))
        guard filtered.allSatisfy({ isSubtype($0, comparable) }) else {
            return fallback
        }
        // kotlinc keeps every most-specific supertype a mix of platform
        // builtins shares — `Comparable<*>` & `Serializable` for `String` +
        // `Int`, or `Comparable<String & Char>` & `Serializable` for `String` +
        // `Char` — where this approximation drops to bare `Comparable<*>`.
        // Reifying the join as an intersection keeps a reified type argument
        // inferred from it forbidden (KT-72035). A join that also involves a
        // non-builtin input is honestly single-conjunct (`Comparable<C>` +
        // `Int` has only `Comparable<*>` in common) and stays approximated.
        if filtered.allSatisfy({ isPlatformBuiltinJoinInput($0) }),
           Set(filtered.map { makeNonNullable($0) }).count > 1,
           filtered.contains(where: { !isIntegerFamilyJoinInput($0) }) {
            return make(.intersection([comparable]))
        }
        return comparable
    }

    /// The all-numeric shortcut in `nearestCommonSupertype` collapses a mixed
    /// numeric join to bare `Number`, dropping the `Comparable<*>` conjunct
    /// kotlinc retains — `Number & Comparable<*>` for `Int` + `Double`
    /// (KT-72035). Integer-only mixes stay exempted: unsuffixed literals adopt
    /// the widest member (`arrayOf(1, 2L)` → `Array<Long>`) and kotlinc's
    /// common-supertype computation also unifies several declared integer
    /// pairs (`UByte` + `Int`, `UInt` + `ULong`), so a pure integer join is
    /// not necessarily an intersection there either.
    private func platformNumericJoinIntersection(fallback: TypeID, from filtered: [TypeID]) -> TypeID? {
        guard let numberSym = numberClassSymbol,
              case let .classType(numberClass) = kind(of: fallback),
              numberClass.classSymbol == numberSym,
              Set(filtered.map { makeNonNullable($0) }).count > 1,
              filtered.allSatisfy(isNumericPrimitiveType),
              filtered.contains(where: { !isIntegerFamilyJoinInput($0) }),
              let comparableSymbol = comparableInterfaceSymbol
        else {
            return nil
        }
        let comparable = make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.star],
            nullability: numberClass.nullability
        )))
        return make(.intersection([fallback, comparable]))
    }

    private func isPlatformBuiltinJoinInput(_ type: TypeID) -> Bool {
        switch kind(of: makeNonNullable(type)) {
        case .primitive, .stringStruct:
            return true
        default:
            return false
        }
    }

    private func isIntegerFamilyJoinInput(_ type: TypeID) -> Bool {
        guard case let .primitive(primitive, _) = kind(of: makeNonNullable(type)) else {
            return false
        }
        switch primitive {
        case .byte, .short, .int, .long, .ubyte, .ushort, .uint, .ulong:
            return true
        case .boolean, .char, .float, .double:
            return false
        }
    }

    /// Resolves an all-integer-family inference join the way kotlinc 2.4 does:
    ///
    /// - Two or more distinct *declared signed* integer types share only
    ///   `Number & Comparable<*>` — returning that intersection keeps a
    ///   reified argument forbidden (`arrayOf(i, 2L)`, `arrayOf(b, s)`).
    /// - A literal lower bound adopts the declared integer type when that
    ///   type is a member of its literal-type set (`1` adopts `Long`), and a
    ///   literal that cannot adopt (`i` + `5000000000`, or `i` + `2L` where
    ///   `2L` is already a declared `Long`) falls back to the same
    ///   signed-vs-signed intersection.
    /// - Any *declared unsigned* member unifies the join into a single bound
    ///   (`Comparable<*>`), so unsigned mixes — including literals folded
    ///   through their unsigned defaults — stay accepted.
    /// - With no declared member at all, the literal defaults decide: mixed
    ///   signedness (`1` + `2u`) has no common member and fails the solve,
    ///   while a single signedness keeps the nominal join.
    ///
    /// Returns `nil` when the join stays accepted and the ordinary fallback
    /// result applies.
    private func integerOnlyJoinResult(
        _ filtered: [TypeID],
        integerLiterals: [TypeID: IntegerLiteralProvenance]
    ) -> TypeID? {
        var declaredNonNull: Set<TypeID> = []
        var declaredHasUnsigned = false
        var literalInputs: [(bound: TypeID, provenance: IntegerLiteralProvenance)] = []
        for type in filtered {
            if let provenance = integerLiterals[type] {
                literalInputs.append((type, provenance))
            } else {
                let nonNull = makeNonNullable(type)
                declaredNonNull.insert(nonNull)
                if case let .primitive(primitive, _) = kind(of: nonNull),
                   isUnsignedIntegerPrimitive(primitive) {
                    declaredHasUnsigned = true
                }
            }
        }
        guard !declaredHasUnsigned else { return nil }

        if declaredNonNull.count > 1 {
            return integerJoinIntersection(for: filtered)
        }
        if let declared = declaredNonNull.first,
           case let .primitive(declaredPrimitive, _) = kind(of: declared) {
            for (bound, provenance) in literalInputs {
                if integerLiteralPossiblePrimitives(provenance).contains(declaredPrimitive) {
                    continue
                }
                guard case let .primitive(approx, _) = kind(of: makeNonNullable(bound)),
                      approx != declaredPrimitive
                else { continue }
                if !isUnsignedIntegerPrimitive(approx) {
                    return integerJoinIntersection(for: filtered)
                }
            }
            return nil
        }

        var hasSignedLiteral = false
        var hasUnsignedLiteral = false
        for (_, provenance) in literalInputs {
            switch provenance {
            case .signed: hasSignedLiteral = true
            case .unsigned: hasUnsignedLiteral = true
            }
        }
        if hasSignedLiteral, hasUnsignedLiteral {
            // `1` + `2u` has no common literal-type member; kotlinc reports a
            // plain type mismatch, so the solve must fail rather than join an
            // intersection a non-reified parameter would still accept.
            return errorType
        }
        return nil
    }

    private func integerLiteralPossiblePrimitives(
        _ provenance: IntegerLiteralProvenance
    ) -> [PrimitiveType] {
        switch provenance {
        case let .signed(value):
            if (-128 ... 127).contains(value) {
                return [.byte, .short, .int, .long]
            }
            if (-32768 ... 32767).contains(value) {
                return [.short, .int, .long]
            }
            if (Int64(Int32.min) ... Int64(Int32.max)).contains(value) {
                return [.int, .long]
            }
            return [.long]
        case let .unsigned(value):
            if value <= UInt64(UInt8.max) {
                return [.ubyte, .ushort, .uint, .ulong]
            }
            if value <= UInt64(UInt16.max) {
                return [.ushort, .uint, .ulong]
            }
            if value <= UInt64(UInt32.max) {
                return [.uint, .ulong]
            }
            return [.ulong]
        }
    }

    private func isUnsignedIntegerPrimitive(_ primitive: PrimitiveType) -> Bool {
        switch primitive {
        case .ubyte, .ushort, .uint, .ulong:
            return true
        case .boolean, .byte, .char, .double, .float, .int, .long, .short:
            return false
        }
    }

    private func integerJoinIntersection(for filtered: [TypeID]) -> TypeID? {
        let resultNullability: Nullability = filtered.contains {
            nullability(of: $0) == .nullable
        } ? .nullable : .nonNull
        guard let numberSym = numberClassSymbol,
              let comparableSymbol = comparableInterfaceSymbol
        else {
            return nil
        }
        let number = make(.classType(ClassType(
            classSymbol: numberSym,
            args: [],
            nullability: resultNullability
        )))
        let comparable = make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.star],
            nullability: resultNullability
        )))
        return make(.intersection([number, comparable]))
    }

    private func inferenceLubRetainingCommonTypeParameterUpperBounds(_ types: [TypeID]) -> TypeID? {
        guard types.count > 1 else { return nil }

        var candidates: [TypeID] = []
        var pending = types
        var visitedParameters: Set<SymbolID> = []
        while let input = pending.popLast() {
            guard let parameter = typeParamPart(of: input) else { continue }
            if let capture = parameter.capture {
                if !candidates.contains(capture.upper) {
                    candidates.append(capture.upper)
                }
                continue
            }
            guard visitedParameters.insert(parameter.symbol).inserted else { continue }

            for bound in declaredUpperBounds(for: parameter.symbol) {
                let candidate = parameter.nullability == .nullable ? makeNullable(bound) : bound
                if !candidates.contains(candidate) {
                    candidates.append(candidate)
                }
                if case .typeParam = kind(of: candidate) {
                    pending.append(candidate)
                }
            }
        }

        let commonBounds = candidates.filter { candidate in
            types.allSatisfy { input in
                let subtypeCheck = if case .intersection = kind(of: input) {
                    isNonNullLubSubtype(input, candidate, visitedParameters: [])
                } else {
                    isSubtype(input, candidate)
                }
                guard subtypeCheck else { return false }
                // A null-capable parameter can be instantiated with a
                // nullable type, so a non-null candidate cannot be a bound
                // of it (KUU-2693).
                if isNullableCapableTypeParameter(input, visitedParameters: []) {
                    return nullability(of: candidate) != .nonNull
                        || isNullableCapableTypeParameter(candidate, visitedParameters: [])
                }
                return true
            }
        }
        guard !commonBounds.isEmpty else { return nil }

        var mostSpecific: [TypeID] = []
        for candidate in commonBounds {
            if mostSpecific.contains(where: { isSubtype($0, candidate) }) {
                continue
            }
            mostSpecific.removeAll { isSubtype(candidate, $0) }
            mostSpecific.append(candidate)
        }
        if mostSpecific.count == 1 {
            return mostSpecific[0]
        }
        return make(.intersection(mostSpecific))
    }

    public func glb(_ types: [TypeID]) -> TypeID {
        guard let first = types.first else {
            return errorType
        }
        if types.dropFirst().allSatisfy({ $0 == first }) {
            return first
        }
        let hasNullableNothing = types.contains { kind(of: $0) == .nothing(.nullable) }
        if types.contains(where: { if case .nothing = kind(of: $0) { return true }; return false }) {
            if hasNullableNothing, types.allSatisfy({ isSubtype(nullableNothingType, $0) }) {
                return nullableNothingType
            }
            return nothingType
        }
        return make(.intersection(types))
    }

    func nullabilitySubtype(_ lhs: Nullability, _ rhs: Nullability) -> Bool {
        if lhs == rhs { return true }
        if lhs == .nonNull, rhs == .nullable { return true }
        if lhs == .platformType { return true }
        if rhs == .platformType { return true }
        return false
    }

    func isNominalSubtypeSymbol(_ candidate: SymbolID, of base: SymbolID) -> Bool {
        let closure = nominalSupertypeClosure(for: candidate)
        if closure.symbols.contains(base) || closure.linkedTargets.contains(base) {
            return true
        }
        return !closure.symbols.isDisjoint(with: nominalForwardLinks(for: base))
    }

    private func areLinkedExpectActualClassSymbols(_ lhs: SymbolID, _ rhs: SymbolID) -> Bool {
        nominalForwardLinks(for: lhs).contains(rhs)
            || nominalForwardLinks(for: rhs).contains(lhs)
    }

    func actualTypeAliasTargetNominalSymbol(
        for symbolID: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID? {
        var currentID = symbolID
        var visited: Set<SymbolID> = []
        while visited.insert(currentID).inserted {
            guard let symbol = symbols.symbol(currentID) else { return nil }
            let aliasID: SymbolID?
            if symbol.kind == .typeAlias {
                aliasID = currentID
            } else if symbol.flags.contains(.expectDeclaration),
                      let actualID = symbols.actualSymbol(for: currentID),
                      symbols.symbol(actualID)?.kind == .typeAlias
            {
                aliasID = actualID
            } else {
                return nil
            }
            guard let aliasID,
                  let underlying = symbols.typeAliasUnderlyingType(for: aliasID),
                  case let .classType(classType) = kind(of: underlying),
                  let target = symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            if target.kind == .typeAlias {
                currentID = target.id
                continue
            }
            if target.flags.contains(.expectDeclaration),
               let actualTargetID = symbols.actualSymbol(for: target.id)
            {
                return actualTargetID
            }
            return target.id
        }
        return nil
    }

    enum Projection {
        case invariant(TypeID)
        case out(TypeID)
        case `in`(TypeID)
        case star
        case invalid
    }

    func normalizedNominalVariances(for symbol: SymbolID, arity: Int) -> [TypeVariance] {
        let stored = nominalTypeParameterVariances(for: symbol)
        if stored.count >= arity {
            return Array(stored.prefix(arity))
        }
        if stored.isEmpty {
            return Array(repeating: .invariant, count: arity)
        }
        return stored + Array(repeating: .invariant, count: arity - stored.count)
    }

    func composedProjection(
        declarationVariance: TypeVariance,
        useSite: TypeArg
    ) -> Projection {
        switch declarationVariance {
        case .invariant:
            projection(from: useSite)
        case .out:
            outProjection(useSite: useSite)
        case .in:
            inProjection(useSite: useSite)
        }
    }

    private func outProjection(useSite: TypeArg) -> Projection {
        switch useSite {
        case let .invariant(type): .out(type)
        case let .out(type): .out(type)
        case .star: .star
        case .in: .invalid
        }
    }

    private func inProjection(useSite: TypeArg) -> Projection {
        switch useSite {
        case let .invariant(type): .in(type)
        case let .in(type):
            // A use-site `in` projection on an `in`-declared parameter is
            // redundant: `Sink<in X>` behaves like `Sink<X>` and admits
            // `Sink<S>` whenever `X <: S` (KUU-1381). Composing to `.out`
            // flipped the bound and rejected every argument.
            .in(type)
        case .star: .star
        case .out: .invalid
        }
    }

    func projection(from arg: TypeArg) -> Projection {
        switch arg {
        case let .invariant(type):
            .invariant(type)
        case let .out(type):
            .out(type)
        case let .in(type):
            .in(type)
        case .star:
            .star
        }
    }

    func isProjectionSubtype(_ lhs: Projection, _ rhs: Projection) -> Bool {
        if case .star = rhs { return true }
        if case .invalid = rhs { return false }
        if case .invalid = lhs { return false }
        if case .star = lhs { return false }

        switch (lhs, rhs) {
        case let (.invariant(la), .invariant(ra)):
            return isSubtype(la, ra) && isSubtype(ra, la)
        case let (.invariant(la), .out(ra)):
            return isSubtype(la, ra)
        case let (.invariant(la), .in(ra)):
            return isSubtype(ra, la)
        case let (.out(la), .out(ra)):
            return isSubtype(la, ra)
        case let (.in(la), .in(ra)):
            return isSubtype(ra, la)
        default:
            return false
        }
    }

    private func lubReapplyingNullability(
        _ filtered: [TypeID],
        retainingCommonIntersection: Bool = false
    ) -> TypeID {
        let anyMarkedNullable = filtered.contains { nullability(of: $0) == .nullable }
        // A type parameter written without `?` is still nullable-capable
        // unless an upper bound is definitely non-null — the implicit bound
        // is `Any?`, so `lub(K, V)` for unrelated `K`, `V` must be `Any?`
        // rather than `Any` (KUU-2693).
        let anyNullable = anyMarkedNullable || filtered.contains {
            isNullableCapableTypeParameter($0, visitedParameters: [])
        }
        let nonNull = filtered.map { makeNonNullable($0) }
        let base: TypeID
        if let firstNonNull = nonNull.first, nonNull.dropFirst().allSatisfy({ $0 == firstNonNull }) {
            base = firstNonNull
        } else if let kClassLub = lubKClassTypes(nonNull) {
            base = kClassLub
        } else if let commonSupertype = nearestCommonSupertype(
            nonNull,
            retainingCommonIntersection: retainingCommonIntersection && !anyNullable
        ) {
            base = commonSupertype
        } else {
            base = anyType
        }
        guard anyNullable else { return base }
        if !anyMarkedNullable, isNullableCapableTypeParameter(base, visitedParameters: []) {
            return base
        }
        return makeNullable(base)
    }

    private func isNullableCapableTypeParameter(
        _ type: TypeID,
        visitedParameters: Set<SymbolID>
    ) -> Bool {
        guard case let .typeParam(parameter) = kind(of: type) else { return false }
        if parameter.nullability == .nullable { return true }
        let bounds: [TypeID]
        if let capture = parameter.capture {
            bounds = [capture.upper]
        } else {
            guard !visitedParameters.contains(parameter.symbol) else {
                return true
            }
            bounds = declaredUpperBounds(for: parameter.symbol)
        }
        guard !bounds.isEmpty else { return true }
        var visited = visitedParameters
        visited.insert(parameter.symbol)
        return bounds.allSatisfy { bound in
            if case .typeParam = kind(of: bound) {
                return isNullableCapableTypeParameter(bound, visitedParameters: visited)
            }
            return !isDefinitelyNonNull(bound)
        }
    }

    func canHoldNull(_ type: TypeID) -> Bool {
        if case .typeParam = kind(of: type) {
            return isNullableCapableTypeParameter(type, visitedParameters: [])
        }
        return nullability(of: type) == .nullable
    }

    private func typeParamPart(of type: TypeID) -> TypeParamType? {
        switch kind(of: type) {
        case let .typeParam(parameter):
            return parameter
        case let .intersection(parts):
            for part in parts {
                if case let .typeParam(parameter) = kind(of: part) {
                    return parameter
                }
            }
            return nil
        default:
            return nil
        }
    }

    private func nearestCommonSupertype(
        _ types: [TypeID],
        retainingCommonIntersection: Bool = false
    ) -> TypeID? {
        if let dominating = types.first(where: { candidate in
            types.allSatisfy { isNonNullLubSubtype($0, candidate, visitedParameters: []) }
        }) {
            return dominating
        }
        if let sharedUpperBound = nearestCommonTypeParameterUpperBound(types) {
            return sharedUpperBound
        }
        if let commonFunction = commonFunctionSupertype(
            types,
            retainingCommonIntersection: retainingCommonIntersection
        ) {
            return commonFunction
        }
        if let numberSym = numberClassSymbol, types.allSatisfy(isNumericPrimitiveType) {
            return make(.classType(ClassType(classSymbol: numberSym, args: [], nullability: .nonNull)))
        }
        if let commonNominal = commonNominalSupertype(types) {
            return commonNominal
        }
        return nearestCommonNominalSupertype(types, retainingCommonIntersection: retainingCommonIntersection)
    }

    private func nearestCommonTypeParameterUpperBound(_ types: [TypeID]) -> TypeID? {
        guard types.count > 1 else { return nil }

        var candidates: [TypeID] = []
        var pending = types
        var visitedParameters: Set<SymbolID> = []
        while let input = pending.popLast() {
            guard let parameter = typeParamPart(of: input) else {
                continue
            }
            guard visitedParameters.insert(parameter.symbol).inserted else {
                continue
            }

            let bounds: [TypeID]
            if let capture = parameter.capture {
                bounds = [capture.upper]
            } else {
                bounds = declaredUpperBounds(for: parameter.symbol)
            }
            for bound in bounds {
                let candidate = makeNonNullable(bound)
                if !candidates.contains(candidate) {
                    candidates.append(candidate)
                }
                if case .typeParam = kind(of: candidate) {
                    pending.append(candidate)
                }
            }
        }

        let commonBounds = candidates.filter { candidate in
            types.allSatisfy { isNonNullLubSubtype($0, candidate, visitedParameters: []) }
        }
        guard !commonBounds.isEmpty else { return nil }

        var mostSpecific: [TypeID] = []
        for candidate in commonBounds {
            if mostSpecific.contains(where: {
                isNonNullLubSubtype($0, candidate, visitedParameters: [])
            }) {
                continue
            }
            mostSpecific.removeAll {
                isNonNullLubSubtype(candidate, $0, visitedParameters: [])
            }
            mostSpecific.append(candidate)
        }
        if mostSpecific.count == 1 {
            return mostSpecific[0]
        }
        return make(.intersection(mostSpecific))
    }

    private func isNonNullLubSubtype(
        _ subtype: TypeID,
        _ supertype: TypeID,
        visitedParameters: Set<SymbolID>
    ) -> Bool {
        if subtype == supertype { return true }
        // A `Nothing?` conjunct means "this value held null" — it must not
        // satisfy a join candidate on the parameter's behalf: `Nothing? & K`
        // is a subtype of `V` (null is a `V`), but the common supertype of
        // `Nothing? & K` and `V` is `Any?`, not `V` (KUU-2693).
        var effectiveSubtype = subtype
        if case let .intersection(parts) = kind(of: subtype),
           parts.contains(where: { kind(of: $0) == .nothing(.nullable) })
        {
            let rest = parts.filter { kind(of: $0) != .nothing(.nullable) }
            effectiveSubtype = rest.count == 1 ? rest[0]
                : rest.isEmpty ? nothingType
                : make(.intersection(rest))
        }
        if case let .intersection(parts) = kind(of: effectiveSubtype) {
            return parts.contains {
                isNonNullLubSubtype($0, supertype, visitedParameters: visitedParameters)
            }
        }
        guard let parameter = typeParamPart(of: effectiveSubtype) else {
            return isSubtype(effectiveSubtype, supertype)
        }
        guard !visitedParameters.contains(parameter.symbol) else { return false }

        var nextVisited = visitedParameters
        nextVisited.insert(parameter.symbol)
        let bounds: [TypeID]
        if let capture = parameter.capture {
            bounds = [capture.upper]
        } else {
            bounds = declaredUpperBounds(for: parameter.symbol)
        }
        if bounds.isEmpty {
            return isSubtype(subtype, supertype)
        }
        return bounds.contains { bound in
            isNonNullLubSubtype(
                makeNonNullable(bound),
                supertype,
                visitedParameters: nextVisited
            )
        }
    }

    private func commonFunctionSupertype(
        _ types: [TypeID],
        retainingCommonIntersection: Bool
    ) -> TypeID? {
        guard types.count > 1 else { return nil }
        let functions = types.compactMap { type -> FunctionType? in
            guard case let .functionType(function) = kind(of: type) else { return nil }
            return function
        }
        guard functions.count == types.count, let first = functions.first else {
            return nil
        }
        let effectiveParams = functions.map { function in
            (function.receiver.map { [$0] } ?? []) + function.params
        }
        guard let firstParams = effectiveParams.first else { return nil }
        guard functions.allSatisfy({ function in
            function.contextReceivers.count == first.contextReceivers.count
                && function.isSuspend == first.isSuspend
                && function.throws == first.throws
        }), effectiveParams.allSatisfy({ $0.count == firstParams.count }) else {
            return nil
        }

        let contextReceivers = first.contextReceivers.indices.map { index in
            commonFunctionInputType(functions.map { $0.contextReceivers[index] })
        }
        let commonParams = firstParams.indices.map { index in
            commonFunctionInputType(effectiveParams.map { $0[index] })
        }
        let returnType = lub(
            functions.map(\.returnType),
            retainingCommonIntersection: retainingCommonIntersection
        )
        let common = make(.functionType(FunctionType(
            contextReceivers: contextReceivers,
            receiver: nil,
            params: commonParams,
            returnType: returnType,
            isSuspend: first.isSuspend,
            isCallableReference: false,
            nullability: .nonNull,
            throws: first.throws
        )))
        return types.allSatisfy { isSubtype($0, common) } ? common : nil
    }

    private func commonFunctionInputType(_ types: [TypeID]) -> TypeID {
        let uniqueTypes = Array(Set(types)).sorted { $0.rawValue < $1.rawValue }
        if let existingBound = uniqueTypes.first(where: { candidate in
            uniqueTypes.allSatisfy { isSubtype(candidate, $0) }
        }) {
            return existingBound
        }
        return make(.intersection(uniqueTypes))
    }

    private func nearestCommonNominalSupertype(
        _ types: [TypeID],
        retainingCommonIntersection: Bool = false
    ) -> TypeID? {
        guard let mostSpecific = nearestCommonNominalSupertypes(types) else { return nil }
        if retainingCommonIntersection, mostSpecific.count > 1 {
            return make(.intersection(mostSpecific))
        }
        let isInterface: (TypeID) -> Bool = { [self] candidate in
            guard case let .classType(classType) = kind(of: candidate) else { return false }
            return symbolTable?.symbol(classType.classSymbol)?.kind == .interface
        }
        return mostSpecific.first(where: { !isInterface($0) }) ?? mostSpecific.first
    }

    private func nearestCommonNominalSupertypes(_ types: [TypeID]) -> [TypeID]? {
        guard types.count > 1 else { return nil }
        var classTypes: [ClassType] = []
        for type in types {
            guard case let .classType(classType) = kind(of: type), classType.nullability == .nonNull else {
                return nil
            }
            classTypes.append(classType)
        }
        let first = classTypes[0]

        var ancestors: [SymbolID] = []
        var visited: Set<SymbolID> = [first.classSymbol]
        var worklist = directNominalSupertypes(for: first.classSymbol)
        var head = 0
        while head < worklist.count {
            let ancestor = worklist[head]
            head += 1
            guard visited.insert(ancestor).inserted else { continue }
            ancestors.append(ancestor)
            worklist.append(contentsOf: directNominalSupertypes(for: ancestor))
        }

        var survivors: [TypeID] = []
        for ancestor in ancestors {
            let args = liftedNominalSupertypeArgs(
                from: first,
                to: ancestor
            ) ?? []
            let candidate = make(.classType(classType(
                for: ancestor, arguments: args, nullability: .nonNull
            )))
            if normalizedBuiltinDisguisedClassTypeAndKind(candidate).0 == anyType {
                continue
            }
            if types.allSatisfy({ isSubtype($0, candidate) }) {
                survivors.append(candidate)
            }
        }

        let mostSpecific = survivors.filter { candidate in
            !survivors.contains { other in other != candidate && isSubtype(other, candidate) }
        }
        return mostSpecific
    }

    private func commonNominalSupertype(_ types: [TypeID]) -> TypeID? {
        var ancestorSets: [Set<SymbolID>] = []
        for input in types {
            guard case let .classType(classType) = kind(of: input) else { return nil }
            var ancestors: Set<SymbolID> = [classType.classSymbol]
            var queue = directNominalSupertypes(for: classType.classSymbol)
            while let symbol = queue.popLast() {
                if ancestors.insert(symbol).inserted {
                    queue.append(contentsOf: directNominalSupertypes(for: symbol))
                }
            }
            ancestorSets.append(ancestors)
        }
        guard var common = ancestorSets.first else { return nil }
        for rest in ancestorSets.dropFirst() {
            common.formIntersection(rest)
        }
        var candidates: Set<TypeID> = []
        for ancestor in common {
            var argumentLists: [[TypeArg]] = []
            var hasExistingCandidate = false
            for input in types {
                guard case let .classType(classType) = kind(of: input),
                      let lifted = liftedNominalSupertypeArgs(
                          from: classType,
                          to: ancestor
                      )
                else {
                    continue
                }
                argumentLists.append(lifted)
                let candidate = make(.classType(self.classType(
                    for: ancestor, arguments: lifted, nullability: .nonNull
                )))
                if !candidates.contains(candidate), types.allSatisfy({ isSubtype($0, candidate) }) {
                    candidates.insert(candidate)
                    hasExistingCandidate = true
                }
            }
            if !hasExistingCandidate, argumentLists.count == types.count,
               let combined = combinedCovariantNominalSupertype(
                   ancestor, argumentLists: argumentLists, inputs: types
               )
            {
                candidates.insert(combined)
            }
        }
        let best = Set(candidates.filter { candidate in candidates.allSatisfy { isSubtype(candidate, $0) } })
        return best.count == 1 ? best.first : nil
    }

    private func combinedCovariantNominalSupertype(
        _ symbol: SymbolID,
        argumentLists: [[TypeArg]],
        inputs: [TypeID]
    ) -> TypeID? {
        guard let first = argumentLists.first,
              argumentLists.allSatisfy({ $0.count == first.count })
        else { return nil }

        let inputSet = Set(inputs)
        guard activeNominalLUBInputs.count < Self.maxNominalLUBDepth,
              activeNominalLUBInputs.insert(inputSet).inserted
        else { return nil }
        defer { activeNominalLUBInputs.remove(inputSet) }

        let enclosingParameterCount = enclosingTypeParameterSymbols(for: symbol).count
        let fallbackArity = max(0, first.count - enclosingParameterCount)
        let variances = allTypeParameterVariances(for: symbol, fallbackArity: fallbackArity)
        let isArray = symbol == arrayClassSymbol
        var combined: [TypeArg] = []
        for index in first.indices {
            let arguments = argumentLists.map { $0[index] }
            if arguments.allSatisfy({ $0 == first[index] }) {
                combined.append(first[index])
                continue
            }
            var upperBounds: [TypeID] = []
            for argument in arguments {
                if isArray {
                    switch argument {
                    case let .invariant(bound), let .out(bound):
                        upperBounds.append(bound)
                    case .in, .star:
                        return nil
                    }
                } else {
                    let declarationVariance = variances.indices.contains(index)
                        ? variances[index]
                        : .invariant
                    switch composedProjection(
                        declarationVariance: declarationVariance, useSite: argument
                    ) {
                    case let .out(bound), let .invariant(bound):
                        upperBounds.append(bound)
                    case .in, .star, .invalid:
                        return nil
                    }
                }
            }
            combined.append(.out(lub(upperBounds)))
        }
        let candidate = make(.classType(classType(
            for: symbol, arguments: combined, nullability: .nonNull
        )))
        return inputs.allSatisfy({ isSubtype($0, candidate) }) ? candidate : nil
    }

    private func functionNArity(of classSymbol: SymbolID) -> Int? {
        for (arity, symbolID) in functionNInterfaceSymbols where symbolID == classSymbol {
            return arity
        }
        return nil
    }

    private func suspendFunctionNArity(of classSymbol: SymbolID) -> Int? {
        for (arity, symbolID) in suspendFunctionNInterfaceSymbols where symbolID == classSymbol {
            return arity
        }
        return nil
    }

    private func functionInterfaceArity(of classSymbol: SymbolID, isSuspend: Bool) -> Int? {
        isSuspend ? suspendFunctionNArity(of: classSymbol) : functionNArity(of: classSymbol)
    }

    func nominalFunctionInterfaceShape(of classSymbol: SymbolID) -> (arity: Int, isSuspend: Bool)? {
        if let arity = functionNArity(of: classSymbol) {
            return (arity, false)
        }
        if let arity = suspendFunctionNArity(of: classSymbol) {
            return (arity, true)
        }
        return nil
    }

    func uniqueStructuralFunctionType(for type: TypeID) -> FunctionType? {
        var visitedTypeParameters: Set<SymbolID> = []
        return uniqueStructuralFunctionType(for: type, visitedTypeParameters: &visitedTypeParameters)
    }

    private func uniqueStructuralFunctionType(
        for type: TypeID,
        visitedTypeParameters: inout Set<SymbolID>
    ) -> FunctionType? {
        func upperBoundsContributed(by parameter: TypeParamType) -> [TypeID] {
            guard visitedTypeParameters.insert(parameter.symbol).inserted else {
                return []
            }
            if let capture = parameter.capture {
                return [capture.upper]
            }
            return declaredUpperBounds(for: parameter.symbol)
        }
        switch kind(of: type) {
        case let .functionType(function):
            return function
        case let .typeParam(parameter):
            return uniqueStructuralFunctionType(
                among: upperBoundsContributed(by: parameter),
                visitedTypeParameters: &visitedTypeParameters
            )
        case let .intersection(parts):
            return uniqueStructuralFunctionType(
                among: parts,
                visitedTypeParameters: &visitedTypeParameters
            )
        default:
            return nil
        }
    }

    private func uniqueStructuralFunctionType(
        among parts: [TypeID],
        visitedTypeParameters: inout Set<SymbolID>
    ) -> FunctionType? {
        var found: FunctionType?
        var pending = parts
        while let part = pending.popLast() {
            switch kind(of: makeNonNullable(part)) {
            case let .functionType(partFunction):
                if let existing = found, existing != partFunction {
                    return nil
                }
                found = partFunction
            case let .intersection(nested):
                pending.append(contentsOf: nested)
            case let .typeParam(parameter):
                guard visitedTypeParameters.insert(parameter.symbol).inserted else {
                    continue
                }
                if let capture = parameter.capture {
                    pending.append(capture.upper)
                } else {
                    pending.append(contentsOf: declaredUpperBounds(for: parameter.symbol))
                }
            default:
                break
            }
        }
        return found
    }

    func nominalFunctionType(for type: TypeID) -> FunctionType? {
        guard case let .classType(classType) = kind(of: type) else {
            return nil
        }
        let isSuspend = suspendFunctionNArity(of: classType.classSymbol) != nil
        if let arity = functionInterfaceArity(of: classType.classSymbol, isSuspend: isSuspend),
           classType.args.count == arity + 1
        {
            return nominalFunctionType(for: classType, arity: arity, isSuspend: isSuspend)
        }
        let directSupertypes = directNominalSupertypes(for: classType.classSymbol)
        guard let kFunctionInterfaceSymbol,
              directSupertypes.contains(kFunctionInterfaceSymbol)
        else {
            return nil
        }
        for supertype in directSupertypes {
            guard let shape = nominalFunctionInterfaceShape(of: supertype),
                  let arguments = liftedNominalSupertypeArgs(from: classType, to: supertype)
            else {
                continue
            }
            let inheritedType = self.classType(
                for: supertype,
                arguments: arguments,
                nullability: classType.nullability
            )
            return nominalFunctionType(for: inheritedType, arity: shape.arity, isSuspend: shape.isSuspend)
        }
        return nil
    }

    private func nominalFunctionType(
        for classType: ClassType,
        arity: Int,
        isSuspend: Bool
    ) -> FunctionType? {
        let projectedArguments = substitutingCovariantStarUpperBounds(
            classType.args,
            for: classType.classSymbol
        )
        var arguments: [TypeID] = []
        arguments.reserveCapacity(projectedArguments.count)
        for (index, argument) in projectedArguments.enumerated() {
            switch argument {
            case let .invariant(type):
                arguments.append(type)
            case let .in(type) where index < arity:
                arguments.append(type)
            case let .out(type) where index == arity:
                arguments.append(type)
            default:
                return nil
            }
        }
        guard arguments.count == arity + 1 else { return nil }
        return FunctionType(
            params: Array(arguments.prefix(arity)),
            returnType: arguments[arity],
            isSuspend: isSuspend,
            nullability: classType.nullability
        )
    }

    func inheritedFunctionInterfaceClassType(
        of classType: ClassType,
        arity: Int,
        isSuspend: Bool
    ) -> ClassType? {
        var visited: Set<SymbolID> = [classType.classSymbol]
        var queue = directNominalSupertypes(for: classType.classSymbol)
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            guard visited.insert(current).inserted else { continue }
            if functionInterfaceArity(of: current, isSuspend: isSuspend) == arity,
               let args = liftedNominalSupertypeArgs(
                   from: classType,
                   to: current
               )
            {
                return self.classType(for: current, arguments: args, nullability: classType.nullability)
            }
            queue.append(contentsOf: directNominalSupertypes(for: current))
        }
        return nil
    }

    func inheritedFunctionNClassType(of classType: ClassType, arity: Int) -> ClassType? {
        inheritedFunctionInterfaceClassType(of: classType, arity: arity, isSuspend: false)
    }

    private func functionTypeSubtypeOfFunctionN(
        _ function: FunctionType,
        _ classType: ClassType
    ) -> Bool {
        guard let arity = functionInterfaceArity(of: classType.classSymbol, isSuspend: function.isSuspend),
              nullabilitySubtype(function.nullability, classType.nullability)
        else {
            return false
        }
        let effectiveParams = function.contextReceivers
            + (function.receiver.map { [$0] } ?? []) + function.params
        guard effectiveParams.count == arity,
              classType.args.count == arity + 1
        else {
            return false
        }
        for (index, param) in effectiveParams.enumerated() {
            switch classType.args[index] {
            case .star:
                continue
            case let .invariant(type), let .in(type):
                guard isSubtype(type, param) else { return false }
            case let .out(type):
                guard isSubtype(param, type) else { return false }
            }
        }
        switch classType.args[arity] {
        case .star:
            return true
        case let .invariant(type), let .out(type):
            return isSubtype(function.returnType, type)
        case let .in(type):
            return isSubtype(type, function.returnType)
        }
    }

    private func functionNSubtypeOfFunctionType(
        _ classType: ClassType,
        _ function: FunctionType
    ) -> Bool {
        guard let arity = functionInterfaceArity(of: classType.classSymbol, isSuspend: function.isSuspend),
              nullabilitySubtype(classType.nullability, function.nullability)
        else {
            return false
        }
        let effectiveParams = function.contextReceivers
            + (function.receiver.map { [$0] } ?? []) + function.params
        guard effectiveParams.count == arity,
              classType.args.count == arity + 1
        else {
            return false
        }
        for (index, param) in effectiveParams.enumerated() {
            switch classType.args[index] {
            case let .invariant(type), let .in(type):
                guard isSubtype(param, type) else { return false }
            case .star, .out:
                return false
            }
        }
        switch classType.args[arity] {
        case let .invariant(type), let .out(type):
            return isSubtype(type, function.returnType)
        case .star, .in:
            return false
        }
    }

    private func isNumericPrimitiveType(_ type: TypeID) -> Bool {
        guard case let .primitive(primitive, _) = kind(of: type) else { return false }
        switch primitive {
        case .int, .long, .float, .double, .byte, .short:
            return true
        default:
            return false
        }
    }

    private func lubKClassTypes(_ filtered: [TypeID]) -> TypeID? {
        var arguments: [TypeID] = []
        var invariantArguments = true
        var hasNullable = false
        for typeID in filtered {
            switch kind(of: typeID) {
            case let .kClassType(kc):
                arguments.append(kc.argument)
            case let .classType(ct) where ct.classSymbol == kClassInterfaceSymbol && ct.args.count == 1:
                switch ct.args[0] {
                case let .invariant(argument): arguments.append(argument)
                case let .out(argument):
                    invariantArguments = false
                    arguments.append(argument)
                case .in, .star:
                    invariantArguments = false
                    arguments.append(anyType)
                }
            default:
                return nil
            }
            if nullability(of: typeID) != .nonNull {
                hasNullable = true
            }
        }
        guard !arguments.isEmpty else { return nil }
        let resultNullability: Nullability = hasNullable ? .nullable : .nonNull
        if let existing = filtered.first(where: { candidate in
            filtered.allSatisfy { isSubtype($0, candidate) }
        }) {
            return withNullability(resultNullability, for: existing)
        }
        let argLub = lub(arguments)
        if invariantArguments,
           arguments.allSatisfy({ isSubtype($0, arguments[0]) && isSubtype(arguments[0], $0) }) {
            return makeKClassType(argument: arguments[0], nullability: resultNullability)
        }
        guard let kClassInterfaceSymbol else {
            return withNullability(resultNullability, for: anyType)
        }
        return make(.classType(ClassType(
            classSymbol: kClassInterfaceSymbol,
            args: [.out(argLub)],
            nullability: resultNullability
        )))
    }

}
