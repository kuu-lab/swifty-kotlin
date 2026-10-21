private func typeArgInnerType(_ arg: TypeArg) -> TypeID? {
    switch arg {
    case let .invariant(type), let .out(type), let .in(type):
        return type
    case .star:
        return nil
    }
}

private func starProjectionUpperBound(for type: TypeID, typeSystem: TypeSystem) -> TypeID {
    guard case let .typeParam(typeParam) = typeSystem.kind(of: type) else {
        return typeSystem.nullableAnyType
    }
    let upperBounds = typeSystem.declaredUpperBounds(for: typeParam.symbol)
    guard !upperBounds.isEmpty else {
        return typeSystem.nullableAnyType
    }
    return typeSystem.glb(upperBounds)
}

private func comparableArgument(of subtype: TypeID, typeSystem: TypeSystem) -> TypeID? {
    let nonNullSubtype = typeSystem.makeNonNullable(subtype)
    switch typeSystem.kind(of: nonNullSubtype) {
    case .primitive, .stringStruct:
        return nonNullSubtype
    case let .classType(classType):
        guard let comparableSymbol = typeSystem.comparableInterfaceSymbol,
              let supertypeArgs = typeSystem.liftedNominalSupertypeArgs(
                  from: classType,
                  to: comparableSymbol
              ),
              let comparableArg = supertypeArgs.first
        else {
            return nil
        }
        return typeArgInnerType(comparableArg)
    case let .typeParam(typeParam):
        guard let symbolTable = typeSystem.symbolTable,
              let comparableSymbol = typeSystem.comparableInterfaceSymbol
        else {
            return nil
        }
        for upperBound in symbolTable.typeParameterUpperBounds(for: typeParam.symbol) {
            guard case let .classType(boundClass) = typeSystem.kind(of: upperBound),
                  boundClass.classSymbol == comparableSymbol,
                  let comparableArg = boundClass.args.first,
                  let argument = typeArgInnerType(comparableArg)
            else {
                continue
            }
            return argument
        }
        return nil
    case let .intersection(parts):
        for part in parts {
            if let argument = comparableArgument(of: part, typeSystem: typeSystem) {
                return argument
            }
        }
        return nil
    default:
        return nil
    }
}

