
extension ControlFlowLowerer {
    // MARK: - Custom Iterator Resolution (STDLIB-OP-032)

    /// Restricts BUG-198 to the signed range/progression classes and direct
    /// signed range expressions. Unsigned ranges, OpenEndRange, custom classes,
    /// and interface-typed values must continue through their existing lowering.
    func isBuiltInSignedRange(
        iterableExpr: ExprID,
        iterableType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        if sema.bindings.isUIntRangeExpr(iterableExpr)
            || sema.bindings.isULongRangeExpr(iterableExpr)
            || nonNullType == sema.types.uintType
            || nonNullType == sema.types.ulongType {
            return false
        }
        if sema.bindings.isRangeExpr(iterableExpr)
            || ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast)
            || isBuiltInRangeMemberCall(iterableExpr, ast: ast, sema: sema, interner: interner) {
            if nonNullType == sema.types.intType
                || nonNullType == sema.types.longType
                || nonNullType == sema.types.charType
            {
                return true
            }
            guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
                  isRangeLikeClass(symbol, sema: sema, interner: interner)
            else {
                return false
            }
            return KnownCompilerNames(interner: interner).isSignedRangeLikeClassName(symbol.name)
        }
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
              isRangeLikeClass(symbol, sema: sema, interner: interner)
        else {
            return false
        }
        return KnownCompilerNames(interner: interner).isSignedRangeLikeClassName(symbol.name)
    }

    /// `downTo` and `step` are represented as member-call nodes by the parser
    /// even though they are built-in range constructors. Use their resolved
    /// runtime links so a source-defined function with the same name is not
    /// mistaken for a built-in range.
    private func isBuiltInRangeMemberCall(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .memberCall(receiver, callee, _, _, _) = ast.arena.expr(exprID),
              ["until", "rangeUntil", "downTo", "step"].contains(interner.resolve(callee)),
              let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee,
              let linkName = sema.symbols.externalLinkName(for: chosen)
        else {
            return false
        }
        let signedLinks = [
            "__kk_op_rangeUntil",
            "__kk_op_downTo",
            "__kk_op_step",
            "__kk_char_range_step",
        ]
        guard signedLinks.contains(linkName) else {
            return false
        }
        if linkName == "__kk_op_step" || linkName == "__kk_char_range_step" {
            return isBuiltInSignedRange(
                iterableExpr: receiver,
                iterableType: sema.bindings.exprType(for: receiver) ?? sema.types.anyType,
                ast: ast,
                sema: sema,
                interner: interner
            )
        }
        return true
    }

    /// Resolved custom iterator operator chain: iterator(), hasNext(), next().
    struct CustomIteratorResolution {
        let iteratorSymbol: SymbolID
        let iteratorType: TypeID
        let hasNextSymbol: SymbolID
        let nextSymbol: SymbolID
    }

    /// Returns true when the class symbol is one of the built-in Range / Progression
    /// classes in `kotlin.ranges` that now provide bundled Kotlin `iterator()`
    /// operators. These synthetic classes are allowed to resolve a custom iterator
    /// so that `for-in` over a range is lowered through `.iterator()` instead of
    /// the legacy `kk_range_iterator` runtime path.
    func isRangeLikeClass(_ classSymbol: SemanticSymbol, sema: SemaModule, interner: StringInterner) -> Bool {
        KnownCompilerNames(interner: interner).isRangeLikeSymbol(classSymbol)
    }

    /// Looks for a non-synthetic bundled `operator fun Receiver.<name>()` extension
    /// (no value parameters) declared in the same package as the receiver's class.
    /// This is how KSP-312's `RangeIterators.kt` and KSP-678's `Channels.kt`
    /// iterator-layer operators are discovered for `for-in` lowering, since
    /// extension operators are not found through class-hierarchy member lookup.
    private func resolveBundledOperatorExtension(
        named name: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let classSymbol = resolveClassTypeSymbol(nonNullReceiverType, sema: sema)?.1
        let isCharSequenceLike = sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
            || (sema.types.charSequenceInterfaceSymbol.map { symbol in
                let charSequenceType = sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
                return sema.types.isSubtype(nonNullReceiverType, charSequenceType)
            } ?? false)
        guard isCharSequenceLike || classSymbol != nil else {
            return nil
        }
        var packageFQNames: [[InternedString]] = classSymbol.map { [Array($0.fqName.dropLast())] } ?? []
        if isCharSequenceLike {
            let textPackage = [interner.intern("kotlin"), interner.intern("text")]
            if !packageFQNames.contains(textPackage) {
                packageFQNames.append(textPackage)
            }
        }
        for packageFQName in packageFQNames {
            for candidate in sema.symbols.lookupAll(fqName: packageFQName + [name]) {
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      candidateSymbol.flags.contains(.operatorFunction),
                      (!candidateSymbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.isEmpty,
                      let candidateReceiverType = signature.receiverType
                else {
                    continue
                }
                if sema.types.isSubtype(receiverType, candidateReceiverType) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// KSP-452: a direct range expression (`for (i in 1..10)`, `downTo`, `until`,
    /// `step`) is typed as its element primitive plus a semantic range marker
    /// rather than as `kotlin.ranges.IntRange`, so the class-based lookup in
    /// `resolveCustomIteratorOperator` cannot see the bundled `iterator()`
    /// operator. Resolve it against the nominal range class instead, so a direct
    /// range loop uses the same `.iterator()` chain as a range held in an
    /// `IntRange` / `LongRange` / `CharRange` / `UIntRange` / `ULongRange` typed
    /// value.
    func resolveDirectRangeIteratorOperator(
        iterableExpr: ExprID,
        iterableType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> CustomIteratorResolution? {
        guard sema.bindings.isRangeExpr(iterableExpr)
            || ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast)
        else {
            return nil
        }
        let nonNullType = sema.types.makeNonNullable(iterableType)
        let rangeClassName: String
        if sema.bindings.isCharRangeExpr(iterableExpr) || nonNullType == sema.types.charType {
            rangeClassName = "CharRange"
        } else if sema.bindings.isULongRangeExpr(iterableExpr) || nonNullType == sema.types.ulongType {
            rangeClassName = "ULongRange"
        } else if sema.bindings.isUIntRangeExpr(iterableExpr) || nonNullType == sema.types.uintType {
            rangeClassName = "UIntRange"
        } else if nonNullType == sema.types.longType {
            rangeClassName = "LongRange"
        } else if nonNullType == sema.types.intType {
            rangeClassName = "IntRange"
        } else {
            return nil
        }
        guard let rangeClassSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern(rangeClassName),
        ]) else {
            return nil
        }
        let rangeType = sema.types.make(.classType(ClassType(
            classSymbol: rangeClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        return resolveCustomIteratorOperator(
            iterableType: rangeType,
            sema: sema,
            interner: interner
        )
    }

    /// Resolves user-defined `operator fun iterator()` on the iterable type,
    /// then resolves `hasNext()` and `next()` on the iterator return type.
    /// Returns nil if no custom iterator operator is defined.
    func resolveCustomIteratorOperator(
        iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> CustomIteratorResolution? {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        let isCharSequenceLike: Bool = {
            if sema.types.isSubtype(nonNullType, sema.types.stringType) {
                return true
            }
            guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol else {
                return false
            }
            let charSequenceType = sema.types.make(.classType(ClassType(
                classSymbol: charSequenceSymbol,
                args: [],
                nullability: .nonNull
            )))
            return sema.types.isSubtype(nonNullType, charSequenceType)
        }()
        // Only resolve for user-defined class types and bundled Range/Progression,
        // Channel, or source Sequence/Iterator classes whose `iterator()` operators
        // are now supplied by Kotlin source.
        let classSymbol = resolveClassTypeSymbol(nonNullType, sema: sema)?.1
        guard isCharSequenceLike || {
            guard let classSymbol else { return false }
            return !classSymbol.flags.contains(.synthetic)
                || isRangeLikeClass(classSymbol, sema: sema, interner: interner)
                || KnownCompilerNames(interner: interner).isChannelSymbol(classSymbol)
                || KnownCompilerNames(interner: interner).isSequenceSymbol(classSymbol)
                || sema.symbols.isSourceBackedSymbol(classSymbol.id)
        }() else {
            return nil
        }
        // KSP-441: Allow synthetic Sequence/Iterator symbols to resolve source `iterator()`.
        // Range-like types still fall through to the dedicated range intrinsics when
        // they have no operator iterator() candidate.

        let helpers = TypeCheckHelpers()
        let iteratorName = interner.intern("iterator")
        var iteratorCandidates = helpers.collectMemberFunctionCandidates(
            named: iteratorName,
            receiverType: nonNullType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  (!symbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate)),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }

        // Built-in Range/Progression and Channel classes expose their `iterator()`
        // as a bundled Kotlin extension rather than as a class member, so
        // `collectMemberFunctionCandidates` will not find it through
        // class-hierarchy lookup.
        if iteratorCandidates.isEmpty,
           let bundledIterator = resolveBundledOperatorExtension(
               named: iteratorName,
               receiverType: nonNullType,
               sema: sema,
               interner: interner
           )
        {
            iteratorCandidates = [bundledIterator]
        }

        guard let iteratorSymbol = iteratorCandidates.first,
              let iteratorSignature = sema.symbols.functionSignature(for: iteratorSymbol)
        else {
            return nil
        }

        let iteratorReturnType = iteratorSignature.returnType

        // Resolve hasNext() and next() on the iterator type. These may be real
        // members (e.g. kotlin.collections.Iterator) or bundled Kotlin extension
        // operators (e.g. the Channel iterator layer in Channels.kt).
        let hasNextName = interner.intern("hasNext")
        var hasNextCandidates = helpers.collectMemberFunctionCandidates(
            named: hasNextName,
            receiverType: iteratorReturnType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard sema.symbols.symbol(candidate) != nil,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }
        if hasNextCandidates.isEmpty,
           let bundledHasNext = resolveBundledOperatorExtension(
               named: hasNextName,
               receiverType: iteratorReturnType,
               sema: sema,
               interner: interner
           )
        {
            hasNextCandidates = [bundledHasNext]
        }

        let nextName = interner.intern("next")
        var nextCandidates = helpers.collectMemberFunctionCandidates(
            named: nextName,
            receiverType: iteratorReturnType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard sema.symbols.symbol(candidate) != nil,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }
        if nextCandidates.isEmpty,
           let bundledNext = resolveBundledOperatorExtension(
               named: nextName,
               receiverType: iteratorReturnType,
               sema: sema,
               interner: interner
           )
        {
            nextCandidates = [bundledNext]
        }

        guard let hasNextSymbol = hasNextCandidates.first,
              let nextSymbol = nextCandidates.first
        else {
            return nil
        }

        return CustomIteratorResolution(
            iteratorSymbol: iteratorSymbol,
            iteratorType: iteratorReturnType,
            hasNextSymbol: hasNextSymbol,
            nextSymbol: nextSymbol
        )
    }
}
