/// KUU-655: Kotlin lets an `override` omit the argument(s) for parameters
/// whose *base* declaration carries a default value, even when the override
/// itself declares none (re-declaring one is a separate, unenforced rule --
/// see the diagnostic note below):
///
/// ```kotlin
/// open class A { open fun f(x: Int = 1) = "A$x" }
/// class B : A() { override fun f(x: Int) = "B$x" }
/// fun main() {
///     println(B().f())  // "B1" -- B.f has no default of its own, but A.f's applies
/// }
/// ```
///
/// Before this pass, `MemberHeaderCollection` builds every function's
/// `FunctionSignature.valueParameterHasDefaultValues` purely from that
/// function's own AST parameters (`HeaderHelpers.collectValueParameters`),
/// so `B.f`'s flags are all `false` and the call above is rejected with
/// `KSWIFTK-SEMA-0002` (`Resolution+TypeConstraints.buildParameterMapping`
/// requires a default flag to skip an unbound parameter).
///
/// This pass runs once all headers and inheritance edges exist (see
/// `Phase.runValidationPasses`) and, for every `override` function whose own
/// declaration has no default value, walks its supertype chain for the
/// nearest matching declaration that does, then copies that declaration's
/// default-value flags onto the override's stored signature. It also records
/// the *original* owning symbol in `overrideDefaultsBaseSymbol` (walking
/// through any number of intermediate overrides that themselves lack their
/// own defaults) so KIR call-site lowering knows which declaration's
/// `$default` stub to route through -- the override itself never gets one,
/// since its AST has no default expressions to evaluate. See
/// `CallSupportLowerer.defaultStubOwnerSymbol` and
/// `CallSupportLowerer.generateDefaultStubFunction`'s virtual-dispatch call
/// for the KIR side of this fix.
///
/// A `by`-delegation forwarding method (`Inheritance.synthesizeForwardingMethod`)
/// is itself an `override` with all-false default flags and a `parentSymbol`/
/// `directSupertypes` edge to the delegated interface, so it is covered by
/// this same walk without any special-casing -- this pass is intentionally
/// scheduled after `synthesizeClassDelegationForwardingMethodSymbols` in
/// `Phase.runValidationPasses`.
///
/// Not covered: object-literal member overrides (`object : A() { override
/// fun f(x: Int) = ... }`), whose override symbols are only created later,
/// during body analysis (`ExprTypeChecker+ObjectLiteralInference`), after
/// this pass has already run. That is a narrower, separate gap -- tracked
/// alongside this fix's Linear ticket rather than fixed here.
extension DataFlowSemaPhase {
    func inheritDefaultArgumentValuesForOverrides(
        symbols: SymbolTable,
        types: TypeSystem
    ) {
        let functionSymbols = symbols.allSymbols().filter { $0.kind == .function }

        // Snapshot each function's *own* declared default-value flags before
        // any mutation below. Without this, resolution order over
        // `symbols.allSymbols()` (which is not guaranteed to visit a base
        // before its override) could read a signature this same pass already
        // rewrote, silently turning "does this override have its own
        // default?" into "did *anything* upstream have one?" -- collapsing a
        // 3-level chain's distinctions and making diamond resolution
        // order-dependent.
        var ownDefaultsSnapshot: [SymbolID: [Bool]] = [:]
        ownDefaultsSnapshot.reserveCapacity(functionSymbols.count)
        for sym in functionSymbols {
            if let signature = symbols.functionSignature(for: sym.id) {
                ownDefaultsSnapshot[sym.id] = signature.valueParameterHasDefaultValues
            }
        }

        func hasOwnDefault(_ id: SymbolID) -> Bool {
            ownDefaultsSnapshot[id]?.contains(true) ?? false
        }

        var resolvedBase: [SymbolID: SymbolID] = [:]
        var inProgress: Set<SymbolID> = []

        // Finds the nearest ancestor declaration (by BFS over
        // `directSupertypes`, same traversal shape as
        // `OpenFinalOverride.findAllInheritedMembers`) that supplies this
        // override's defaults, resolving transitively through any
        // intermediate override that itself has none of its own. Diamond
        // inheritance (`class C : A(), I` where both declare `f`) resolves
        // to whichever matching candidate the BFS reaches first; Kotlin
        // requires such a diamond to already agree on defaults (or the
        // override to redeclare its own), so any two matches here are
        // expected to carry the same effective flags.
        func resolve(_ id: SymbolID) -> SymbolID? {
            if let cached = resolvedBase[id] { return cached }
            if hasOwnDefault(id) { return nil }
            guard !inProgress.contains(id) else { return nil }
            inProgress.insert(id)
            defer { inProgress.remove(id) }

            guard let sym = symbols.symbol(id),
                  sym.flags.contains(.overrideMember),
                  let ownerID = symbols.parentSymbol(for: id),
                  let signature = symbols.functionSignature(for: id)
            else { return nil }

            let paramCount = signature.parameterTypes.count
            var visited: Set<SymbolID> = [ownerID]
            var queue = symbols.directSupertypes(for: ownerID)
            while !queue.isEmpty {
                let currentOwner = queue.removeFirst()
                guard visited.insert(currentOwner).inserted else { continue }
                guard let ownerSym = symbols.symbol(currentOwner) else { continue }

                var foundAtThisLevel = false
                for candidateID in symbols.children(ofFQName: ownerSym.fqName) {
                    guard let candidate = symbols.symbol(candidateID),
                          candidate.kind == .function,
                          candidate.name == sym.name,
                          let candidateSig = symbols.functionSignature(for: candidateID),
                          candidateSig.parameterTypes.count == paramCount,
                          candidateSig.isSuspend == signature.isSuspend,
                          isOverrideVtableParameterMatch(
                              candidateParameterTypes: candidateSig.parameterTypes,
                              overrideParameterTypes: signature.parameterTypes,
                              types: types
                          )
                    else { continue }
                    foundAtThisLevel = true
                    if hasOwnDefault(candidateID) {
                        return candidateID
                    }
                    if candidate.flags.contains(.overrideMember), let deeper = resolve(candidateID) {
                        return deeper
                    }
                }
                // Mirrors `findAllInheritedMembers`: once a level declares
                // this member (even without defaults of its own), stop --
                // an ancestor beyond it is an earlier override of the same
                // logical member, not an independent candidate.
                if !foundAtThisLevel {
                    queue.append(contentsOf: symbols.directSupertypes(for: currentOwner))
                }
            }
            return nil
        }

        for sym in functionSymbols where sym.flags.contains(.overrideMember) {
            guard !hasOwnDefault(sym.id) else { continue }
            if let base = resolve(sym.id) {
                resolvedBase[sym.id] = base
            }
        }

        for (overrideID, baseID) in resolvedBase {
            guard let signature = symbols.functionSignature(for: overrideID) else { continue }
            let paramCount = signature.parameterTypes.count
            let baseDefaults = ownDefaultsSnapshot[baseID] ?? []
            let normalizedBaseDefaults: [Bool] = if baseDefaults.count == paramCount {
                baseDefaults
            } else if baseDefaults.count > paramCount {
                Array(baseDefaults.prefix(paramCount))
            } else {
                baseDefaults + Array(repeating: false, count: paramCount - baseDefaults.count)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    parameterTypes: signature.parameterTypes,
                    returnType: signature.returnType,
                    isSuspend: signature.isSuspend,
                    canThrow: signature.canThrow,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: normalizedBaseDefaults,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                    classTypeParameterCount: signature.classTypeParameterCount
                ),
                for: overrideID
            )
            symbols.setOverrideDefaultsBaseSymbol(baseID, for: overrideID)
        }
    }
}
