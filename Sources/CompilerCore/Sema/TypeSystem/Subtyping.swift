extension TypeSystem {
    public func isSubtype(_ subtype: TypeID, _ supertype: TypeID) -> Bool {
        let (subtype, lhs) = normalizedBuiltinDisguisedClassTypeAndKind(subtype)
        let (supertype, rhs) = normalizedBuiltinDisguisedClassTypeAndKind(supertype)
        if subtype == supertype {
            return true
        }

        if case .nothing(.nonNull) = lhs {
            return true
        }
        if case .nothing(.nullable) = lhs {
            // Nothing? is subtype of all nullable and platform types, Any?, and Nothing? itself
            switch rhs {
            case .nullableUnit:
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
        if lhs == .unit, rhs == .nullableUnit {
            return true
        }
        // Subtype of intersection: C <: A & B if C <: all parts
        // (must come before LHS decomposition so that intersection-vs-intersection
        //  decomposes the RHS first, allowing each part to then match via LHS rule)
        if case let .intersection(parts) = rhs {
            return parts.allSatisfy { isSubtype(subtype, $0) }
        }
        // Intersection as subtype: A & B <: C if any part <: C
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
            case .any(.nonNull), .any(.platformType), .unit, .nothing(.nonNull):
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

        // primitive <: Comparable<same_primitive>
        // All Kotlin primitive types (Int, Long, Double, Float, Char, Boolean, etc.) implement Comparable<Self>.
        if case let .primitive(_, leftNullability) = lhs,
           case let .classType(rightClass) = rhs,
           let comparableSym = comparableInterfaceSymbol,
           rightClass.classSymbol == comparableSym,
           rightClass.args.count == 1,
           case let .in(argType) = rightClass.args[0],
           argType == subtype,
           nullabilitySubtype(leftNullability, rightClass.nullability)
        {
            return true
        }

        // primitive / String <: Comparable<*>: the star projection erases the
        // type argument, so every Comparable<Self> primitive satisfies it.
        if case let .classType(rightClass) = rhs,
           let comparableSym = comparableInterfaceSymbol,
           rightClass.classSymbol == comparableSym,
           rightClass.args.count == 1,
           case .star = rightClass.args[0]
        {
            switch lhs {
            case let .primitive(_, leftNullability):
                if nullabilitySubtype(leftNullability, rightClass.nullability) { return true }
            case let .stringStruct(leftNullability):
                if nullabilitySubtype(leftNullability, rightClass.nullability) { return true }
            default:
                break
            }
        }

        // Support for invariant Comparable bounds (backward compatibility)
        if case let .primitive(_, leftNullability) = lhs,
           case let .classType(rightClass) = rhs,
           let comparableSym = comparableInterfaceSymbol,
           rightClass.classSymbol == comparableSym,
           rightClass.args.count == 1,
           case let .invariant(argType) = rightClass.args[0],
           argType == subtype,
           nullabilitySubtype(leftNullability, rightClass.nullability)
        {
            return true
        }

        // String is an aggregate value in the compiler, but it remains a
        // source-level kotlin.String and implements Comparable<String>.
        if case let .stringStruct(leftNullability) = lhs,
           case let .classType(rightClass) = rhs,
           let comparableSym = comparableInterfaceSymbol,
           rightClass.classSymbol == comparableSym,
           rightClass.args.count == 1,
           nullabilitySubtype(leftNullability, rightClass.nullability)
        {
            switch rightClass.args[0] {
            case let .in(argType), let .invariant(argType):
                return argType == subtype
            case .star:
                return true
            case .out:
                return false
            }
        }

        // primitive <: Number  (Int, Long, Float, Double, Byte, Short are subclasses of kotlin.Number)
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
            if leftClass.classSymbol != rightClass.classSymbol {
                guard isNominalSubtypeSymbol(leftClass.classSymbol, of: rightClass.classSymbol) else {
                    return false
                }
                let mappedArgs = liftedNominalSupertypeArgs(
                    from: leftClass.classSymbol,
                    childArgs: leftClass.args,
                    to: rightClass.classSymbol
                ) ?? []
                if mappedArgs.count == rightClass.args.count, !mappedArgs.isEmpty {
                    let liftedSupertype = make(.classType(ClassType(
                        classSymbol: rightClass.classSymbol,
                        args: mappedArgs,
                        nullability: leftClass.nullability
                    )))
                    return isSubtype(liftedSupertype, supertype)
                }
                return rightClass.args.isEmpty || rightClass.args.allSatisfy { arg in
                    if case .star = arg {
                        return true
                    }
                    return false
                }
            }
            if leftClass.args.count != rightClass.args.count {
                return false
            }
            let declarationVariances = normalizedNominalVariances(
                for: leftClass.classSymbol,
                arity: leftClass.args.count
            )
            for index in 0 ..< leftClass.args.count {
                let lhsProjection = composedProjection(
                    declarationVariance: declarationVariances[index],
                    useSite: leftClass.args[index]
                )
                let rhsProjection = composedProjection(
                    declarationVariance: declarationVariances[index],
                    useSite: rightClass.args[index]
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
            // Kotlin allows a lambda literal wherever a Unit-returning function type
            // is expected regardless of the lambda's own inferred return type -- the
            // last expression's value is simply discarded (e.g. `repeat(3) { i ->
            // someCallReturningInt(i) }` passed to `action: (Int) -> Unit`). Skip the
            // return-type check in that case instead of requiring true subtyping.
            if rightFunction.returnType == unitType {
                return true
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
            }
            // Only callable references implement the reflective KFunction interface.
            guard rightClass.classSymbol == functionInterfaceSymbol
                || (leftFunction.isCallableReference
                    && (rightClass.classSymbol == kFunctionInterfaceSymbol
                        || rightClass.classSymbol == kCallableInterfaceSymbol))
            else {
                // KUU-1084: `(P1..PN) -> R` also conforms to the synthetic
                // `kotlin.Function.FunctionN` interface of matching arity.
                return functionTypeSubtypeOfFunctionN(leftFunction, rightClass)
            }
            guard nullabilitySubtype(leftFunction.nullability, rightClass.nullability) else {
                return false
            }
            // KFunction<R> has one type arg (the return type). Accept if none specified or return
            // type matches.
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
            // SAM: fun interface <: function type when the SAM method signature matches
            guard nullabilitySubtype(leftClass.nullability, rightFunction.nullability) else {
                return false
            }
            // KUU-1084: `FunctionN<P1..PN, R>` IS `(P1..PN) -> R` in Kotlin —
            // the nominal form is a subtype of the equivalent function type.
            if functionNArity(of: leftClass.classSymbol) != nil {
                return functionNSubtypeOfFunctionType(leftClass, rightFunction)
            }
            // KUU-1195: a nominal type that reaches `FunctionN` through
            // inheritance (e.g. the bundled `KProperty0/1/2` interfaces, whose
            // `() -> V` / `(T) -> V` / `(D, E) -> V` supertypes are bound to
            // `Function0/1/2` during inheritance resolution) is likewise a
            // subtype of the matching function type.
            if let liftedFunctionN = inheritedFunctionNClassType(
                of: leftClass,
                arity: (rightFunction.receiver.map { [$0] } ?? []).count + rightFunction.params.count
            ), functionNSubtypeOfFunctionType(liftedFunctionN, rightFunction) {
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

        // KClass<T> is covariant in T, matching Kotlin's `KClass<out T : Any>`.
        case let (.kClassType(leftKClass), .kClassType(rightKClass)):
            guard nullabilitySubtype(leftKClass.nullability, rightKClass.nullability) else {
                return false
            }
            return isSubtype(leftKClass.argument, rightKClass.argument)

        case let (.kClassType(leftKClass), .classType(rightClass)):
            guard let kClassSymbol = kClassInterfaceSymbol,
                  nullabilitySubtype(leftKClass.nullability, rightClass.nullability)
            else {
                return false
            }
            if rightClass.classSymbol == kClassSymbol {
                if rightClass.args.isEmpty { return true }
                guard rightClass.args.count == 1 else { return false }
                switch rightClass.args[0] {
                case .star:
                    return true
                case let .out(type), let .invariant(type):
                    return isSubtype(leftKClass.argument, type)
                case .in:
                    return true
                }
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
                if leftClass.args.isEmpty { return isSubtype(anyType, rightKClass.argument) }
                guard leftClass.args.count == 1 else { return false }
                switch leftClass.args[0] {
                case .star:
                    return isSubtype(anyType, rightKClass.argument)
                case let .out(type), let .invariant(type):
                    return isSubtype(type, rightKClass.argument)
                case let .in(type):
                    return isSubtype(type, rightKClass.argument)
                }
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
    /// existed. A no-op for every other type.
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
            lubReapplyingNullability(filtered)
        }
        // If any input was Nothing? (null literal), the result must be nullable
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

    /// Retains a common `Comparable<*>` while inferring from lower bounds.
    ///
    /// `lub` intentionally keeps its conservative `Any` fallback for callers
    /// that need the existing nominal-only behavior. This is deliberately not
    /// a general common-supertype search: generic argument inference only
    /// retains the platform-neutral built-in interface needed for mixed
    /// comparable values. Other nominal LUB work remains with `lub`.
    func inferenceLubRetainingCommonComparable(_ types: [TypeID]) -> TypeID {
        let fallback = lub(types)
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
        // Platform type (T!) is assignable to both nullable and non-null
        if lhs == .platformType { return true }
        // Both nullable and non-null are assignable to platform type
        if rhs == .platformType { return true }
        return false
    }

    func isNominalSubtypeSymbol(_ candidate: SymbolID, of base: SymbolID) -> Bool {
        if candidate == base {
            return true
        }
        var queue = directNominalSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while let current = queue.first {
            queue.removeFirst()
            if current == base {
                return true
            }
            if visited.insert(current).inserted {
                queue.append(contentsOf: directNominalSupertypes(for: current))
            }
        }
        return false
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

    /// Computes the LUB over the non-null projections of `filtered` and
    /// re-applies nullability if any input was nullable. When the non-null
    /// projections share a single underlying type (e.g. `String` and
    /// `String?`), the result is that type made nullable (`String?`) rather
    /// than being widened to `Any?`.
    private func lubReapplyingNullability(_ filtered: [TypeID]) -> TypeID {
        let anyNullable = filtered.contains { nullability(of: $0) == .nullable }
        let nonNull = filtered.map { makeNonNullable($0) }
        let base: TypeID
        if let firstNonNull = nonNull.first, nonNull.dropFirst().allSatisfy({ $0 == firstNonNull }) {
            base = firstNonNull
        } else if let kClassLub = lubKClassTypes(nonNull) {
            base = kClassLub
        } else if let commonSupertype = nearestCommonSupertype(nonNull) {
            base = commonSupertype
        } else {
            base = anyType
        }
        return anyNullable ? makeNullable(base) : base
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
    ///
    /// Returns `nil` when none of the shapes apply, leaving the caller to fall
    /// back to `Any`.
    private func nearestCommonSupertype(_ types: [TypeID]) -> TypeID? {
        if let dominating = types.first(where: { candidate in types.allSatisfy { isSubtype($0, candidate) } }) {
            return dominating
        }
        if let numberSym = numberClassSymbol, types.allSatisfy(isNumericPrimitiveType) {
            return make(.classType(ClassType(classSymbol: numberSym, args: [], nullability: .nonNull)))
        }
        // Prefer the strict result (unique most-specific ancestor with agreeing type
        // arguments); fall back to the BFS approximation when several incomparable
        // candidates remain.
        return commonNominalSupertype(types) ?? nearestCommonNominalSupertype(types)
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
    /// Among the survivors, candidates that are strict supertypes of another
    /// survivor are dropped, and a superclass is preferred over an interface.
    ///
    /// Kotlin infers an intersection type when several incomparable candidates
    /// remain (e.g. two classes implementing both `I` and `J`). This compiler
    /// has no denotable intersection for inferred variables, so it
    /// approximates with the first surviving candidate in breadth-first order
    /// (nominal supertypes are stored sorted by symbol ID, so the
    /// choice is deterministic). Members of the other candidates are not
    /// visible on the result.
    private func nearestCommonNominalSupertype(_ types: [TypeID]) -> TypeID? {
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
                from: first.classSymbol,
                childArgs: first.args,
                to: ancestor
            ) ?? []
            let candidate = make(.classType(ClassType(classSymbol: ancestor, args: args, nullability: .nonNull)))
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
        let isInterface: (TypeID) -> Bool = { [self] candidate in
            guard case let .classType(classType) = kind(of: candidate) else { return false }
            return symbolTable?.symbol(classType.classSymbol)?.kind == .interface
        }
        return mostSpecific.first(where: { !isInterface($0) }) ?? mostSpecific.first
    }

    /// Nominal hierarchy walk for inputs that are all nominal class types
    /// where no input dominates the rest — e.g.
    /// `lub(EmptyCoroutineContext, Element) == CoroutineContext`: neither
    /// input is a supertype of the other, but they share
    /// `CoroutineContext` above them. Collects the ancestor symbols
    /// reachable from every input, keeps those whose substituted type args
    /// agree across all inputs, and returns the single most specific
    /// candidate (a subtype of every other candidate). Returns `nil` for
    /// non-class inputs, disagreeing args, or ambiguity — the caller then
    /// falls back to `Any`, so this can only tighten results that would
    /// otherwise widen to `Any`.
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
        var candidates: [TypeID] = []
        for ancestor in common {
            var args: [TypeArg]?
            var agrees = true
            for input in types {
                guard case let .classType(classType) = kind(of: input),
                      let lifted = liftedNominalSupertypeArgs(
                          from: classType.classSymbol,
                          childArgs: classType.args,
                          to: ancestor
                      )
                else {
                    agrees = false
                    break
                }
                if let prev = args, prev != lifted {
                    agrees = false
                    break
                }
                args = args ?? lifted
            }
            guard agrees, let args else { continue }
            candidates.append(make(.classType(ClassType(classSymbol: ancestor, args: args, nullability: .nonNull))))
        }
        let best = Set(candidates.filter { candidate in candidates.allSatisfy { isSubtype(candidate, $0) } })
        return best.count == 1 ? best.first : nil
    }

    /// Arity of `kotlin.Function.FunctionN` when `classSymbol` is one of the
    /// synthetic function interfaces registered by
    /// `registerSyntheticFunctionInterface` (KUU-1084).
    private func functionNArity(of classSymbol: SymbolID) -> Int? {
        for (arity, symbolID) in functionNInterfaceSymbols where symbolID == classSymbol {
            return arity
        }
        return nil
    }

    func nominalFunctionType(for type: TypeID) -> FunctionType? {
        guard case let .classType(classType) = kind(of: type),
              let arity = functionNArity(of: classType.classSymbol),
              classType.args.count == arity + 1
        else {
            return nil
        }
        let arguments = classType.args.enumerated().compactMap { index, argument -> TypeID? in
            switch argument {
            case let .invariant(type):
                return type
            case let .in(type) where index < arity:
                return type
            case let .out(type) where index == arity:
                return type
            default:
                return nil
            }
        }
        guard arguments.count == arity + 1 else { return nil }
        return FunctionType(
            params: Array(arguments.prefix(arity)),
            returnType: arguments[arity],
            nullability: classType.nullability
        )
    }

    /// Lifts a nominal class type to the `kotlin.Function.FunctionN`
    /// interface of the given arity that it reaches through its nominal
    /// supertype chain (e.g. `KProperty0<Int>` → `Function0<Int>` via the
    /// `() -> V` supertype binding — KUU-1195), preserving the declared
    /// projections and the subtype's nullability. `nil` when no `FunctionN`
    /// ancestor of that arity exists. The walk mirrors
    /// `isNominalSubtypeSymbol`: an explicit worklist with a visited set so a
    /// cyclic `.kklib` supertype graph cannot loop.
    func inheritedFunctionNClassType(of classType: ClassType, arity: Int) -> ClassType? {
        var visited: Set<SymbolID> = [classType.classSymbol]
        var queue = directNominalSupertypes(for: classType.classSymbol)
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            if functionNArity(of: current) == arity,
               let args = liftedNominalSupertypeArgs(
                   from: classType.classSymbol,
                   childArgs: classType.args,
                   to: current
               )
            {
                return ClassType(
                    classSymbol: current,
                    args: args,
                    nullability: classType.nullability
                )
            }
            queue.append(contentsOf: directNominalSupertypes(for: current))
        }
        return nil
    }

    /// `(Q1..QN) -> S <: FunctionN<A1..AN, B>`: the receiver counts as the
    /// leading parameter, arity must match, each `in` argument accepts the
    /// parameter (`Ai <: Qi`), and the return type satisfies the `out` argument
    /// (`S <: B`). `suspend` and context-receiver function types never conform
    /// to the non-suspend `FunctionN` interfaces.
    private func functionTypeSubtypeOfFunctionN(
        _ function: FunctionType,
        _ classType: ClassType
    ) -> Bool {
        guard let arity = functionNArity(of: classType.classSymbol),
              function.contextReceivers.isEmpty,
              !function.isSuspend,
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

    /// `FunctionN<A1..AN, B> <: (Q1..QN) -> S`: arity must match, each
    /// parameter of the expected function type must be accepted by the
    /// nominal `in` argument (`Qi <: Ai`), and the nominal `out` return must
    /// fit the expected return (`B <: S`). Star or opposite-direction
    /// projections cannot prove either bound, so they are rejected.
    private func functionNSubtypeOfFunctionType(
        _ classType: ClassType,
        _ function: FunctionType
    ) -> Bool {
        guard let arity = functionNArity(of: classType.classSymbol),
              function.contextReceivers.isEmpty,
              !function.isSuspend,
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

    /// If **all** types in `filtered` are `KClass<…>`, compute
    /// `KClass<lub(T1, T2, …)>` with the appropriate nullability.
    /// Returns `nil` when the types are not all KClass.
    private func lubKClassTypes(_ filtered: [TypeID]) -> TypeID? {
        var arguments: [TypeID] = []
        var hasNullable = false
        for typeID in filtered {
            guard case let .kClassType(kc) = kind(of: typeID) else {
                return nil
            }
            arguments.append(kc.argument)
            if kc.nullability == .nullable || kc.nullability == .platformType {
                hasNullable = true
            }
        }
        guard !arguments.isEmpty else { return nil }
        let argLub = lub(arguments)
        let resultNullability: Nullability = hasNullable ? .nullable : .nonNull
        return makeKClassType(argument: argLub, nullability: resultNullability)
    }

}
