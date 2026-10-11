import RuntimeABI
import CompilerCore

extension NativeEmitter {
    /// Declarations are keyed only by name; if the first emitted call is arity-0 bootstrap noise
    /// (e.g. synthetic kotlin.math loads) and a later call passes arguments, LLVM must still
    /// declare the symbol with the maximum arity seen for declareExternalFunction.
    static func maxKIRArgumentCountByExternalCallee(
        body: [KIRInstruction],
        interner: StringInterner
    ) -> [String: Int] {
        var maxCount: [String: Int] = [:]
        for instruction in body {
            switch instruction {
            case let .call(_, callee, arguments, _, _, _, _, _):
                let raw = interner.resolve(callee)
                guard !raw.isEmpty else { continue }
                let effective = effectiveExternalCalleeNameForArity(raw, argumentCount: arguments.count)
                maxCount[effective, default: 0] = max(maxCount[effective, default: 0], arguments.count)
            case .virtualCall:
                // Generic virtual calls use an arity-qualified declaration
                // (for example, `size__v1`) solely as the indirect-call type.
                // Folding their receiver-plus-argument count into the plain
                // external name can widen an unrelated direct runtime bridge
                // declaration such as `__kk_map_size(i64)` to four parameters.
                continue
            default:
                break
            }
        }
        return maxCount
    }

    private static func effectiveExternalCalleeNameForArity(_ calleeName: String, argumentCount: Int) -> String {
        if isStringLengthAggregateAccessorName(calleeName), argumentCount == 1 {
            "__kk_string_struct_get_length"
        } else {
            calleeName
        }
    }

    static func isStringLengthAggregateAccessorName(_ calleeName: String) -> Bool {
        calleeName == "length"
            || calleeName == "__kk_string_struct_get_length"
            || calleeName == "kk_string_struct_get_length"
    }

    static func runtimePrimitiveAlias(
        for calleeName: String,
        argumentCount: Int,
        resolvedSymbol: SymbolID?
    ) -> String? {
        if ["and", "or", "xor"].contains(calleeName),
           let resolvedSymbol,
           resolvedSymbol != .invalid
        {
            return nil
        }
        return switch calleeName {
        case "and": "kk_bitwise_and"
        case "or": "kk_bitwise_or"
        case "xor": "kk_bitwise_xor"
        case "__doubleRoundToInt": "kk_double_roundToInt"
        case "__floatRoundToInt": "kk_float_roundToInt"
        case "__doubleRoundToLong": "kk_double_roundToLong"
        case "__floatRoundToLong": "kk_float_roundToLong"
        case "__assert": "kk_precondition_assert"
        case "__assertLazy": "kk_precondition_assert_lazy"
        default: nil
        }
    }
}
