/// Kotlin's `operator` modifier is inherited by overrides: an `override`
/// of an `operator fun` is itself usable through operator syntax even when
/// the override does not repeat the keyword.
///
/// ```kotlin
/// open class A { open operator fun plus(n: Int) = n }
/// class B : A() { override fun plus(n: Int) = n * 2 }
/// fun main() {
///     println(B() + 1)  // 2
/// }
/// ```
///
/// `HeaderHelpers.flags(from:)` sets `.operatorFunction` purely from the
/// declaration's own modifiers, and every operator-resolution filter in
/// `ExprTypeChecker` / `CallTypeChecker` keys off that flag, so `B.plus`
/// above used to be dropped and the call rejected with `KSWIFTK-SEMA-0002`.
///
/// This pass runs alongside `inheritDefaultArgumentValuesForOverrides`
/// (same supertype matching via `nearestOverriddenFunctionCandidates`) and
/// copies `.operatorFunction` onto every override whose overridden
/// declaration carries it. It iterates to a fixpoint so a chain of
/// intermediate keyword-less overrides inherits regardless of the order
/// `symbols.allSymbols()` visits them in.
extension DataFlowSemaPhase {
    func inheritOperatorModifierForOverrides(
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        var pending = symbols.allSymbols()
            .filter {
                $0.kind == .function
                    && $0.flags.contains(.overrideMember)
                    && !$0.flags.contains(.operatorFunction)
            }
            .map(\.id)
        var changed = true
        while changed, !pending.isEmpty {
            changed = false
            pending.removeAll { id in
                let inheritsOperator = nearestOverriddenFunctionCandidates(
                    of: id, symbols: symbols, types: types
                ).contains {
                    symbols.symbol($0)?.flags.contains(.operatorFunction) == true
                }
                guard inheritsOperator else { return false }
                symbols.insertFlags(.operatorFunction, for: id)
                changed = true
                return true
            }
        }
    }
}
