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
