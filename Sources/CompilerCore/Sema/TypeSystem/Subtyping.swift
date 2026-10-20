extension TypeSystem {
    public func isSubtype(_ subtype: TypeID, _ supertype: TypeID) -> Bool {
        let (subtype, lhs) = normalizedBuiltinDisguisedClassTypeAndKind(subtype)
        let (supertype, rhs) = normalizedBuiltinDisguisedClassTypeAndKind(supertype)
        if subtype == supertype {
            return true
        }

        // A captured parameter is readable through its upper bound and accepts
        // only values below its lower bound. It is never equal to either bound.
        if case let .typeParam(left) = lhs, case let .typeParam(right) = rhs,
           let capture = left.capture, capture == right.capture
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
            // Any! accepts all types (platform type has unknown nullability)
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

        // Treat Kotlin String as a subtype of kotlin.CharSequence so that
        // the synthetic CharSequence overloads can reuse the String runtime ABI.
        if case let .stringStruct(lhsNullability) = lhs,
           case let .classType(rhsClass) = rhs,
           let charSequenceSym = charSequenceInterfaceSymbol,
           rhsClass.classSymbol == charSequenceSym
        {
            return nullabilitySubtype(lhsNullability, rhsClass.nullability)
        }

        // STDLIB-030-BUG-01: A type parameter T is a subtype of its upper bounds.
        // This allows `T : AutoCloseable` (which stores `Closeable` as its bound after
        // typealias expansion) to satisfy `T <: Closeable` in the constraint solver and
        // member-lookup paths.
        if case let .typeParam(typeParam) = lhs,
           let symbols = symbolTable
        {
            let upperBounds = symbols.typeParameterUpperBounds(for: typeParam.symbol)
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
            // We do not return false here, as it might be a subtype through normal inheritance
            // if Annotation was explicitly added to supertypes.
        }

        // primitive / String <: Comparable<Self>, and both satisfy
        // Comparable<*>: all Kotlin primitive types (Int, Long, Double, Float,
        // Char, Boolean, etc.) implement Comparable<Self>, and String is an
        // aggregate value in the compiler but remains a source-level
        // kotlin.String implementing Comparable<String>. A star projection
        // erases the type argument, so every Comparable<Self> type satisfies it.
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
                    // Nullable values still implement Comparable of non-null Self.
                    // Outer nullability was checked above; retain argument nullability.
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
            // Matching expect/actual declarations have distinct symbols, but
            // their class types represent the same nominal Kotlin type.
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
            // Star and in-projected KClass types still read through the Any
            // upper bound, including synthetic declarations without bound metadata.
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
                        ? symbolTable?.typeParameterUpperBounds(for: typeParameterSymbols[index]) ?? [] : []
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
                    // Recursive stars and in-projected dependencies need a
                    // captured type; an in projection supplies only a lower
                    // bound. Keep the conservative path for these cases.
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
            guard leftFunction.contextReceivers.count == rightFunction.contextReceivers.count else {
                return false
            }
            // Kotlin treats a receiver as the leading function parameter,
            // including for unbound suspend callable references.
            let leftParams = (leftFunction.receiver.map { [$0] } ?? []) + leftFunction.params
            let rightParams = (rightFunction.receiver.map { [$0] } ?? []) + rightFunction.params
            guard leftParams.count == rightParams.count else {
                return false
            }
            guard leftFunction.isSuspend == rightFunction.isSuspend else {
                return false
            }
            guard nullabilitySubtype(leftFunction.nullability, rightFunction.nullability) else {
                return false
            }
            for (leftContextReceiver, rightContextReceiver) in zip(leftFunction.contextReceivers, rightFunction.contextReceivers) {
                // swiftlint:disable:next for_where
                if !isSubtype(rightContextReceiver, leftContextReceiver) {
                    return false
                }
            }
            for (leftParam, rightParam) in zip(leftParams, rightParams) where !isSubtype(rightParam, leftParam) {
                return false
            }
            // Lambda bodies and direct callable references apply Unit coercion
            // while being checked against their expected type. A function value
            // with another return type is not itself a subtype of a Unit function.
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
            }
            // Only callable references implement the reflective KFunction interface.
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
            // KFunction<R> has one type arg (the return type).
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
            // KUU-1084: `FunctionN<P1..PN, R>` IS `(P1..PN) -> R` in Kotlin —
            // the nominal form is a subtype of the equivalent function type.
            if functionInterfaceArity(of: leftClass.classSymbol, isSuspend: rightFunction.isSuspend) != nil {
                return functionNSubtypeOfFunctionType(leftClass, rightFunction)
            }
            // KUU-1195: a nominal type that reaches a function interface
            // through inheritance (e.g. KProperty0/1/2 or a fun interface
            // extending a function type) is also a subtype of that function
            // type when the suspend modifier and arity match.
            if let liftedFunctionInterface = inheritedFunctionInterfaceClassType(
                of: leftClass,
                arity: (rightFunction.receiver.map { [$0] } ?? []).count + rightFunction.params.count,
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
            let children = symbols.children(ofFQName: sym.fqName)
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

        // Kotlin declares KClass<T : Any> with an invariant type parameter.
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
        } else if case .typeParam = kind(of: first),
                  filtered.dropFirst().allSatisfy({ isSubtype($0, first) }) {
            // Preserve a declared common supertype such as `R` when a
            // self-type extension combines it with a bounded receiver `C`.
            first
        } else if let kClassLub = lubKClassTypes(filtered) {
            kClassLub
        } else {
            // Separate the nullability dimension from the underlying type:
            // compute the LUB over the non-null projections and re-apply
            // nullability when any input was nullable. This keeps
            // `lub(T, T?) == T?` instead of widening all the way to `Any?`.
            lubReapplyingNullability(filtered, retainingCommonIntersection: retainingCommonIntersection)
        }
        if hasNullableNothing {
            let nullable = makeNullable(result)
            // makeNullable returns the same ID for two reasons:
            // (a) the type is already nullable (e.g. Int?) — keep it as-is
            // (b) makeNullable is a genuine no-op (e.g. an intersection) — fall back to Any?
            if nullable == result {
                if isSubtype(nullableNothingType, result) {
                    return result // already nullable, Nothing? <: result
                }
                return nullableAnyType
            }
            return nullable
        }
        return result
    }

    /// Generic inference retains incomparable common nominal bounds as an
    /// intersection, declared shared type-parameter upper bounds, and the
    /// platform-neutral `Comparable<*>` bound for mixed comparable primitives.
    /// Ordinary expression LUBs keep their existing nominal approximation.
    func inferenceLubRetainingSharedSupertypes(_ types: [TypeID]) -> TypeID {
        let fallback = lub(types, retainingCommonIntersection: true)
        guard fallback == anyType || fallback == nullableAnyType else {
            return fallback
        }

        let filtered = types.filter {
            kind(of: $0) != .error
                && kind(of: $0) != .nothing(.nonNull)
                && kind(of: $0) != .nothing(.nullable)
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
        return comparable
    }

    private func inferenceLubRetainingCommonTypeParameterUpperBounds(_ types: [TypeID]) -> TypeID? {
        guard types.count > 1, let symbolTable else { return nil }

        var candidates: [TypeID] = []
        var pending = types
        var visitedParameters: Set<SymbolID> = []
        while let input = pending.popLast() {
            // `T & Any` (the non-null narrowing of `T`) contributes `T`'s
            // bounds to the shared-bound walk.
            guard let parameter = typeParamPart(of: input) else { continue }
            if let capture = parameter.capture {
                if !candidates.contains(capture.upper) {
                    candidates.append(capture.upper)
                }
                continue
            }
            guard visitedParameters.insert(parameter.symbol).inserted else { continue }

            for bound in symbolTable.typeParameterUpperBounds(for: parameter.symbol) {
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
                // `T & Any` only satisfies a candidate through `T`'s bounds —
                // its `Any` conjunct is a non-null marker, not a real bound.
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

        // Keep only the most specific shared bounds. An intersection retains
        // every independent common constraint while remaining a valid LUB.
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
            // Only return Nothing? if it is a valid lower bound (subtype of all inputs).
            // glb([Nothing?, Int]) → Nothing (non-null), since Nothing? is NOT <: Int.
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
        // A superclass edge may name an actual class while the use site names
        // its linked expect class.
        if candidate == base || areLinkedExpectActualClassSymbols(candidate, base) {
            return true
        }
        var queue = directNominalSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            if current == base || areLinkedExpectActualClassSymbols(current, base) {
                return true
            }
            if visited.insert(current).inserted {
                queue.append(contentsOf: directNominalSupertypes(for: current))
            }
        }
        return false
    }

    private func areLinkedExpectActualClassSymbols(_ lhs: SymbolID, _ rhs: SymbolID) -> Bool {
        guard let symbolTable else { return false }
        return symbolTable.actualSymbol(for: lhs) == rhs
            || symbolTable.actualSymbol(for: rhs) == lhs
            || actualTypeAliasTargetNominalSymbol(for: lhs, symbols: symbolTable) == rhs
            || actualTypeAliasTargetNominalSymbol(for: rhs, symbols: symbolTable) == lhs
    }

    private func actualTypeAliasTargetNominalSymbol(
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
        // The common bound being itself a null-capable type parameter (e.g.
        // `K, V : R` with unbounded `R`) already covers null — keep it as-is.
        if !anyMarkedNullable, isNullableCapableTypeParameter(base, visitedParameters: []) {
            return base
        }
        return makeNullable(base)
    }

    /// True when a `.typeParam` may hold `null`: a parameter written without
    /// `?` is still nullable-capable unless an upper bound is definitely
    /// non-null, since its implicit upper bound is `Any?`. `T : Any` (or any
    /// non-null bound, transitively) makes the parameter non-null again.
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
            guard let symbolTable, !visitedParameters.contains(parameter.symbol) else {
                // No bound metadata, or a cyclic bound: the implicit upper
                // bound is `Any?`, so assume the parameter can hold null.
                return true
            }
            bounds = symbolTable.typeParameterUpperBounds(for: parameter.symbol)
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

    /// The type parameter carried by `type`, looking through the `T & Any`
    /// intersection produced by definitely-non-null narrowing (`?:`,
    /// `x != null`). The parameter's declared bounds still drive the join.
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

    /// Finds a supertype of every element of `types` that is more specific
    /// than `Any`, without a full generic-hierarchy walk (the special-cased
    /// `isSubtype` rules for primitives don't expose a generic "supertypes
    /// of" query). Covers three shapes seen in practice:
    ///
    /// - One input is already a common supertype of the rest, e.g.
    ///   `lub(Int, Number) == Number`, even when `Number` only appears as
    ///   the *upper* bound context and never lands in this lower-bound pool
    ///   by itself (unlike the narrower, `.typeParam`-only check in `lub()`,
    ///   this accepts a dominating candidate of any kind).
    /// - All inputs are numeric primitives (`Int`, `Long`, `Float`,
    ///   `Double`, `Byte`, `Short`), whose only common ancestor besides
    ///   `Any` is `kotlin.Number` — e.g. `lub(Int, Long) == Number`, matching
    ///   kotlinc (`pick(1, 2L)` assigned to a `Number`-typed val).
    /// - All inputs are user/library class types whose nominal supertype
    ///   graphs share a class or interface other than `Any`, e.g.
    ///   `lub(X, Y) == I` for `class X : I` / `class Y : I`
    ///   (see `nearestCommonNominalSupertype`).
    /// - A type-parameter input declares a bound shared by every input, e.g.
    ///   `lub(T, Int) == Number` for `T : Number?` after taking the non-null
    ///   projections used by Elvis.
    ///
    /// Returns `nil` when none of the shapes apply, leaving the caller to fall
    /// back to `Any`.
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

    /// `nearestCommonSupertype` only receives non-null projections, so each
    /// bound is narrowed to its non-null view.
    private func nearestCommonTypeParameterUpperBound(_ types: [TypeID]) -> TypeID? {
        guard types.count > 1 else { return nil }

        var candidates: [TypeID] = []
        var pending = types
        var visitedParameters: Set<SymbolID> = []
        while let input = pending.popLast() {
            // `T & Any` contributes `T`'s bounds: it is `T`'s non-null view.
            guard let parameter = typeParamPart(of: input) else {
                continue
            }
            guard visitedParameters.insert(parameter.symbol).inserted else {
                continue
            }

            let bounds: [TypeID]
            if let capture = parameter.capture {
                bounds = [capture.upper]
            } else if let symbolTable {
                bounds = symbolTable.typeParameterUpperBounds(for: parameter.symbol)
            } else {
                continue
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

    /// Checks a non-null LUB projection through declared type-parameter bounds
    /// without changing ordinary subtype rules for nullable receivers.
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
        // `A & B <: X` holds when any conjunct does. Parameter conjuncts go
        // through this function — not `isSubtype` — so their declared bounds
        // are walked with the visited set that keeps cyclic bounds
        // (`T : U, U : T`) terminating.
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
        } else if let symbolTable {
            bounds = symbolTable.typeParameterUpperBounds(for: parameter.symbol)
        } else {
            return isSubtype(subtype, supertype)
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

    /// Function inputs are contravariant, so their common type is a greatest
    /// lower bound; function results are covariant and use LUB.
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
            // A function receiver is its leading invocation parameter. Use a
            // regular function shape so mixed receiver and parameter forms
            // share the same callable supertype and invocation lowering.
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

    /// Finds the most specific nominal supertype (other than `Any`) shared by
    /// every non-null class type in `types`.
    ///
    /// Candidates are the ancestors of the first input, visited breadth-first
    /// over `directNominalSupertypes` (an explicit worklist with a visited set,
    /// so a cyclic or attacker-shaped `.kklib` supertype graph cannot recurse
    /// or loop -- see KUU-809). Each candidate is instantiated with the type
    /// arguments the first input lifts to (`liftedNominalSupertypeArgs`) and is
    /// kept only if *every* input is a subtype of that instantiation, which
    /// rejects generic mismatches such as `Comparable<X>` vs `Comparable<Y>`.
    ///
    /// Kotlin infers an intersection type when several incomparable candidates
    /// remain (e.g. two classes implementing both `I` and `J`). Ordinary
    /// expression LUBs continue to approximate with one candidate; generic
    /// inference retains all candidates through `inferenceLubRetainingSharedSupertypes`.
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

    /// Returns every incomparable most-specific nominal supertype shared by
    /// the inputs. `nil` means the inputs are outside this nominal class walk;
    /// an empty array means the inputs are nominal but have no shared ancestor
    /// other than `Any`.
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

    /// Returns `nil` for non-class inputs, incompatible args, or ambiguity —
    /// the caller then uses the nearest-common-ancestor approximation.
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
                // A later branch may provide the common instantiation:
                // Result<R> accepts both Success<R> and Failure : Result<Nothing>.
                let candidate = make(.classType(self.classType(
                    for: ancestor, arguments: lifted, nullability: .nonNull
                )))
                if !candidates.contains(candidate), types.allSatisfy({ isSubtype($0, candidate) }) {
                    candidates.insert(candidate)
                    hasExistingCandidate = true
                }
            }
            // Retain existing instantiations (including Nothing-based branches)
            // before synthesizing a wider covariant argument.
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
        // Recursive supertypes may repeat the same inputs or grow their type
        // arguments at each step. Bound the additional recursion from argument
        // synthesis; at the limit, use the existing sound Any approximation.
        guard activeNominalLUBInputs.count < Self.maxNominalLUBDepth,
              activeNominalLUBInputs.insert(inputSet).inserted
        else { return nil }
        defer { activeNominalLUBInputs.remove(inputSet) }

        let variances = allTypeParameterVariances(for: symbol)
        var combined: [TypeArg] = []
        for index in first.indices {
            let arguments = argumentLists.map { $0[index] }
            if arguments.allSatisfy({ $0 == first[index] }) {
                combined.append(first[index])
                continue
            }
            var upperBounds: [TypeID] = []
            for argument in arguments {
                guard case let .out(bound) = composedProjection(
                    declarationVariance: variances[index], useSite: argument
                ) else { return nil }
                upperBounds.append(bound)
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

    func nominalFunctionType(for type: TypeID) -> FunctionType? {
        guard case let .classType(classType) = kind(of: type) else {
            return nil
        }
        let isSuspend = suspendFunctionNArity(of: classType.classSymbol) != nil
        guard let arity = functionInterfaceArity(of: classType.classSymbol, isSuspend: isSuspend),
              classType.args.count == arity + 1 else { return nil }
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

    /// The supertype walk mirrors `isNominalSubtypeSymbol`: an explicit
    /// worklist with a visited set so a cyclic `.kklib` supertype graph cannot
    /// loop.
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
              function.contextReceivers.isEmpty,
              nullabilitySubtype(function.nullability, classType.nullability)
        else {
            return false
        }
        let effectiveParams = (function.receiver.map { [$0] } ?? []) + function.params
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
                // `out` projection on an `in` position bounds the impl's
                // parameter above: accept only `Qi <: Ai`.
                guard isSubtype(param, type) else { return false }
            }
        }
        switch classType.args[arity] {
        case .star:
            return true
        case let .invariant(type), let .out(type):
            return isSubtype(function.returnType, type)
        case let .in(type):
            // `in` projection on the `out` position requires the impl's
            // return type to be a supertype of the bound.
            return isSubtype(type, function.returnType)
        }
    }

    private func functionNSubtypeOfFunctionType(
        _ classType: ClassType,
        _ function: FunctionType
    ) -> Bool {
        guard let arity = functionInterfaceArity(of: classType.classSymbol, isSuspend: function.isSuspend),
              function.contextReceivers.isEmpty,
              nullabilitySubtype(classType.nullability, function.nullability)
        else {
            return false
        }
        let effectiveParams = (function.receiver.map { [$0] } ?? []) + function.params
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
        // Preserve an existing common supertype, including an in-projected
        // lower bound, before approximating unrelated captures by their upper bounds.
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
