import Foundation

/// VAL-001: Value class unboxing lowering pass.
///
/// Rewrites KIR instructions that reference value class types so that at
/// the ABI level they operate on the underlying primitive type directly:
///
/// - **Constructor calls** for a value class become a simple copy of the
///   single argument to the result.  `Meter(42)` -> `copy(42, result)`.
///
/// - **Property getter calls** for the single wrapped property become a
///   copy of the receiver to the result.  `m.amount` -> `copy(m, result)`.
///
/// This pass must run **before** ABILoweringPass, which handles boxing
/// when the unboxed primitive crosses an ABI boundary (e.g. `Meter -> Any`).
final class ValueClassUnboxingPass: LoweringPass {
    static let name = "ValueClassUnboxing"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else {
            return false
        }
        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else {
                continue
            }
            guard let sym = sema.symbols.symbol(nominal.symbol) else {
                continue
            }
            if sym.flags.contains(.valueType),
               sema.symbols.valueClassUnderlyingType(for: nominal.symbol) != nil
            {
                return true
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols

        // Collect the set of value class symbols, their constructor symbols
        // and their single-property getter symbols.
        var valueClassSymbols: Set<SymbolID> = []
        var valueClassCtors: Set<SymbolID> = []
        var valueClassPropertyGetters: Set<SymbolID> = []

        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else {
                continue
            }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  let underlyingType = symbols.valueClassUnderlyingType(for: nominal.symbol)
            else {
                continue
            }
            valueClassSymbols.insert(nominal.symbol)

            // Find child symbols (constructors, properties) by fqName.
            let children = symbols.children(ofFQName: sym.fqName)
            for childID in children {
                guard let child = symbols.symbol(childID) else {
                    continue
                }
                if child.kind == .constructor {
                    valueClassCtors.insert(childID)
                }
                // Only collect the single primary-constructor-backed property,
                // not computed properties defined in the class body (e.g.
                // `val doubled: Int get() = amount * 2`).  We identify it by
                // matching its propertyType against the recorded underlying
                // type of the value class.
                if child.kind == .property || child.kind == .field {
                    if let propType = symbols.propertyType(for: childID),
                       propType == underlyingType
                    {
                        valueClassPropertyGetters.insert(childID)
                    }
                }
            }
        }

        guard !valueClassCtors.isEmpty || !valueClassPropertyGetters.isEmpty else {
            module.recordLowering(Self.name)
            return
        }

        module.arena.transformFunctions { function in
            var updated = function
            let newBody = self.rewriteBody(
                function.body,
                valueClassCtors: valueClassCtors,
                valueClassPropertyGetters: valueClassPropertyGetters
            )
            updated.replaceBody(newBody)
            return updated
        }

        module.recordLowering(Self.name)
    }

    private func rewriteBody(
        _ body: [KIRInstruction],
        valueClassCtors: Set<SymbolID>,
        valueClassPropertyGetters: Set<SymbolID>
    ) -> [KIRInstruction] {
        body.map { instruction in
            switch instruction {
            // Rewrite value class constructor calls:
            // call <init>(receiver, arg) result -> copy(arg, result)
            //
            // Value classes have exactly one primary constructor parameter, so
            // we only rewrite when the argument count is exactly 2 (receiver +
            // value) or exactly 1 (value only, no explicit receiver).  If the
            // arity does not match, leave the instruction unchanged so we do
            // not silently mis-compile unexpected calling conventions.
            case let .call(symbol, callee: _, arguments, result, canThrow: _, thrownResult: _, isSuperCall: _):
                if let symbol, valueClassCtors.contains(symbol),
                   let result
                {
                    if arguments.count == 2 {
                        // arguments[0] is receiver (the class instance), arguments[1] is the value
                        return .copy(from: arguments[1], to: result)
                    } else if arguments.count == 1 {
                        // arguments[0] is the value (no explicit receiver)
                        return .copy(from: arguments[0], to: result)
                    }
                    // Unexpected arity -- leave instruction as-is.
                }
                return instruction

            // Rewrite property getter calls on value class:
            // virtualCall getter(receiver) result -> copy(receiver, result)
            case let .virtualCall(symbol, callee: _, receiver, arguments: _, result, canThrow: _, thrownResult: _, dispatch: _):
                if let symbol, valueClassPropertyGetters.contains(symbol),
                   let result
                {
                    return .copy(from: receiver, to: result)
                }
                return instruction

            default:
                return instruction
            }
        }
    }
}
