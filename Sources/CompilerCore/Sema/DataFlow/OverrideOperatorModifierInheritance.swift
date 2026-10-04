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
///
/// Only overrides declared in user source inherit the flag. Bundled stdlib
/// declarations keep exactly the modifiers they spell out: several of them
/// (for example `ULongProgression.iterator`) describe values that are
/// runtime range boxes without a Kotlin vtable, and flagging them as
/// operators reroutes `for`/`in` resolution away from their runtime bridges
/// onto a virtual call that cannot dispatch. Imported library symbols carry
/// their serialized flags and are skipped for the same reason.
extension DataFlowSemaPhase {
    func inheritOperatorModifierForOverrides(
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager
    ) {
        var pending = symbols.allSymbols()
            .filter {
                guard $0.kind == .function,
                      $0.flags.contains(.overrideMember),
                      !$0.flags.contains(.operatorFunction),
                      !$0.flags.contains(.importedLibrary),
                      let fileID = $0.declSite?.start.file
                else { return false }
                return sourceManager.origin(of: fileID)?.isBundledStdlib != true
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