extension OverloadResolver {
    func buildParameterMapping(
        signature: FunctionSignature,
        callArgs: [CallArg],
        symbols: SymbolTable,
        typeSystem: TypeSystem,
        inheritedDefaultValues: [Bool]? = nil,
        isCallableArgument: ((Int) -> Bool)? = nil
    ) -> [Int: Int]? {
        let paramCount = signature.parameterTypes.count
        if paramCount == 0 {
            return callArgs.isEmpty ? [:] : nil
        }

        let hasDefaultValues = Self.normalizeFlags(inheritedDefaultValues ?? signature.valueParameterHasDefaultValues, count: paramCount)
        let isVararg = Self.normalizeFlags(signature.valueParameterIsVararg, count: paramCount)
        let paramNames = parameterNames(
            for: signature,
            symbols: symbols,
            count: paramCount
        )
        func isCallableLike(_ type: TypeID) -> Bool {
            if case .functionType = typeSystem.kind(of: type) {
                return true
            }
            return false
        }
        func trailingLambdaParameterIndex(for argIndex: Int) -> Int? {
            guard argIndex == callArgs.count - 1 else {
                return nil
            }
            if let isTrailing = callArgs[argIndex].isTrailingLambda {
                let lastParameter = paramCount - 1
                guard isTrailing, !isVararg[lastParameter],
                      !boundNonVarargParams.contains(lastParameter)
                else { return nil }
                return lastParameter
            }
            let argumentIsCallable = isCallableArgument?(argIndex) ?? isCallableLike(callArgs[argIndex].type)
            guard argumentIsCallable else { return nil }
            let remainingIndices = positionalCursor..<paramCount
            for paramIndex in remainingIndices.reversed() {
                guard isCallableLike(signature.parameterTypes[paramIndex]) else {
                    continue
                }
                if isVararg[paramIndex] || boundNonVarargParams.contains(paramIndex) {
                    continue
                }
                var satisfiesTrailingRequirements = true
                if paramIndex + 1 < paramCount {
                    for index in (paramIndex + 1)..<paramCount {
                        if isVararg[index] || boundNonVarargParams.contains(index) || hasDefaultValues[index] {
                            continue
                        }
                        satisfiesTrailingRequirements = false
                        break
                    }
                }
                if satisfiesTrailingRequirements {
                    return paramIndex
                }
            }
            return nil
        }
        func trailingRequiredParameterCount(after paramIndex: Int) -> Int {
            guard paramIndex + 1 < paramCount else {
                return 0
            }
            var count = 0
            for index in (paramIndex + 1)..<paramCount {
                if isVararg[index] {
                    continue
                }
                if boundNonVarargParams.contains(index) {
                    continue
                }
                if hasDefaultValues[index] {
                    continue
                }
                count += 1
            }
            return count
        }
        func advancePositionalCursor(for argIndex: Int) {
            while positionalCursor < paramCount {
                if !isVararg[positionalCursor], boundNonVarargParams.contains(positionalCursor) {
                    positionalCursor += 1
                    continue
                }
                if isVararg[positionalCursor] {
                    // Source positional arguments remain vararg elements;
                    // later ordinary parameters must be supplied by name.
                    // A trailing lambda is mapped separately below.
                    if callArgs[argIndex].isTrailingLambda != nil { break }
                    let trailingRequiredCount = trailingRequiredParameterCount(after: positionalCursor)
                    if callArgs.count - argIndex <= trailingRequiredCount {
                        positionalCursor += 1
                        continue
                    }
                }
                break
            }
        }
        var mapping: [Int: Int] = [:]
        var boundNonVarargParams: Set<Int> = []
        var boundNamedVarargParams: Set<Int> = []
        var sawNamedArgument = false
        var sawOutOfOrderNamedArgument = false
        var positionalCursor = 0
        // Highest parameter index bound so far by any argument (named or
        // positional). Kotlin only allows a positional argument after a named
        // one when the parameter order still matches declaration order; a
        // vararg parameter that is declared *before* an already-bound named
        // parameter (e.g. `fun f(vararg items: Int, name: String)` called as
        // `f(name = "x", 1, 2)`) would otherwise be silently accepted here.
        var maxBoundParamIndex = -1

        for (argIndex, arg) in callArgs.enumerated() {
            if arg.bindsToLastParameter {
                let parameterIndex = paramCount - 1
                guard argIndex == callArgs.count - 1,
                      arg.label == nil,
                      !arg.isSpread,
                      arg.isTrailingLambda != true,
                      !mapping.values.contains(parameterIndex)
                else { return nil }
                if !isVararg[parameterIndex] {
                    guard !boundNonVarargParams.contains(parameterIndex) else { return nil }
                    boundNonVarargParams.insert(parameterIndex)
                }
                mapping[argIndex] = parameterIndex
                maxBoundParamIndex = max(maxBoundParamIndex, parameterIndex)
                positionalCursor = max(positionalCursor, parameterIndex + 1)
                continue
            }
            if arg.isTrailingLambda == true {
                guard arg.label == nil, !arg.isSpread,
                      let parameterIndex = trailingLambdaParameterIndex(for: argIndex)
                else { return nil }
                boundNonVarargParams.insert(parameterIndex)
                mapping[argIndex] = parameterIndex
                maxBoundParamIndex = max(maxBoundParamIndex, parameterIndex)
                positionalCursor = max(positionalCursor, parameterIndex + 1)
                continue
            }
            if let label = arg.label {
                sawNamedArgument = true
                guard let paramIndex = paramNames.firstIndex(where: { $0 == label }) else {
                    return nil
                }
                if paramIndex != positionalCursor {
                    sawOutOfOrderNamedArgument = true
                }
                if arg.isSpread, !isVararg[paramIndex] {
                    return nil
                }
                if isVararg[paramIndex] {
                    guard !mapping.values.contains(paramIndex) else { return nil }
                    boundNamedVarargParams.insert(paramIndex)
                    mapping[argIndex] = paramIndex
                    maxBoundParamIndex = max(maxBoundParamIndex, paramIndex)
                    continue
                }
                if boundNonVarargParams.contains(paramIndex) {
                    return nil
                }
                boundNonVarargParams.insert(paramIndex)
                mapping[argIndex] = paramIndex
                maxBoundParamIndex = max(maxBoundParamIndex, paramIndex)
                if paramIndex == positionalCursor {
                    positionalCursor += 1
                }
                continue
            }

            if sawNamedArgument {
                // Positional arguments after named arguments must retain
                // declaration order, including ordinary callable arguments.
                // Trailing lambdas are also allowed after named arguments when
                // they map to the final function-typed parameter.
                if let trailingLambdaParamIndex = trailingLambdaParameterIndex(for: argIndex),
                   trailingLambdaParamIndex >= maxBoundParamIndex
                {
                    if boundNonVarargParams.contains(trailingLambdaParamIndex) {
                        return nil
                    }
                    boundNonVarargParams.insert(trailingLambdaParamIndex)
                    mapping[argIndex] = trailingLambdaParamIndex
                    maxBoundParamIndex = max(maxBoundParamIndex, trailingLambdaParamIndex)
                    if trailingLambdaParamIndex == positionalCursor {
                        positionalCursor += 1
                    }
                    continue
                }
                advancePositionalCursor(for: argIndex)
                if sawOutOfOrderNamedArgument || positionalCursor >= paramCount || positionalCursor < maxBoundParamIndex {
                    return nil
                }
                if arg.isSpread, !isVararg[positionalCursor] {
                    return nil
                }
                guard !boundNamedVarargParams.contains(positionalCursor) else { return nil }
                maxBoundParamIndex = max(maxBoundParamIndex, positionalCursor)
                mapping[argIndex] = positionalCursor
                if !isVararg[positionalCursor] {
                    boundNonVarargParams.insert(positionalCursor)
                    positionalCursor += 1
                }
                continue
            }

            advancePositionalCursor(for: argIndex)
            if positionalCursor >= paramCount {
                return nil
            }

            // Trailing lambda: a lambda outside parentheses can be bound to a later
            // function-typed parameter when the intervening parameters have
            // default values.
            let paramIndex: Int
            if argIndex == callArgs.count - 1,
               let trailingIndex = trailingLambdaParameterIndex(for: argIndex) {
                paramIndex = trailingIndex
            } else {
                paramIndex = positionalCursor
            }
            if arg.isSpread, !isVararg[paramIndex] {
                return nil
            }
            if isVararg[paramIndex] {
                guard !boundNamedVarargParams.contains(paramIndex) else { return nil }
                mapping[argIndex] = paramIndex
                continue
            }
            boundNonVarargParams.insert(paramIndex)
            mapping[argIndex] = paramIndex
            if paramIndex == positionalCursor {
                positionalCursor += 1
            } else {
                positionalCursor = max(positionalCursor, paramIndex + 1)
            }
        }

        for paramIndex in paramNames.indices {
            if isVararg[paramIndex] {
                continue
            }
            if boundNonVarargParams.contains(paramIndex) {
                continue
            }
            if !hasDefaultValues[paramIndex] {
                return nil
            }
        }
        return mapping
    }

