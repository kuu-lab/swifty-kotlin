extension TypeSystem {
    /// Replacing a captured argument by its upper bound is safe only where
    /// that argument occurs covariantly. Invariant results need a capture.
    func canApproximateCapturedUpperBound(
        in type: TypeID, parameter: SymbolID, position: TypeVariance = .out
    ) -> Bool {
        guard typeContainsTypeParam(type, symbol: parameter) else { return true }
        switch kind(of: type) {
        case .typeParam:
            return position == .out
        case let .classType(classType):
            let arguments = allTypeArguments(for: classType)
            let variances = allTypeParameterVariances(for: classType.classSymbol)
            return arguments.enumerated().allSatisfy { index, argument in
                let inner: TypeID
                let variance: TypeVariance
                let declarationVariance = variances.indices.contains(index) ? variances[index] : .invariant
                switch composedProjection(declarationVariance: declarationVariance, useSite: argument) {
                case let .invariant(type): (inner, variance) = (type, .invariant)
                case let .out(type): (inner, variance) = (type, .out)
                case let .in(type): (inner, variance) = (type, .in)
                case .star: return true
                case .invalid: return false
                }
                return canApproximateCapturedUpperBound(
                    in: inner, parameter: parameter, position: capturePosition(position, composedWith: variance)
                )
            }
        case let .functionType(function):
            let inputs = function.contextReceivers + (function.receiver.map { [$0] } ?? []) + function.params
            return inputs.allSatisfy {
                canApproximateCapturedUpperBound(in: $0, parameter: parameter, position: capturePosition(position, composedWith: .in))
            } && canApproximateCapturedUpperBound(in: function.returnType, parameter: parameter, position: position)
        case let .kClassType(kClass):
            return canApproximateCapturedUpperBound(in: kClass.argument, parameter: parameter, position: .invariant)
        case let .intersection(parts):
            return parts.allSatisfy { canApproximateCapturedUpperBound(in: $0, parameter: parameter, position: position) }
        default:
            return false
        }
    }

    private func capturePosition(_ outer: TypeVariance, composedWith inner: TypeVariance) -> TypeVariance {
        if outer == .invariant || inner == .invariant { return .invariant }
        return outer == inner ? .out : .in
    }
}
