extension TypeSystem {
    func capturedReadableUpperBound(of type: TypeID) -> TypeID {
        guard case let .typeParam(parameter) = kind(of: type), let capture = parameter.capture else { return type }
        return withNullability(parameter.nullability, for: capture.upper)
    }

    func capturedOperatorReceiverType(of type: TypeID) -> TypeID {
        let upper = capturedReadableUpperBound(of: type)
        // Any supplies no builtin operator contract. Keep the existential so
        // permissive legacy Any fallbacks cannot accept an unknown operation.
        if case .any = kind(of: upper) { return type }
        return upper
    }

    func isBuiltinArithmeticOperand(_ type: TypeID) -> Bool {
        guard case let .primitive(primitive, .nonNull) = kind(of: type) else { return false }
        return primitive != .boolean
    }

    private func capturedLowerApproximation(of type: TypeID) -> TypeID {
        if case let .typeParam(parameter) = kind(of: type), let capture = parameter.capture {
            return withNullability(parameter.nullability, for: capture.lower)
        }
        return containsCapturedTypes(type) ? nothingType : type
    }

    func containsCapturedTypes(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case let .typeParam(parameter):
            return parameter.capture != nil
        case let .classType(nominal):
            return allTypeArguments(for: nominal).contains { arg in
                switch arg {
                case let .invariant(inner), let .in(inner), let .out(inner): containsCapturedTypes(inner)
                case .star: false
                }
            }
        case let .kClassType(klass):
            return containsCapturedTypes(klass.argument)
        case let .functionType(function):
            return (function.contextReceivers + function.params + (function.receiver.map { [$0] } ?? [])
                + [function.returnType]).contains(where: containsCapturedTypes)
        case let .intersection(parts):
            return parts.contains(where: containsCapturedTypes)
        default:
            return false
        }
    }

    /// Captures are local to a call. Export readable bounds and use-site
    /// projections instead of leaking the extension's declaration-local T.
    func approximatingCapturedTypes(in type: TypeID) -> TypeID {
        switch kind(of: type) {
        case let .typeParam(parameter):
            guard let capture = parameter.capture else { return type }
            return withNullability(parameter.nullability, for: capture.upper)
        case let .classType(nominal):
            let arguments = allTypeArguments(for: nominal)
            let variances = allTypeParameterVariances(for: nominal.classSymbol)
            let approximatedArguments = arguments.enumerated().map { index, arg -> TypeArg in
                let inner: TypeID
                switch arg {
                case let .in(type): return .in(capturedLowerApproximation(of: type))
                case let .out(type): return .out(approximatingCapturedTypes(in: type))
                case .star: return .star
                case let .invariant(type): inner = type
                }
                let variance = variances.indices.contains(index) ? variances[index] : .invariant
                if case let .typeParam(parameter) = kind(of: inner), let capture = parameter.capture {
                    if variance == .in || (variance == .invariant && capture.lower != nothingType) {
                        return .in(withNullability(parameter.nullability, for: capture.lower))
                    }
                    return .out(withNullability(parameter.nullability, for: capture.upper))
                }
                let approximation = approximatingCapturedTypes(in: inner)
                // A nested existential must not become a concrete invariant
                // argument merely because its own readable bound was widened.
                if approximation == inner { return arg }
                return variance == .in ? .in(capturedLowerApproximation(of: inner)) : .out(approximation)
            }
            let enclosingCount = nominal.enclosingTypeArgs.count
            let enclosingTypeArgs = Array(approximatedArguments.prefix(enclosingCount))
            let args = Array(approximatedArguments.dropFirst(enclosingCount))
            guard args != nominal.args || enclosingTypeArgs != nominal.enclosingTypeArgs else { return type }
            return make(.classType(ClassType(
                classSymbol: nominal.classSymbol,
                args: args,
                enclosingTypeArgs: enclosingTypeArgs,
                nullability: nominal.nullability
            )))
        case let .kClassType(klass):
            let argument = approximatingCapturedTypes(in: klass.argument)
            guard argument != klass.argument else { return type }
            guard let symbol = kClassInterfaceSymbol else { return type }
            return make(.classType(ClassType(classSymbol: symbol, args: [.out(argument)], nullability: klass.nullability)))
        case let .functionType(function):
            // Preserve contravariant inputs through the captured lower bound.
            return make(.functionType(FunctionType(
                contextReceivers: function.contextReceivers.map(capturedLowerApproximation),
                receiver: function.receiver.map(capturedLowerApproximation),
                params: function.params.map(capturedLowerApproximation), returnType: approximatingCapturedTypes(in: function.returnType),
                isSuspend: function.isSuspend, isCallableReference: function.isCallableReference,
                nullability: function.nullability, throws: function.throws
            )))
        case let .intersection(parts):
            return make(.intersection(parts.map { approximatingCapturedTypes(in: $0) }))
        default:
            return type
        }
    }
}
