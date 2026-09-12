import Foundation
import RuntimeABI

struct KIRVerificationFailure: Equatable {
    enum Kind: Equatable {
        case duplicateLabel
        case undefinedJumpTarget
        case undefinedRegisterRead
        case instructionLocationCountMismatch
        case unresolvableCallee
    }

    let kind: Kind
    let functionName: String
    let instructionIndex: Int?
    let message: String
}

/// Structural sanity checks on lowered KIR function bodies. The checks are
/// deliberately flow-insensitive: a register read counts as defined when any
/// instruction in the same function defines it, and jump targets only need a
/// matching label somewhere in the same body.
struct KIRVerifier {
    /// Default: on in DEBUG builds, off otherwise. `KSWIFTK_KIR_VERIFY=1|0` overrides.
    static var isEnabled: Bool {
        if let override = ProcessInfo.processInfo.environment["KSWIFTK_KIR_VERIFY"] {
            if override == "1" { return true }
            if override == "0" { return false }
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static let maxFailuresPerFunction = 20

    static func verify(
        module: KIRModule,
        symbols: SymbolTable?,
        interner: StringInterner
    ) -> [KIRVerificationFailure] {
        var moduleFunctionNames: Set<InternedString> = []
        var moduleFunctionSymbols: Set<SymbolID> = []
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            moduleFunctionNames.insert(function.name)
            moduleFunctionSymbols.insert(function.symbol)
        }
        let runtimeCalleeNames = Set(RuntimeABISpec.allFunctions.lazy.map(\.name))
            .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames)
            .union(RuntimeABISpec.compilerInternalBuiltinCalleeNames)

        var failures: [KIRVerificationFailure] = []
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            verify(
                function: function,
                module: module,
                moduleFunctionNames: moduleFunctionNames,
                moduleFunctionSymbols: moduleFunctionSymbols,
                runtimeCalleeNames: runtimeCalleeNames,
                symbols: symbols,
                interner: interner,
                into: &failures
            )
        }
        return failures
    }

    private static func verify(
        function: KIRFunction,
        module: KIRModule,
        moduleFunctionNames: Set<InternedString>,
        moduleFunctionSymbols: Set<SymbolID>,
        runtimeCalleeNames: Set<String>,
        symbols: SymbolTable?,
        interner: StringInterner,
        into failures: inout [KIRVerificationFailure]
    ) {
        let functionName = interner.resolve(function.name)
        var emitted = 0
        func report(_ kind: KIRVerificationFailure.Kind, _ index: Int?, _ message: String) {
            guard emitted < maxFailuresPerFunction else { return }
            emitted += 1
            failures.append(KIRVerificationFailure(
                kind: kind,
                functionName: functionName,
                instructionIndex: index,
                message: "\(functionName): \(message)"
            ))
        }

        var definedLabels: Set<Int32> = []
        var definedExprs: Set<KIRExprID> = []
        for instruction in function.body {
            switch instruction {
            case let .label(id):
                definedLabels.insert(id)
            case let .constValue(result, _):
                definedExprs.insert(result)
            case let .binary(_, _, _, result):
                definedExprs.insert(result)
            case let .unary(_, _, result):
                definedExprs.insert(result)
            case let .nullAssert(_, result):
                definedExprs.insert(result)
            case let .call(_, _, _, result, _, thrownResult, _, _):
                if let result { definedExprs.insert(result) }
                if let thrownResult { definedExprs.insert(thrownResult) }
            case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
                if let result { definedExprs.insert(result) }
                if let thrownResult { definedExprs.insert(thrownResult) }
            case let .copy(_, to):
                definedExprs.insert(to)
            case let .loadGlobal(result, _):
                definedExprs.insert(result)
            default:
                break
            }
        }

        if function.instructionLocations.count != function.body.count {
            report(
                .instructionLocationCountMismatch,
                nil,
                "instructionLocations has \(function.instructionLocations.count) entries for \(function.body.count) instructions"
            )
        }

        var seenLabels: Set<Int32> = []
        for (index, instruction) in function.body.enumerated() {
            switch instruction {
            case let .label(id):
                if !seenLabels.insert(id).inserted {
                    report(.duplicateLabel, index, "duplicate label \(id)")
                }
            case let .jump(target):
                if !definedLabels.contains(target) {
                    report(.undefinedJumpTarget, index, "jump to undefined label \(target)")
                }
            case let .jumpIfEqual(lhs, rhs, target):
                if !definedLabels.contains(target) {
                    report(.undefinedJumpTarget, index, "jumpIfEqual to undefined label \(target)")
                }
                checkRead(lhs, index: index, definedExprs: definedExprs, module: module, report: report)
                checkRead(rhs, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .jumpIfNotNull(value, target):
                if !definedLabels.contains(target) {
                    report(.undefinedJumpTarget, index, "jumpIfNotNull to undefined label \(target)")
                }
                checkRead(value, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .binary(_, lhs, rhs, _):
                checkRead(lhs, index: index, definedExprs: definedExprs, module: module, report: report)
                checkRead(rhs, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .unary(_, operand, _):
                checkRead(operand, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .nullAssert(operand, _):
                checkRead(operand, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .call(symbol, callee, arguments, _, _, _, _, _):
                for argument in arguments {
                    checkRead(argument, index: index, definedExprs: definedExprs, module: module, report: report)
                }
                if !isResolvableCallee(
                    callee: callee,
                    symbol: symbol,
                    moduleFunctionNames: moduleFunctionNames,
                    moduleFunctionSymbols: moduleFunctionSymbols,
                    runtimeCalleeNames: runtimeCalleeNames,
                    symbols: symbols,
                    interner: interner
                ) {
                    report(
                        .unresolvableCallee,
                        index,
                        "call to '\(interner.resolve(callee))' does not resolve to a module function, an external link name, or a runtime ABI function"
                    )
                }
            case let .virtualCall(_, _, receiver, arguments, _, _, _, _):
                checkRead(receiver, index: index, definedExprs: definedExprs, module: module, report: report)
                for argument in arguments {
                    checkRead(argument, index: index, definedExprs: definedExprs, module: module, report: report)
                }
            case let .copy(from, _):
                checkRead(from, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .storeGlobal(value, _):
                checkRead(value, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .rethrow(value):
                checkRead(value, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .returnIfEqual(lhs, rhs):
                checkRead(lhs, index: index, definedExprs: definedExprs, module: module, report: report)
                checkRead(rhs, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .returnValue(value):
                checkRead(value, index: index, definedExprs: definedExprs, module: module, report: report)
            case let .nonLocalReturn(value):
                if let value {
                    checkRead(value, index: index, definedExprs: definedExprs, module: module, report: report)
                }
            default:
                break
            }
        }
    }

    /// A read is legal when some instruction in the same function defines the
    /// expression, or when the expression is not a `.temporary` slot that must
    /// be materialized (literals, symbol refs, null, unit, ...).
    private static func checkRead(
        _ exprID: KIRExprID,
        index: Int,
        definedExprs: Set<KIRExprID>,
        module: KIRModule,
        report: (KIRVerificationFailure.Kind, Int?, String) -> Void
    ) {
        if definedExprs.contains(exprID) { return }
        if let kind = module.arena.expr(exprID), case let .temporary(raw) = kind {
            // `ImportedInlineKIRMaterializer` maps imported-body IDs that have
            // no defining instruction (implicit exception slots observed only
            // by throw checks) to the `.temporary(0)` sentinel; codegen emits
            // it as the constant-zero fallback, so the read is legal.
            if raw == 0 { return }
            report(.undefinedRegisterRead, index, "expression \(exprID.rawValue) is read but never defined in this function")
        }
    }

    private static func isResolvableCallee(
        callee: InternedString,
        symbol: SymbolID?,
        moduleFunctionNames: Set<InternedString>,
        moduleFunctionSymbols: Set<SymbolID>,
        runtimeCalleeNames: Set<String>,
        symbols: SymbolTable?,
        interner: StringInterner
    ) -> Bool {
        if moduleFunctionNames.contains(callee) { return true }
        if let symbol {
            if moduleFunctionSymbols.contains(symbol) { return true }
            if let linkName = symbols?.externalLinkName(for: symbol), !linkName.isEmpty {
                return true
            }
            // Synthetic accessor/`$default`-stub symbols are never registered
            // in the table, but codegen resolves them structurally (internal
            // functions, itable, or `resolveUnnamedInternalFunction` by name).
            if SyntheticSymbolScheme.isSyntheticCallTarget(symbol) { return true }
            if let symbols {
                // Any symbol the table knows is resolvable at codegen:
                // functions/constructors via module or external names, and
                // callable values (value parameters, locals, properties)
                // via local-slot invokes — e.g. `action(...)` on a
                // function-typed parameter lowered without a
                // callableValueCallBinding keeps the parameter symbol.
                if let kind = symbols.symbol(symbol)?.kind {
                    switch kind {
                    case .function, .constructor, .valueParameter, .local,
                         .property, .field, .backingField:
                        return true
                    default:
                        break
                    }
                }
            } else {
                // Without a symbol table a bound symbol cannot be
                // disambiguated; treat it as resolvable.
                return true
            }
        }
        let calleeName = interner.resolve(callee)
        if runtimeCalleeNames.contains(calleeName) { return true }
        // `kk_fn_*` names are compiler-generated module link names; they
        // resolve at final link time against the emitted object symbols.
        if calleeName.hasPrefix(RuntimeABISpec.compilerGeneratedLinkNamePrefix) {
            return true
        }
        // Symbol-less calls still resolve in codegen by name (external
        // declarations are emitted under the callee name). Accept any declared
        // function/constructor symbol with that short name — e.g. bundled
        // stdlib `external fun __kk_*` primitives invoked without a symbol.
        if symbol == nil,
           let symbols,
           symbols.lookupByShortName(callee).contains(where: {
               let kind = symbols.symbol($0)?.kind
               return kind == .function || kind == .constructor
           })
        {
            return true
        }
        // `<name>$default` calls target the synthesized default-argument stub
        // whose symbol is derived (not registered in the table). The stub
        // exists iff the base declaration does, so check the base name.
        if symbol == nil,
           calleeName.hasSuffix("$default"),
           let symbols,
           symbols.lookupByShortName(
               interner.intern(String(calleeName.dropLast("$default".count)))
           ).contains(where: {
               let kind = symbols.symbol($0)?.kind
               return kind == .function || kind == .constructor
           })
        {
            return true
        }
        return false
    }
}
