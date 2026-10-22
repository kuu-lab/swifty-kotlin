public extension TypeSystem {
    internal func nullabilitySuffix(_ nullability: Nullability) -> String {
        switch nullability {
        case .nullable: "?"
        case .platformType: "!"
        case .nonNull: ""
        }
    }

    internal func renderType(_ type: TypeID) -> String {
        switch kind(of: type) {
        case .error:
            return "<error>"
        case .unit:
            return "Unit"
        case .nullableUnit:
            return "Unit?"
        case .platformUnit:
            return "Unit!"
        case let .nothing(nullability):
            return "Nothing\(nullabilitySuffix(nullability))"
        case let .any(nullability):
            return "Any\(nullabilitySuffix(nullability))"
        case let .stringStruct(nullability):
            return "String\(nullabilitySuffix(nullability))"
        case let .primitive(primitive, nullability):
            let base = primitive.kotlinName
            return "\(base)\(nullabilitySuffix(nullability))"
        case let .classType(classType):
            let allArguments = allTypeArguments(for: classType)
            let args = if allArguments.isEmpty {
                ""
            } else {
                "<" + allArguments.map(renderTypeArg).joined(separator: ", ") + ">"
            }
            return "Class#\(classType.classSymbol.rawValue)\(args)\(nullabilitySuffix(classType.nullability))"
        case let .typeParam(typeParam):
            if let capture = typeParam.capture {
                return "Captured[\(renderType(capture.lower))..\(renderType(capture.upper))]\(nullabilitySuffix(typeParam.nullability))"
            }
            return "T#\(typeParam.symbol.rawValue)\(nullabilitySuffix(typeParam.nullability))"
        case let .functionType(functionType):
            let contextPrefix = if functionType.contextReceivers.isEmpty {
                ""
            } else {
                "context(" + functionType.contextReceivers.map(renderType).joined(separator: ", ") + ") "
            }
            let receiverPrefix = if let receiver = functionType.receiver {
                "\(renderType(receiver))."
            } else {
                ""
            }
            let suspendPrefix = functionType.isSuspend ? "suspend " : ""
            let params = functionType.params.map(renderType).joined(separator: ", ")
            let retType = renderType(functionType.returnType)
            let core = "\(contextPrefix)\(suspendPrefix)\(receiverPrefix)(\(params)) -> \(retType)"
            let suffix = nullabilitySuffix(functionType.nullability)
            // A nullable function type needs its own parens so it stays
            // distinct from a non-nullable function returning a nullable
            // value: `((Int) -> Int)?` vs. `(Int) -> Int?`. Only the
            // function type's own nullability triggers this — the return
            // type's suffix is already inside `retType`.
            return functionType.nullability == .nonNull ? "\(core)\(suffix)" : "(\(core))\(suffix)"
        case let .kClassType(kClassType):
            return "KClass<\(renderType(kClassType.argument))>\(nullabilitySuffix(kClassType.nullability))"
        case let .intersection(parts):
            return parts.map(renderType).joined(separator: " & ")
        }
    }

    /// Renders well-known inference types without leaking internal symbol IDs
    /// into user-facing constraint diagnostics.
    internal func renderConstraintType(_ type: TypeID) -> String {
        switch kind(of: type) {
        case let .classType(classType) where classType.classSymbol == numberClassSymbol:
            return "Number\(nullabilitySuffix(classType.nullability))"
        case let .classType(classType) where classType.classSymbol == comparableInterfaceSymbol:
            let allArguments = allTypeArguments(for: classType)
            let args = allArguments.isEmpty
                ? ""
                : "<" + allArguments.map(renderConstraintTypeArg).joined(separator: ", ") + ">"
            return "Comparable\(args)\(nullabilitySuffix(classType.nullability))"
        case let .intersection(parts):
            return parts.map(renderConstraintType).joined(separator: " & ")
        default:
            return renderType(type)
        }
    }

    private func renderConstraintTypeArg(_ arg: TypeArg) -> String {
        switch arg {
        case let .invariant(type):
            renderConstraintType(type)
        case let .out(type):
            "out \(renderConstraintType(type))"
        case let .in(type):
            "in \(renderConstraintType(type))"
        case .star:
            "*"
        }
    }

    private func renderTypeArg(_ arg: TypeArg) -> String {
        switch arg {
        case let .invariant(type):
            renderType(type)
        case let .out(type):
            "out \(renderType(type))"
        case let .in(type):
            "in \(renderType(type))"
        case .star:
            "*"
        }
    }

    func makeTypeVarBySymbol(_ symbols: [SymbolID]) -> [SymbolID: TypeVarID] {
        var mapping: [SymbolID: TypeVarID] = [:]
        for (index, symbol) in symbols.enumerated() {
            mapping[symbol] = TypeVarID(rawValue: Int32(index))
        }
        return mapping
    }

    struct VarianceProjectionResult {
        /// Substitution for covariant positions (return types).
        /// For `out Number`: T → Number.  For `in Number`: T → Any?.  For `*`: T → Any?.
        public let covariantSubstitution: [TypeVarID: TypeID]
        /// Type parameter symbols that are projected as `out` or `*` (write-forbidden).
        public let writeForbiddenSymbols: Set<SymbolID>
        /// Projected inputs made explicitly nullable by a supertype argument.
        public let nullableWriteSymbols: Set<SymbolID>
    }

    /// Resolve the effective upper bound for a type parameter, returning `Any?` when
    /// no explicit bounds exist and an intersection type when multiple bounds exist.
    private func effectiveUpperBound(for symbol: SymbolID, symbols: SymbolTable) -> TypeID {
        let bounds = declaredUpperBounds(for: symbol)
        if bounds.isEmpty { return nullableAnyType }
        if bounds.count == 1 { return bounds[0] }
        return make(.intersection(bounds))
    }

    /// Build variance-aware substitutions for a member access on a projected receiver type.
    ///
    /// Given a receiver like `MutableList<out Number>`, this builds:
    /// - Covariant substitution: T → Number (for return types)
    /// - A set of type parameter symbols that are write-forbidden (`out` or `*` projections)
    ///
    /// Returns `nil` if the receiver has no projected type arguments (all invariant).
    func buildVarianceProjectionSubstitutions(
        receiverType: TypeID,
        signature: FunctionSignature,
        symbols: SymbolTable
    ) -> VarianceProjectionResult? {
        if case let .intersection(parts) = kind(of: receiverType) {
            let projections = parts.compactMap {
                buildVarianceProjectionSubstitutions(receiverType: $0, signature: signature, symbols: symbols)
            }
            guard !projections.isEmpty else { return nil }
            var covariantSubstitution: [TypeVarID: TypeID] = [:]
            var writeForbiddenSymbols: Set<SymbolID> = []
            var nullForbiddenSymbols: Set<SymbolID> = []
            for projection in projections {
                covariantSubstitution.merge(projection.covariantSubstitution) { glb([$0, $1]) }
                writeForbiddenSymbols.formUnion(projection.writeForbiddenSymbols)
                nullForbiddenSymbols.formUnion(projection.writeForbiddenSymbols.subtracting(projection.nullableWriteSymbols))
            }
            return VarianceProjectionResult(
                covariantSubstitution: covariantSubstitution,
                writeForbiddenSymbols: writeForbiddenSymbols,
                nullableWriteSymbols: writeForbiddenSymbols.subtracting(nullForbiddenSymbols)
            )
        }
        guard case var .classType(classType) = kind(of: receiverType) else {
            return nil
        }
        var nullableWriteSymbols: Set<SymbolID> = []
        // An inherited member's parameters belong to its declaring receiver.
        // Preserve the projections while lifting the actual subtype to it.
        if signature.classTypeParameterCount > 0,
           let receiver = signature.receiverType,
           case let .classType(declared) = kind(of: receiver),
           declared.classSymbol != classType.classSymbol
        {
            let parameters = allTypeParameterSymbols(for: classType.classSymbol)
            var captureIdentities: Set<Int> = []
            let capturedArguments = allTypeArguments(for: classType).enumerated().map { index, argument -> TypeArg in
                guard parameters.indices.contains(index) else { return argument }
                let parameter = parameters[index]
                let lower: TypeID
                let upper: TypeID
                let writeForbidden: Bool
                switch argument {
                case .invariant:
                    return argument
                case let .out(type):
                    lower = nothingType
                    upper = type
                    writeForbidden = true
                case let .in(type):
                    lower = type
                    upper = effectiveUpperBound(for: parameter, symbols: symbols)
                    writeForbidden = false
                case .star:
                    lower = nothingType
                    upper = effectiveUpperBound(for: parameter, symbols: symbols)
                    writeForbidden = true
                }
                let captured = makeProjectedReceiverCapture(
                    receiverType: receiverType,
                    parameter: parameter,
                    lower: lower,
                    upper: upper,
                    writeForbidden: writeForbidden,
                    argumentIndex: index
                )
                if case let .typeParam(parameter) = kind(of: captured), let capture = parameter.capture {
                    captureIdentities.insert(capture.identity)
                }
                // Keep an explicit supertype T? separate from a nullable upper bound.
                return .invariant(makeNonNullable(captured))
            }
            let capturedReceiver = self.classType(
                for: classType.classSymbol, arguments: capturedArguments, nullability: classType.nullability
            )
            guard let lifted = liftedNominalSupertypeArgs(from: capturedReceiver, to: declared.classSymbol) else {
                return nil
            }
            classType = self.classType(
                for: declared.classSymbol, arguments: lifted, nullability: classType.nullability
            )
            let declaredParameters = allTypeParameterSymbols(for: declared.classSymbol)
            for (index, argument) in lifted.enumerated() where declaredParameters.indices.contains(index) {
                if case let .invariant(type) = argument,
                   case let .typeParam(parameter) = kind(of: type),
                   parameter.nullability == .nullable, let capture = parameter.capture,
                   captureIdentities.contains(capture.identity) {
                    nullableWriteSymbols.insert(declaredParameters[index])
                }
            }
        }
        let typeParamSymbols = allTypeParameterSymbols(for: classType.classSymbol)
        let arguments = allTypeArguments(for: classType)
        guard !typeParamSymbols.isEmpty, !arguments.isEmpty else { return nil }

        let hasProjection = arguments.contains { arg in
            switch arg {
            case .out, .in, .star: true
            case let .invariant(type):
                if case let .typeParam(parameter) = kind(of: type) { parameter.capture != nil } else { false }
            }
        }
        guard hasProjection else { return nil }

        let typeVarBySymbol = makeTypeVarBySymbol(signature.typeParameterSymbols)
        var covariantSub = typeVarBySymbol.isEmpty ? [:] : [TypeVarID: TypeID]()
        var writeForbidden: Set<SymbolID> = []

        for (index, arg) in arguments.enumerated() {
            guard index < typeParamSymbols.count else { break }
            let tpSymbol = typeParamSymbols[index]
            guard let typeVar = typeVarBySymbol[tpSymbol] else { continue }
            let resolved = resolveVarianceArg(arg, tpSymbol: tpSymbol, symbols: symbols)
            covariantSub[typeVar] = resolved.type
            if resolved.writeForbidden { writeForbidden.insert(tpSymbol) }
        }

        return VarianceProjectionResult(
            covariantSubstitution: covariantSub,
            writeForbiddenSymbols: writeForbidden,
            nullableWriteSymbols: nullableWriteSymbols
        )
    }

    private func resolveVarianceArg(
        _ arg: TypeArg, tpSymbol: SymbolID, symbols: SymbolTable
    ) -> (type: TypeID, writeForbidden: Bool) {
        switch arg {
        case let .invariant(type):
            if case let .typeParam(parameter) = kind(of: type), let capture = parameter.capture {
                let upper = parameter.nullability == .nullable ? makeNullable(capture.upper) : capture.upper
                return (upper, capture.writeForbidden)
            }
            return (type, false)
        case let .out(type):
            return (type, true)
        case .in:
            return (effectiveUpperBound(for: tpSymbol, symbols: symbols), false)
        case .star:
            return (effectiveUpperBound(for: tpSymbol, symbols: symbols), true)
        }
    }

    func checkVarianceViolationInParameters(
        signature: FunctionSignature,
        writeForbiddenSymbols: Set<SymbolID>,
        nullableWriteSymbols: Set<SymbolID> = [],
        argumentTypes: [TypeID] = [],
        parameterMapping: [Int: Int] = [:]
    ) -> Int? {
        guard !writeForbiddenSymbols.isEmpty else { return nil }
        for (index, paramType) in signature.parameterTypes.enumerated() {
            // Nothing can be passed to an existential input without producing
            // a value. Every supplied argument for this parameter must be bottom.
            let suppliedIndices = parameterMapping.compactMap { $0.value == index ? $0.key : nil }
            let acceptsNull: Bool
            if case let .typeParam(parameter) = kind(of: paramType) {
                acceptsNull = parameter.nullability == .nullable || nullableWriteSymbols.contains(parameter.symbol)
            } else {
                acceptsNull = false
            }
            if !suppliedIndices.isEmpty,
               suppliedIndices.allSatisfy({ argumentIndex in
                   guard argumentTypes.indices.contains(argumentIndex) else { return false }
                   let type = argumentTypes[argumentIndex]
                   return type == nothingType || (acceptsNull && type == nullableNothingType)
               }) {
                continue
            }
            let unsafeVarianceSymbols = signature.valueParameterUnsafeVarianceTypeParameterSymbols.indices.contains(index)
                ? signature.valueParameterUnsafeVarianceTypeParameterSymbols[index]
                : []
            for symbol in writeForbiddenSymbols
            where typeContainsTypeParam(paramType, symbol: symbol) && !unsafeVarianceSymbols.contains(symbol) {
                return index
            }
        }
        return nil
    }

    func substituteTypeParameters(
        in type: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeID {
        let kind = kind(of: type)
        switch kind {
        case let .typeParam(typeParam):
            if typeParam.capture != nil { return type }
            if let variable = typeVarBySymbol[typeParam.symbol],
               let concrete = substitution[variable]
            {
                switch typeParam.nullability {
                case .nullable:
                    return makeNullable(concrete)
                case .platformType:
                    // A nullable Java type argument collapses the flexible
                    // bounds to T?, so it must never become assignable to T.
                    if nullability(of: concrete) == .nullable { return concrete }
                    return withNullability(.platformType, for: concrete)
                case .nonNull:
                    return concrete
                }
            }
            return type

        case let .classType(classType):
            let newArgs = classType.args.map {
                substituteTypeArg($0, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
            }
            let newEnclosingTypeArgs = classType.enclosingTypeArgs.map {
                substituteTypeArg($0, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
            }
            if newArgs == classType.args && newEnclosingTypeArgs == classType.enclosingTypeArgs {
                return type
            }
            return make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: newArgs,
                enclosingTypeArgs: newEnclosingTypeArgs,
                nullability: classType.nullability
            )))

        case let .functionType(functionType):
            return substituteFunctionType(
                functionType, originalType: type,
                substitution: substitution, typeVarBySymbol: typeVarBySymbol
            )

        case let .kClassType(kClassType):
            let newArg = substituteTypeParameters(
                in: kClassType.argument,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if newArg == kClassType.argument { return type }
            return make(.kClassType(KClassType(argument: newArg, nullability: kClassType.nullability)))

        case let .intersection(parts):
            let newParts = parts.map { part in
                substituteTypeParameters(
                    in: part,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            if newParts == parts {
                return type
            }
            // A non-null intersection component removes null from every
            // substituted part, including a nullable concrete type argument.
            let hasNonNullPart = newParts.contains { isDefinitelyNonNull($0) }
            let narrowedParts = hasNonNullPart
                ? newParts.map { part in
                    nullability(of: part) == .nonNull
                        ? part
                        : withNullability(.nonNull, for: part)
                }
                : newParts
            return make(.intersection(narrowedParts))

        default:
            return type
        }
    }

    /// Rewrites references to type-parameter symbols in `arg` according to
    /// `mapping` (old symbol -> replacement symbol), keeping each reference's
    /// nullability. Used to reconcile the synthetic `T<n>` symbols that
    /// library metadata spells with the symbols a nominal was registered with.
    func substitutingTypeParameterSymbols(_ arg: TypeArg, mapping: [SymbolID: SymbolID]) -> TypeArg {
        let orderedOldSymbols = mapping.keys.sorted { $0.rawValue < $1.rawValue }
        let typeVarBySymbol = makeTypeVarBySymbol(orderedOldSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (oldSymbol, variable) in typeVarBySymbol {
            guard let replacement = mapping[oldSymbol] else { continue }
            substitution[variable] = make(.typeParam(TypeParamType(symbol: replacement, nullability: .nonNull)))
        }
        return substituteTypeArg(arg, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
    }

    private func substituteTypeArg(
        _ arg: TypeArg,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            .invariant(substituteTypeParameters(in: inner, substitution: substitution, typeVarBySymbol: typeVarBySymbol))
        case let .out(inner):
            .out(substituteTypeParameters(in: inner, substitution: substitution, typeVarBySymbol: typeVarBySymbol))
        case let .in(inner):
            .in(substituteTypeParameters(in: inner, substitution: substitution, typeVarBySymbol: typeVarBySymbol))
        case .star:
            .star
        }
    }

    private func substituteFunctionType(
        _ functionType: FunctionType,
        originalType: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeID {
        let sub = { [self] (t: TypeID) in
            substituteTypeParameters(in: t, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
        }
        let newContextReceivers = functionType.contextReceivers.map { sub($0) }
        let newReceiver = functionType.receiver.map { sub($0) }
        let newParams = functionType.params.map { sub($0) }
        let newReturn = sub(functionType.returnType)
        if newContextReceivers == functionType.contextReceivers,
           newReceiver == functionType.receiver,
           newParams == functionType.params,
           newReturn == functionType.returnType
        {
            return originalType
        }
        return make(.functionType(FunctionType(
            contextReceivers: newContextReceivers,
            receiver: newReceiver, params: newParams, returnType: newReturn,
            isSuspend: functionType.isSuspend, isCallableReference: functionType.isCallableReference,
            nullability: functionType.nullability
        )))
    }
}
