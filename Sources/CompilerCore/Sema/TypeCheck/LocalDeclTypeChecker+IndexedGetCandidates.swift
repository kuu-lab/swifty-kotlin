extension LocalDeclTypeChecker {
    /// Keep lexical priority among applicable operators. A nearer declaration
    /// that cannot accept the receiver or indices must not hide an outer one.
    func collectIndexedOperatorExtensionCandidates(
        named name: InternedString,
        receiverType: TypeID,
        call: CallExpr? = nil,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        func matches(_ candidate: SymbolID) -> Bool {
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  driver.helpers.declaresExtensionReceiver(candidate, sema: sema, interner: ctx.interner),
                  !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols),
                  ctx.visibilityChecker.isAccessible(
                      symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                  ),
                  !(symbol.flags.contains(.expectDeclaration) && sema.symbols.actualSymbol(for: candidate) != nil),
                  driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                      callSiteReceiver: nonNullReceiver, declaredReceiver: declaredReceiver, sema: sema
                  )
            else { return false }
            guard let call else { return true }
            return !ctx.resolver.probeCall(
                candidates: [candidate], call: call, expectedType: nil,
                implicitReceiverType: receiverType, ctx: sema
            ).viableCandidates.isEmpty
        }

        let localCandidates = driver.exprChecker.collectLocalOperatorExtensionCandidates(
            names: [name], receiverType: receiverType, call: call, locals: locals, ctx: ctx
        )
        if !localCandidates.isEmpty { return localCandidates }

        let memberExtensionCandidates = collectIndexedOperatorMemberExtensionCandidates(
            named: name, receiverType: receiverType, call: call, ctx: ctx
        )
        if !memberExtensionCandidates.isEmpty { return memberExtensionCandidates }

        let scoped = ctx.scope.lookup(name, matching: matches)
        if !scoped.isEmpty { return scoped }

        let synthetic = sema.symbols.lookupByShortName(name).filter { candidate in
            // Imported user extensions require a lexical import. Bundled atomic
            // extensions retain their dedicated importless fallback below.
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.importedLibrary)
            else { return false }
            if let parent = sema.symbols.parentSymbol(for: candidate),
               sema.symbols.symbol(parent)?.kind == .property
            {
                return false
            }
            return matches(candidate)
        }
        if !synthetic.isEmpty { return synthetic }

        return driver.callChecker.collectBundledStdlibExtensionCandidates(
            named: name, receiverType: receiverType, requireOperator: true,
            sourceFile: ctx.currentASTFile, sema: sema, interner: ctx.interner
        ).filter(matches)
    }

    /// Member extensions are declared on an implicit dispatch receiver while
    /// their extension receiver is the indexed value (for example, a
    /// `Long.get` declared inside an object used by `with`). Keep this tier
    /// ahead of package-scope extensions, matching ordinary operator lookup.
    func collectIndexedOperatorMemberExtensionCandidates(
        named name: InternedString,
        receiverType: TypeID,
        call: CallExpr? = nil,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)

        func matches(_ candidate: SymbolID) -> Bool {
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(.operatorFunction),
                  sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  driver.helpers.declaresExtensionReceiver(candidate, sema: sema, interner: ctx.interner),
                  !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols),
                  ctx.visibilityChecker.isAccessible(
                      symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                  ),
                  !(symbol.flags.contains(.expectDeclaration) && sema.symbols.actualSymbol(for: candidate) != nil),
                  driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                      callSiteReceiver: nonNullReceiver, declaredReceiver: declaredReceiver, sema: sema
                  ),
                  !ctx.isCandidateBlockedByDslMarker(candidate)
            else {
                return false
            }

            guard let call else { return true }
            return !ctx.resolver.probeCall(
                candidates: [candidate], call: call, expectedType: nil,
                implicitReceiverType: receiverType, ctx: sema
            ).viableCandidates.isEmpty
        }

        for dispatchReceiver in ctx.implicitReceiverMemberLookupEntries() {
            let candidates = driver.helpers.collectMemberFunctionCandidates(
                named: name, receiverType: dispatchReceiver.type, sema: sema, interner: ctx.interner
            ).filter(matches)
            guard !candidates.isEmpty else { continue }
            if let call {
                let viable = ctx.resolver.probeCall(
                    candidates: candidates, call: call, expectedType: nil,
                    implicitReceiverType: receiverType, ctx: sema
                ).viableCandidates.map(\.symbol)
                if !viable.isEmpty { return viable }
            } else {
                return candidates
            }
        }
        return []
    }

    /// Returns the implicit dispatch receiver selected for a member-extension
    /// operator. The active `with` receiver has no symbol here and is supplied
    /// by the lowering context; outer receivers retain their capture symbol.
    func indexedOperatorDispatchReceiverSymbol(
        for candidate: SymbolID,
        named name: InternedString,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        guard ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil else { return nil }
        return ctx.implicitReceiverMemberLookupEntries().first { entry in
            driver.helpers.collectMemberFunctionCandidates(
                named: name, receiverType: entry.type, sema: ctx.sema, interner: ctx.interner
            ).contains(candidate)
        }?.symbol
    }
}