    static func normalizeFlags(_ flags: [Bool], count: Int) -> [Bool] {
        if flags.count == count {
            return flags
        }
        if flags.count > count {
            return Array(flags.prefix(count))
        }
        return flags + Array(repeating: false, count: count - flags.count)
    }

    func parameterNames(
        for signature: FunctionSignature,
        symbols: SymbolTable,
        count: Int
    ) -> [InternedString?] {
        var names: [InternedString?] = []
        names.reserveCapacity(count)
        for index in 0 ..< count {
            if index < signature.valueParameterSymbols.count,
               let symbol = symbols.symbol(signature.valueParameterSymbols[index])
            {
                names.append(symbol.name)
            } else {
                names.append(nil)
            }
        }
        return names
    }

    func usedTypeVariables(from constraints: [VariableConstraint]) -> [TypeVarID] {
        var seen: Set<TypeVarID> = []
        for constraint in constraints {
            if case let .variable(variable) = constraint.left {
                seen.insert(variable)
            }
            if case let .variable(variable) = constraint.right {
                seen.insert(variable)
            }
        }
        return seen.sorted(by: { $0.rawValue < $1.rawValue })
    }

    func containsTypeVariable(
        _ type: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> Bool {
        switch typeSystem.kind(of: type) {
        case let .typeParam(typeParam):
            return typeParam.capture == nil && typeVarBySymbol[typeParam.symbol] != nil
        case let .intersection(parts):
            return parts.contains {
                containsTypeVariable($0, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            }
        case let .classType(classType):
            return typeSystem.allTypeArguments(for: classType).contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    containsTypeVariable(inner, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
                case .star:
                    false
                }
            }
        case let .kClassType(kClassType):
            return containsTypeVariable(kClassType.argument, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        case let .functionType(functionType):
            if functionType.contextReceivers.contains(where: {
                containsTypeVariable($0, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            }) {
                return true
            }
            if let receiver = functionType.receiver,
               containsTypeVariable(receiver, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            {
                return true
            }
            if containsTypeVariable(functionType.returnType, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem) {
                return true
            }
            return functionType.params.contains {
                containsTypeVariable($0, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            }
        default:
            return false
        }
    }

    /// Decomposes `subtype <: supertype` into fine-grained constraints that expose
    /// type variables nested inside generic class types and function types.
    ///
    /// For example, given `List<Int> <: List<T>` where `T` is a type variable, this
    /// produces the equality constraint `Int == T` (for invariant type arguments).
    /// For `out` positions it produces `Int <: T`, and for `in` positions `T <: Int`.
    ///
    /// When the supertype is a direct type parameter, it produces a single
    /// `subtype <: variable` constraint, matching the previous `operand()` behavior.
    ///
    /// Falls back to a simple `subtype <: supertype` type constraint when no
    /// decomposition is possible (different class symbols, non-generic types, etc.).
    func decomposeSubtypeConstraint(
        subtype: TypeID,
        supertype: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?
    ) -> [VariableConstraint] {
        decomposeSubtypeConstraintImpl(
            subtype: subtype,
            supertype: supertype,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: typeSystem,
            blameRange: blameRange,
            depth: 0
        )
    }

    private func decomposeSubtypeConstraintImpl(
        subtype: TypeID,
        supertype: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?,
        depth: Int
    ) -> [VariableConstraint] {
        // Guard against infinite recursion in cyclic type hierarchies.
        if depth > 20 {
            return [VariableConstraint(
                kind: .subtype,
                left: .type(subtype),
                right: .type(supertype),
                blameRange: blameRange
            )]
        }
        let supertypeKind = typeSystem.kind(of: supertype)
        if case let .typeParam(typeParam) = supertypeKind,
           typeParam.capture == nil,
           let variable = typeVarBySymbol[typeParam.symbol]
        {
            // Contextual lambda inputs can still refer to the candidate's
            // own parameters. Keep their relationship in the inference graph
            // rather than treating the left parameter as an opaque Any value.
            if case let .typeParam(subParameter) = typeSystem.kind(of: subtype),
               subParameter.capture == nil,
               let subVariable = typeVarBySymbol[subParameter.symbol],
               subParameter.nullability == .nonNull,
               typeParam.nullability == .nonNull
            {
                return [VariableConstraint(
                    kind: .subtype,
                    left: .variable(subVariable),
                    right: .variable(variable),
                    blameRange: blameRange
                )]
            }
            if typeParam.nullability != .nonNull {
                if case .nothing(.nullable) = typeSystem.kind(of: subtype) {
                    // `null` has type `Nothing?`. Although it is compatible
                    // with every nullable `T?`, it still provides the bottom
                    // type as the lower bound, so unconstrained calls such as
                    // `requireNotNull(null)` infer T = Nothing.
                    return [VariableConstraint(
                        kind: .subtype,
                        left: .type(typeSystem.nothingType),
                        right: .variable(variable),
                        blameRange: blameRange
                    )]
                }
                let nonNullSubtype = typeSystem.makeNonNullable(subtype)
                return [VariableConstraint(
                    kind: .subtype,
                    left: .type(nonNullSubtype),
                    right: .variable(variable),
                    blameRange: blameRange
                )]
            }
            return [VariableConstraint(
                kind: .subtype,
                left: .type(subtype),
                right: .variable(variable),
                blameRange: blameRange
            )]
        }

        // KClass is invariant. A projected receiver determines an existential
        // T, not its readable upper bound or its writable lower bound alone.
        if case let .kClassType(receiver) = supertypeKind,
           case let .typeParam(parameter) = typeSystem.kind(of: receiver.argument),
           let variable = typeVarBySymbol[parameter.symbol],
           case let .classType(actual) = typeSystem.kind(of: subtype),
           actual.classSymbol == typeSystem.kClassInterfaceSymbol,
           actual.args.count == 1,
           typeSystem.nullabilitySubtype(actual.nullability, receiver.nullability)
        {
            let lower: TypeID
            let upper: TypeID
            let writeForbidden: Bool
            switch actual.args[0] {
            case let .in(type):
                lower = type
                upper = typeSystem.anyType
                writeForbidden = false
            case let .out(type):
                lower = typeSystem.nothingType
                upper = type
                writeForbidden = true
            case .star:
                lower = typeSystem.nothingType
                upper = typeSystem.anyType
                writeForbidden = true
            case let .invariant(type):
                return [VariableConstraint(kind: .equal, left: .variable(variable), right: .type(type), blameRange: blameRange)]
            }
            let captured = typeSystem.makeCapturedType(
                parameter: parameter.symbol,
                lower: lower,
                upper: upper,
                writeForbidden: writeForbidden
            )
            return [VariableConstraint(kind: .equal, left: .variable(variable), right: .type(captured), blameRange: blameRange)]
        }

        // Case 1.5: supertype is an intersection. Decompose into all parts:
        // `A <: (B & C)` => `A <: B` and `A <: C`.
        if case let .intersection(parts) = supertypeKind {
            var result: [VariableConstraint] = []
            for part in parts {
                result.append(contentsOf: decomposeSubtypeConstraintImpl(
                    subtype: subtype,
                    supertype: part,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange,
                    depth: depth + 1
                ))
            }
            if !result.isEmpty {
                return result
            }
        }

        // `T & Any` is the definitely-non-null view of T. Preserve an
        // expected return type as an upper bound on T with nullable allowance;
        // the final substituted intersection removes null before subtype
        // validation (for example, String? & Any <: String).
        if case let .intersection(parts) = typeSystem.kind(of: subtype),
           parts.count == 2,
           parts.contains(where: { typeSystem.kind(of: $0) == .any(.nonNull) }),
           let typeParameter = parts.compactMap({ part -> TypeParamType? in
               guard case let .typeParam(parameter) = typeSystem.kind(of: part),
                     parameter.capture == nil,
                     parameter.nullability == .nonNull
               else {
                   return nil
               }
               return parameter
           }).first,
           let variable = typeVarBySymbol[typeParameter.symbol]
        {
            return [VariableConstraint(
                kind: .subtype,
                left: .variable(variable),
                right: .type(typeSystem.makeNullable(supertype)),
                blameRange: blameRange
            )]
        }

        // Comparable is a compiler-backed conformance for primitive values and
        // type parameters whose upper bound is Comparable<Self>. Those receivers
        // do not always have a classType that the generic decomposition below can
        // lift, so recover the concrete Comparable argument before solving the
        // member's class type parameter.
        if case let .classType(superClass) = supertypeKind,
           superClass.classSymbol == typeSystem.comparableInterfaceSymbol,
           superClass.args.count == 1,
           let superArgument = typeArgInnerType(superClass.args[0]),
           containsTypeVariable(superArgument, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem),
           let actualArgument = comparableArgument(of: subtype, typeSystem: typeSystem)
        {
            return decomposeSubtypeConstraintImpl(
                subtype: actualArgument,
                supertype: superArgument,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange,
                depth: depth + 1
            )
        }

        if containsTypeVariable(subtype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
            || containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        {
            if case .functionType = typeSystem.kind(of: subtype),
               let function = typeSystem.nominalFunctionType(for: supertype)
            {
                return decomposeSubtypeConstraintImpl(
                    subtype: subtype, supertype: typeSystem.make(.functionType(function)),
                    typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                    blameRange: blameRange, depth: depth + 1
                )
            }
            if case let .functionType(superFunction) = supertypeKind,
               let function = typeSystem.nominalFunctionType(for: subtype)
                   ?? nominalFunctionTypeThroughInheritance(
                       subtype,
                       matchingArityOf: superFunction,
                       typeSystem: typeSystem
                   )
            {
                return decomposeSubtypeConstraintImpl(
                    subtype: typeSystem.make(.functionType(function)), supertype: supertype,
                    typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                    blameRange: blameRange, depth: depth + 1
                )
            }
        }

        // Case 2: supertype is a generic class type with inferable variables or
        // use-site projections. Projections such as `Comparator<in Char>` are
        // otherwise left to the nominal subtype check, which cannot distinguish
        // a valid projected argument from an invariant one.
        if case let .classType(superClass) = supertypeKind,
           !typeSystem.allTypeArguments(for: superClass).isEmpty,
           (containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
               || typeSystem.allTypeArguments(for: superClass).contains(where: { arg in
                   switch arg {
                   case .in, .out:
                       true
                   case .invariant, .star:
                       false
                   }
               }))
        {
            let subtypeKind = typeSystem.kind(of: subtype)
            let receiverBounds: [TypeID] = switch subtypeKind {
            case let .typeParam(parameter):
                parameter.capture.map { [$0.upper] }
                    ?? typeSystem.declaredUpperBounds(for: parameter.symbol)
            case let .intersection(parts):
                parts
            default:
                []
            }
            let matchingBounds = receiverBounds.filter { bound in
                guard case let .classType(boundClass) = typeSystem.kind(of: bound) else { return false }
                return typeSystem.isNominalSubtypeSymbol(boundClass.classSymbol, of: superClass.classSymbol)
            }
            if !matchingBounds.isEmpty {
                return matchingBounds.flatMap { bound in
                    decomposeSubtypeConstraintImpl(
                        subtype: bound, supertype: supertype,
                        typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                        blameRange: blameRange, depth: depth + 1
                    )
                }
            }
            // Kotlin function types are represented as `Function<R>` in source
            // declarations such as `callsInPlace` and `holdsIn`. Preserve the
            // lambda return-type constraint when the source-backed interface is
            // generic, even though the lambda itself is modeled as a function type.
            if superClass.classSymbol == typeSystem.functionInterfaceSymbol,
               case let .functionType(subFunction) = subtypeKind,
               superClass.args.count == 1,
               let returnArg = superClass.args.first
            {
                switch returnArg {
                case let .out(type), let .invariant(type):
                    return decomposeSubtypeConstraintImpl(
                        subtype: subFunction.returnType,
                        supertype: type,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange,
                        depth: depth + 1
                    )
                case .in, .star:
                    break
                }
            }
            if case let .kClassType(subKClass) = subtypeKind,
               superClass.classSymbol == typeSystem.kClassInterfaceSymbol,
               subKClass.nullability == superClass.nullability || superClass.nullability == .nullable,
               let superArg = superClass.args.first
            {
                return decomposeTypeArgConstraintImpl(
                    subArg: .invariant(subKClass.argument),
                    superArg: superArg,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange,
                    depth: depth + 1
                )
            }
            if case let .classType(subClass) = subtypeKind,
               let alignedSubtype = alignNominalSubtype(
                   subClass,
                   to: superClass.classSymbol,
                   targetNullability: superClass.nullability,
                   typeSystem: typeSystem
               ),
               case let .classType(alignedClass) = typeSystem.kind(of: alignedSubtype),
               typeSystem.allTypeArguments(for: alignedClass).count == typeSystem.allTypeArguments(for: superClass).count
            {
                if subClass.classSymbol != superClass.classSymbol,
                   let liftedSubtype = liftClassType(
                       subClass,
                       to: superClass.classSymbol,
                       typeSystem: typeSystem
                   ),
                   liftedSubtype != subtype
                {
                    return decomposeSubtypeConstraintImpl(
                        subtype: liftedSubtype,
                        supertype: supertype,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange,
                        depth: depth + 1
                    )
                }
                let subArguments = typeSystem.allTypeArguments(for: alignedClass)
                let superArguments = typeSystem.allTypeArguments(for: superClass)
                let declarationVariances = typeSystem.allTypeParameterVariances(for: superClass.classSymbol)
                guard subClass.classSymbol == superClass.classSymbol,
                      subArguments.count == superArguments.count
                else {
                    return [VariableConstraint(
                        kind: .subtype,
                        left: .type(subtype),
                        right: .type(supertype),
                        blameRange: blameRange
                    )]
                }
                var result: [VariableConstraint] = []
                for (index, (subArg, superArg)) in zip(subArguments, superArguments).enumerated() {
                    let decomposed = decomposeTypeArgConstraintImpl(
                        subArg: subArg,
                        superArg: superArg,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange,
                        depth: depth + 1,
                        declarationVariance: declarationVariances.indices.contains(index)
                            ? declarationVariances[index] : .invariant
                    )
                    result.append(contentsOf: decomposed)
                }
                return result
            }
            if case let .classType(subClass) = subtypeKind,
               let liftedSubtype = liftClassType(
                   subClass,
                   to: superClass.classSymbol,
                   typeSystem: typeSystem
               ),
               liftedSubtype != subtype
            {
                return decomposeSubtypeConstraintImpl(
                    subtype: liftedSubtype,
                    supertype: supertype,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange,
                    depth: depth + 1
                )
            }
        }

        // Invariant KClass arguments constrain T in both directions.
        if case let .kClassType(superKClass) = supertypeKind,
           containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem),
           case let .kClassType(subKClass) = typeSystem.kind(of: subtype),
           subKClass.nullability == superKClass.nullability || superKClass.nullability == .nullable
        {
            return decomposeTypeArgConstraintImpl(
                subArg: .invariant(subKClass.argument),
                superArg: .invariant(superKClass.argument),
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange,
                depth: depth + 1
            )
        }

        // Case 3: either side is a function type with type variables in
        // params/return. Invariant generic arguments decompose in both
        // directions. The reverse direction can place the variable-bearing
        // function on the subtype side, for example:
        // `(T) -> Unit <: (String) -> Unit` from
        // `Box<(String) -> Unit> <: Box<(T) -> Unit>`.
        // Leaving that as a type-to-type constraint asks isSubtype to compare
        // the unresolved T before the solver applies its bounds.
        if case let .functionType(superFunc) = supertypeKind,
           containsTypeVariable(subtype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
               || containsTypeVariable(supertype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        {
            let subtypeKind = typeSystem.kind(of: subtype)
            // A function type's receiver is interchangeable with a leading
            // parameter: `ProducerScope<Int>.() -> Unit` and
            // `(ProducerScope<Int>) -> Unit` are the same Kotlin type. Align
            // each side's effective parameter list — receiver first when
            // present — and decompose pairwise, contravariantly.
            let effectiveParams: [TypeID] = if case let .functionType(subFunc) = subtypeKind {
                (subFunc.receiver.map { [$0] } ?? []) + subFunc.params
            } else {
                []
            }
            let superEffectiveParams =
                (superFunc.receiver.map { [$0] } ?? []) + superFunc.params
            if case let .functionType(subFunc) = subtypeKind,
               effectiveParams.count == superEffectiveParams.count,
               subFunc.contextReceivers.count == superFunc.contextReceivers.count,
               // A non-suspend function is usable wherever a suspend one is
               // expected (`() -> T <: suspend () -> T`), but not vice versa.
               superFunc.isSuspend || !subFunc.isSuspend,
               typeSystem.nullabilitySubtype(subFunc.nullability, superFunc.nullability)
            {
                var result: [VariableConstraint] = []
                for (subContextReceiver, superContextReceiver) in zip(subFunc.contextReceivers, superFunc.contextReceivers) {
                    result.append(contentsOf: decomposeSubtypeConstraintImpl(
                        subtype: superContextReceiver,
                        supertype: subContextReceiver,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange,
                        depth: depth + 1
                    ))
                }
                // Function types are contravariant in the receiver and
                // parameter types: `ProducerScope<Int>.() -> Unit <:
                // ProducerScope<E>.() -> Unit` binds E to Int.
                for (subParam, superParam) in zip(effectiveParams, superEffectiveParams) {
                    result.append(contentsOf: decomposeSubtypeConstraintImpl(
                        subtype: superParam,
                        supertype: subParam,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange,
                        depth: depth + 1
                    ))
                }
                result.append(contentsOf: decomposeSubtypeConstraintImpl(
                    subtype: subFunc.returnType,
                    supertype: superFunc.returnType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange,
                    depth: depth + 1
                ))
                return result
            }
        }

        let subtypeKind = typeSystem.kind(of: subtype)
        if case let .typeParam(typeParam) = subtypeKind,
           typeParam.capture == nil,
           let variable = typeVarBySymbol[typeParam.symbol]
        {
            return [VariableConstraint(
                kind: .subtype,
                left: .variable(variable),
                right: .type(supertype),
                blameRange: blameRange
            )]
        }

        if case let .classType(subClass) = subtypeKind,
           !typeSystem.allTypeArguments(for: subClass).isEmpty,
           containsTypeVariable(subtype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        {
            if case let .classType(superClass) = supertypeKind,
               subClass.classSymbol == superClass.classSymbol,
               typeSystem.allTypeArguments(for: subClass).count == typeSystem.allTypeArguments(for: superClass).count,
               typeSystem.nullabilitySubtype(subClass.nullability, superClass.nullability)
            {
                let subtypeArguments = typeSystem.allTypeArguments(for: subClass)
                let supertypeArguments = typeSystem.allTypeArguments(for: superClass)
                let declarationVariances = typeSystem.allTypeParameterVariances(for: superClass.classSymbol)
                var result: [VariableConstraint] = []
                for (index, (subArg, superArg)) in zip(subtypeArguments, supertypeArguments).enumerated() {
                    let decomposed = decomposeTypeArgConstraintImpl(
                        subArg: subArg,
                        superArg: superArg,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange,
                        depth: depth + 1,
                        declarationVariance: declarationVariances.indices.contains(index)
                            ? declarationVariances[index] : .invariant
                    )
                    result.append(contentsOf: decomposed)
                }
                return result
            }
            // Generic subtype against a concrete supertype instantiation
            // (e.g. `MutableSharedFlow<T> <: SharedFlow<Int>`): lift the
            // subtype to the supertype's nominal symbol so the type variables
            // inside its arguments stay inferable.
            if case let .classType(superClass) = supertypeKind,
               subClass.classSymbol != superClass.classSymbol,
               let liftedSubtype = liftClassType(
                   subClass,
                   to: superClass.classSymbol,
                   typeSystem: typeSystem
               ),
               liftedSubtype != subtype
            {
                return decomposeSubtypeConstraintImpl(
                    subtype: liftedSubtype,
                    supertype: supertype,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange,
                    depth: depth + 1
                )
            }
        }

        if case let .kClassType(subKClass) = subtypeKind,
           containsTypeVariable(subtype, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem),
           case let .kClassType(superKClass) = supertypeKind,
           subKClass.nullability == superKClass.nullability || superKClass.nullability == .nullable
        {
            return decomposeTypeArgConstraintImpl(
                subArg: .invariant(subKClass.argument),
                superArg: .invariant(superKClass.argument),
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange,
                depth: depth + 1
            )
        }

        return [VariableConstraint(
            kind: .subtype,
            left: .type(subtype),
            right: .type(supertype),
            blameRange: blameRange
        )]
    }

    private func alignNominalSubtype(
        _ subtype: ClassType,
        to superSymbol: SymbolID,
        targetNullability: Nullability,
        typeSystem: TypeSystem
    ) -> TypeID? {
        guard typeSystem.nullabilitySubtype(subtype.nullability, targetNullability) else {
            return nil
        }
        if subtype.classSymbol == superSymbol {
            return typeSystem.make(.classType(subtype))
        }
        guard typeSystem.isNominalSubtypeSymbol(subtype.classSymbol, of: superSymbol) else {
            return nil
        }

        let substitutedArgs = typeSystem.liftedNominalSupertypeArgs(from: subtype, to: superSymbol) ?? []
        return typeSystem.make(.classType(typeSystem.classType(
            for: superSymbol,
            arguments: substitutedArgs,
            nullability: subtype.nullability
        )))
    }

    func liftClassType(
        _ subtype: ClassType,
        to targetSymbol: SymbolID,
        typeSystem: TypeSystem
    ) -> TypeID? {
        alignNominalSubtype(
            subtype,
            to: targetSymbol,
            targetNullability: subtype.nullability,
            typeSystem: typeSystem
        )
    }

    /// KUU-1195: a nominal subtype that reaches a regular or suspend function
    /// interface through inheritance decomposes against a variable-bearing
    /// function supertype the same way a literal function interface does.
    /// Only the subtype side looks through inheritance: a plain function value
    /// is not an arbitrary nominal subtype, so the supertype direction keeps
    /// the direct `nominalFunctionType` check.
    private func nominalFunctionTypeThroughInheritance(
        _ subtype: TypeID,
        matchingArityOf function: FunctionType,
        typeSystem: TypeSystem
    ) -> FunctionType? {
        guard case let .classType(subClass) = typeSystem.kind(of: subtype) else {
            return nil
        }
        let arity = (function.receiver.map { [$0] } ?? []).count + function.params.count
        guard let lifted = typeSystem.inheritedFunctionInterfaceClassType(
            of: subClass,
            arity: arity,
            isSuspend: function.isSuspend
        ) else {
            return nil
        }
        return typeSystem.nominalFunctionType(for: typeSystem.make(.classType(lifted)))
    }

    private func decomposeTypeArgConstraintImpl(
        subArg: TypeArg,
        superArg: TypeArg,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange?,
        depth: Int,
        declarationVariance: TypeVariance = .invariant
    ) -> [VariableConstraint] {
        // Kotlin declaration-site variance applies even when source syntax uses
        // invariant type arguments (`Sequence<T>` is still covariant because
        // Sequence declares `out T`). Without this projection, a generic
        // source-backed return such as Sequence<Int> cannot flow into
        // Sequence<Any> during type-variable solving.
        // Star projections carry their own variance, so projecting them would hide the
        // dedicated star handling below and leave type variables unconstrained.
        let involvesStar = isStarProjection(subArg) || isStarProjection(superArg)
        let projectedSubArg = involvesStar
            ? subArg
            : applyDeclarationVariance(subArg, declarationVariance: declarationVariance)
        let projectedSuperArg = involvesStar
            ? superArg
            : applyDeclarationVariance(superArg, declarationVariance: declarationVariance)

        switch (projectedSubArg, projectedSuperArg) {
        case let (.invariant(subInner), .invariant(superInner)):
            // Invariant: both directions (equality).
            var result = decomposeSubtypeConstraintImpl(
                subtype: subInner, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            )
            result.append(contentsOf: decomposeSubtypeConstraintImpl(
                subtype: superInner, supertype: subInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            ))
            return result

        case let (.invariant(subInner), .out(superInner)),
             let (.out(subInner), .out(superInner)):
            return decomposeSubtypeConstraintImpl(
                subtype: subInner, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            )

        case let (.invariant(subInner), .in(superInner)),
             let (.in(subInner), .in(superInner)):
            return decomposeSubtypeConstraintImpl(
                subtype: superInner, supertype: subInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            )

        case let (.star, .invariant(superInner)), let (.star, .out(superInner)):
            // Subtype is star (e.g. receiver `Box<*>` against signature `Box<T>`).
            // A star projection is equivalent to `out TUpperBound`, where the
            // upper bound comes from the declaration of the projected type.
            // Use Any? only for an unbounded type parameter.
            let starUpperBound = starProjectionUpperBound(for: superInner, typeSystem: typeSystem)
            return decomposeSubtypeConstraintImpl(
                subtype: starUpperBound, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            ) + decomposeSubtypeConstraintImpl(
                subtype: superInner, supertype: starUpperBound,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            )

        default:
            // Incompatible variance combinations (e.g. .out vs .in) – conservatively
            // treat as invariant so the original subtype relation is still enforced.
            let subInner: TypeID
            let superInner: TypeID
            switch subArg {
            case let .invariant(t), let .out(t), let .in(t): subInner = t
            case .star: return []
            }
            switch superArg {
            case let .invariant(t), let .out(t), let .in(t): superInner = t
            case .star: return []
            }
            var fallback = decomposeSubtypeConstraintImpl(
                subtype: subInner, supertype: superInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            )
            fallback.append(contentsOf: decomposeSubtypeConstraintImpl(
                subtype: superInner, supertype: subInner,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: blameRange, depth: depth
            ))
            return fallback
        }
    }

    private func isStarProjection(_ arg: TypeArg) -> Bool {
        if case .star = arg { return true }
        return false
    }

    private func applyDeclarationVariance(
        _ arg: TypeArg,
        declarationVariance: TypeVariance
    ) -> TypeArg {
        switch declarationVariance {
        case .invariant:
            return arg
        case .out:
            switch arg {
            case let .invariant(type), let .out(type):
                return .out(type)
            case .in, .star:
                return arg
            }
        case .in:
            switch arg {
            case let .invariant(type), let .in(type):
                return .in(type)
            case .out, .star:
                return arg
            }
        }
    }

    func isConstraintSatisfiedWithoutVariables(
        _ constraint: VariableConstraint,
        typeSystem: TypeSystem
    ) -> Bool {
        guard case let .type(lhs) = constraint.left,
              case let .type(rhs) = constraint.right
        else {
            return false
        }
        switch constraint.kind {
        case .subtype:
            return typeSystem.isSubtype(lhs, rhs)
        case .equal:
            return typeSystem.isSubtype(lhs, rhs) && typeSystem.isSubtype(rhs, lhs)
        case .supertype:
            return typeSystem.isSubtype(rhs, lhs)
        }
    }
}
