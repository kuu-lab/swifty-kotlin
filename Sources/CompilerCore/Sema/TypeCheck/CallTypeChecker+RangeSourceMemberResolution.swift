import Foundation

// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func floatingPointRangeArgumentType(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let rangeFQName = sema.bindings.isOpenFloatingPointRangeExpr(exprID)
            ? knownNames.kotlinRangesPackage + [interner.intern("OpenEndRange")]
            : knownNames.kotlinRangesClosedFloatingPointRangeFQName
        guard sema.bindings.isFloatingPointRangeExpr(exprID),
              let rangeSymbol = sema.symbols.lookup(
                  fqName: rangeFQName
              )
        else {
            return nil
        }
        if let inferredType = sema.bindings.exprType(for: exprID),
           driver.helpers.isRangeLikeType(inferredType, sema: sema, interner: interner)
        {
            return inferredType
        }
        let elementType: TypeID = if let elementType = sema.bindings.floatingPointRangeElementType(forExpr: exprID) {
            elementType
        } else if case let .binary(_, lhs, rhs, _) = ast.arena.expr(exprID),
                  sema.bindings.exprType(for: lhs) == sema.types.floatType
                      || sema.bindings.exprType(for: rhs) == sema.types.floatType
        {
            sema.types.floatType
        } else {
            sema.types.doubleType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: rangeSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func isBundledRangeSourceMember(
        _ calleeName: InternedString,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        return knownNames.bundledRangeSourceMemberNames.contains(calleeName)
    }

    func sourceLevelRangeMemberLookupType(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        allowSyntacticRangeExpression: Bool = false
    ) -> TypeID? {
        guard let rangeKind = sourceLevelRangeMemberReceiverKind(
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            sema: sema,
            interner: interner,
            allowSyntacticRangeExpression: allowSyntacticRangeExpression
        ) else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        let typeID: InternedString
        switch rangeKind {
        case .intRange:
            typeID = knownNames.intRange
        case .longRange:
            typeID = knownNames.longRange
        case .charRange:
            typeID = knownNames.charRange
        case .uintRange:
            typeID = knownNames.uintRange
        case .ulongRange:
            typeID = knownNames.ulongRange
        case .intProgression:
            typeID = knownNames.intProgression
        case .longProgression:
            typeID = knownNames.longProgression
        case .charProgression:
            typeID = knownNames.charProgression
        case .uintProgression:
            typeID = knownNames.uintProgression
        case .ulongProgression:
            typeID = knownNames.ulongProgression
        case .iterable, .list, .set, .collection, .map, .sequence, .string, .charSequence:
            return nil
        }

        guard let symbol = sema.symbols.lookup(
            fqName: knownNames.kotlinRangesPackage + [typeID]
        ) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func sourceLevelRangeMemberReceiverKind(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        allowSyntacticRangeExpression: Bool = false
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) {
            let knownNames = KnownCompilerNames(interner: interner)
            switch symbol.name {
            case knownNames.intRange:
                return .intRange
            case knownNames.longRange:
                return .longRange
            case knownNames.charRange:
                return .charRange
            case knownNames.uintRange:
                return .uintRange
            case knownNames.ulongRange:
                return .ulongRange
            case knownNames.intProgression:
                return .intProgression
            case knownNames.longProgression:
                return .longProgression
            case knownNames.charProgression:
                return .charProgression
            case knownNames.uintProgression:
                return .uintProgression
            case knownNames.ulongProgression:
                return .ulongProgression
            default:
                return nil
            }
        }

        guard sema.bindings.isRangeExpr(receiverExpr) || allowSyntacticRangeExpression else {
            return nil
        }
        if sema.bindings.isFloatingPointRangeExpr(receiverExpr) {
            return nil
        }
        if sema.bindings.isCharRangeExpr(receiverExpr) {
            return .charRange
        }
        if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
            return .ulongRange
        }
        if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
            return .uintRange
        }
        if nonNullReceiverType == sema.types.longType {
            return .longRange
        }
        if nonNullReceiverType == sema.types.intType {
            return .intRange
        }
        return nil
    }

    func collectRangeSourceExtensionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let knownNames = KnownCompilerNames(interner: interner)
        let rangesFQName = knownNames.kotlinRangesPackage
        guard let rangesPackageSymbol = sema.symbols.lookup(fqName: rangesFQName) else {
            return []
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        let isUIntRangeReceiver: Bool = {
            guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema) else {
                return false
            }
            return symbol.name == knownNames.uintRange || symbol.name == knownNames.uintProgression
        }()
        let isUIntRangeMigrationMember = isUIntRangeReceiver
            && knownNames.rangeMigrationMemberNames.contains(calleeName)
        let isULongRangeReceiver: Bool = {
            guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema) else {
                return false
            }
            return symbol.name == knownNames.ulongRange || symbol.name == knownNames.ulongProgression
        }()
        let isULongRangeMigrationMember = isULongRangeReceiver
            && knownNames.rangeMigrationMemberNames.contains(calleeName)
        let isULongProgressionReceiver: Bool = {
            guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema) else {
                return false
            }
            return symbol.name == knownNames.ulongProgression
        }()
        let isULongProgressionFirstLastMember = isULongProgressionReceiver
            && knownNames.progressionFirstLastMemberNames.contains(calleeName)
        return sema.symbols.lookupAll(fqName: rangesFQName + [calleeName])
            .filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      (!symbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate)),
                      (sema.symbols.parentSymbol(for: candidate) == rangesPackageSymbol
                          || ((isUIntRangeMigrationMember || isULongProgressionFirstLastMember || isULongRangeMigrationMember)
                              && sema.symbols.isSourceBackedSymbol(candidate))),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            }
            .sorted { $0.rawValue < $1.rawValue }
    }

    func collectScopedRangeUserExtensionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let knownNames = KnownCompilerNames(interner: interner)
        let rangesPackageFQName = knownNames.kotlinRangesPackage
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        return ctx.cachedScopeLookup(calleeName).filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let parentID = sema.symbols.parentSymbol(for: candidate),
                  let parent = sema.symbols.symbol(parentID),
                  parent.fqName != rangesPackageFQName,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiver,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }
    }

}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
