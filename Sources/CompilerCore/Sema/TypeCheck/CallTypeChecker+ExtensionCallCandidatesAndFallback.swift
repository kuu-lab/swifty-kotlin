import Foundation

// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {

    /// Extension-function candidates for a `receiver.calleeName(...)` call,
    /// gathered from scope lookups and the bundled/synthetic symbol-table
    /// fallbacks. Kotlin admits these when no member candidate exists, and
    /// (KUU-946) when every member proved inapplicable to the call.
    func collectExtensionCallCandidates(
        named calleeName: InternedString,
        memberLookupType: TypeID,
        isSuperCall: Bool,
        supertypeSymbols: Set<SymbolID>,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        if !isSuperCall,
           let local = locals[calleeName],
           let receiver = sema.symbols.functionSignature(for: local.symbol)?.receiverType,
           extensionSyntheticFallbackReceiverMatches(
               callSiteReceiver: memberLookupType, declaredReceiver: receiver, sema: sema
           )
        {
            return [local.symbol]
        }
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullReceiverForScope = sema.types.makeNonNullable(memberLookupType)
        let requiresScopedBitwiseExtension = (nonNullReceiverForScope == sema.types.byteType
            || nonNullReceiverForScope == sema.types.shortType)
            && ["and", "or", "xor", "inv", "shl", "shr", "ushr"].contains(interner.resolve(calleeName))
        // A nearer property is a separate callable namespace. Keep explicitly
        // imported function aliases available while comparing invocation tiers.
        var scopeCandidates = ctx.scope.lookup(calleeName, matching: { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate) else { return false }
            guard let recv = signature.receiverType else { return false }
            guard extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiverForScope,
                declaredReceiver: recv,
                sema: sema
            ) else { return false }
            if isSuperCall, !supertypeSymbols.isEmpty {
                return sema.symbols.parentSymbol(for: candidate).map { supertypeSymbols.contains($0) } ?? false
            }
            return true
        })
        if let dispatchReceiver = ctx.implicitReceiverType {
            let dispatchMembers = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName, receiverType: dispatchReceiver, sema: sema, interner: interner
            ).filter { candidate in
                guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiverForScope, declaredReceiver: receiver, sema: sema
                )
            }
            if !dispatchMembers.isEmpty {
                scopeCandidates = dispatchMembers
            }
        }
        // Primitive-array source members are top-level extensions in
        // kotlin.collections. Default-import lookup may stop at a
        // same-named Sequence extension first (notably for
        // UByteArray/UShortArray), so prefer the exact source
        // receiver overload when one is present.
        let primitiveArraySourceCandidates = collectPrimitiveArraySourceMembers(
            named: calleeName,
            receiverType: nonNullReceiverForScope,
            sema: sema,
            interner: interner
        )
        let arrayConversionSourceCandidates = collectArraySourceBackedCandidates(
            named: calleeName,
            receiverType: nonNullReceiverForScope,
            ctx: ctx,
            sema: sema,
            interner: interner
        )
        if !arrayConversionSourceCandidates.isEmpty {
            scopeCandidates = arrayConversionSourceCandidates
        } else if !primitiveArraySourceCandidates.isEmpty {
            scopeCandidates = primitiveArraySourceCandidates
        }
        // Extension functions are excluded from scope by the scope
        // builder so they don't shadow top-level calls.  Fall back
        // to a direct symbol-table lookup by short name to find
        // synthetic extension functions (e.g. Double.pow).
        if scopeCandidates.isEmpty, !requiresScopedBitwiseExtension {
            let nonNullReceiver = sema.types.makeNonNullable(memberLookupType)
            let scopedCandidates = Set(ctx.scope.lookupMergingChain(calleeName))
            scopeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let recvType = signature.receiverType
                else { return false }
                // Include bundled/user Kotlin source extensions, not only
                // synthetic stubs, so source-backed Sequence transforms
                // (map, filter, etc.) are visible as member-call candidates.
                let kotlinMathPackage = knownNames.kotlinMathPackage
                let isExplicitlyImportedKotlinMath = {
                    guard Array(symbol.fqName.dropLast()) == kotlinMathPackage,
                          let sourceFile = ctx.currentASTFile
                    else {
                        return false
                    }
                    if sourceFile.packageFQName == kotlinMathPackage {
                        return true
                    }
                    return sourceFile.imports.contains { importDecl in
                        importDecl.path == kotlinMathPackage
                            || importDecl.path == symbol.fqName
                    }
                }()
                let isSourceBackedExtension = sema.symbols.isSourceBackedSymbol(candidate)
                guard !symbol.flags.contains(.localFunction),
                      symbol.flags.contains(.synthetic) || isSourceBackedExtension else {
                    return false
                }
                // Recover user extensions only from the lexical/import scope;
                // a global short-name match must not expose another package.
                if let file = symbol.declSite?.start.file,
                   driver.sourceManager?.origin(of: file) == .user,
                   !scopedCandidates.contains(candidate)
                {
                    return false
                }
                // Member extensions require a dispatch receiver in lexical scope.
                // The scope and dispatch-member paths above already collect them;
                // global short-name recovery must not make them callable outside it.
                guard sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil else {
                    return false
                }
                // A member extension declared in a companion is
                // callable only when that companion is in lexical
                // scope or explicitly imported. Scope lookup above
                // already covers both; the global short-name
                // fallback must not expose it to every file.
                // Extensions declared *on* the companion type
                // (e.g. `fun Worker.Companion.start`) are also
                // parented under the companion symbol (KSP-443);
                // they remain visible through normal imports, so
                // only member extensions whose declared receiver
                // is a different type are excluded here.
                if let parent = sema.symbols.parentSymbol(for: candidate),
                   let owner = sema.symbols.parentSymbol(for: parent),
                   sema.symbols.companionObjectSymbol(for: owner) == parent,
                   resolveClassType(recvType, sema: sema)?.classSymbol != parent
                {
                    return false
                }
                // kotlin.math is not a Kotlin default import. Do not let this
                // member fallback bypass an explicit import for either the
                // bundled source declarations or their imported-library forms.
                guard Array(symbol.fqName.dropLast()) != kotlinMathPackage
                    || isExplicitlyImportedKotlinMath
                else {
                    return false
                }
                // Exclude property accessor functions (getter/setter)
                // whose parent is a property symbol.  Their short name
                // is "get"/"set" and must not pollute member lookup.
                if let parentID = sema.symbols.parentSymbol(for: candidate),
                   let parentSym = sema.symbols.symbol(parentID),
                   parentSym.kind == .property
                {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: recvType,
                    sema: sema
                )
            }
        }
        // Bundled stdlib extensions on flat-representation receivers
        // (e.g. String.startsWith in kotlin.text) live only in scope,
        // but a same-named extension declared in the current package
        // (e.g. File.startsWith) fully shadows them because ordinary
        // scope lookup stops at the innermost binding. Merge the whole
        // scope chain and filter by receiver to recover them.
        if scopeCandidates.isEmpty {
            let nonNullReceiverForChain = sema.types.makeNonNullable(memberLookupType)
            scopeCandidates = ctx.scope.lookupMergingChain(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let recv = signature.receiverType
                else { return false }
                if let parentID = sema.symbols.parentSymbol(for: candidate),
                   let parentSym = sema.symbols.symbol(parentID),
                   parentSym.kind == .property
                {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiverForChain,
                    declaredReceiver: recv,
                    sema: sema
                )
            }
        }
        // Bundled stdlib extension functions are conceptually members
        // of their receiver type (e.g. AtomicIntArray.loadAt) and must
        // resolve on member-style calls without an explicit import, the
        // same way synthetic stubs used to. Ordinary scope lookup only
        // finds them when imported, so as a final fallback — reached only
        // when the call would otherwise be unresolved — match bundled
        // stdlib extensions by receiver type.
        if scopeCandidates.isEmpty {
            scopeCandidates = collectBundledStdlibExtensionCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sourceFile: ctx.currentASTFile,
                sema: sema,
                interner: interner
            )
        }
        return scopeCandidates
    }

    /// KUU-946: Kotlin admits extension functions as call candidates whenever
    /// every same-named member is inapplicable — members only shadow
    /// extensions while one of them resolves. The primary path keeps
    /// `allCandidates` member-only while any member exists, so a member set
    /// that failed overload resolution ends in a diagnostic instead of ever
    /// seeing the extensions. This re-runs the call against the extension
    /// candidate set once all member routes have definitively failed, then
    /// binds it with the same visibility/shaping/success steps the primary
    /// path uses. Returns nil when no extension resolves so the caller can
    /// still emit its member error.
    func tryBindShadowedExtensionCallFallback(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        argTypes: [TypeID],
        isClassNameReceiver: Bool,
        isSuperCall: Bool,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // A `super.` call can never bind an extension, and a class-name
        // receiver only sees static members.
        guard !isClassNameReceiver, !isSuperCall else {
            return nil
        }
        let scopedExtensionCandidates = Set(ctx.scope.lookupMergingChain(calleeName))
        let allowsImportlessAtomicExtensions = isAtomicMigrationReceiver(memberLookupType, sema: sema, interner: interner)
        var allCandidates = collectExtensionCallCandidates(
            named: calleeName,
            memberLookupType: memberLookupType,
            isSuperCall: false,
            supertypeSymbols: [],
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner
        ).filter { candidate in
            !sema.symbols.isSourceBackedSymbol(candidate)
                || scopedExtensionCandidates.contains(candidate)
                || locals[calleeName]?.symbol == candidate
                || allowsImportlessAtomicExtensions
        }
        guard !allCandidates.isEmpty else {
            return nil
        }

        // The MutableMap source-backed preference rules from the primary path,
        // applied to the extension set.
        if calleeName == knownNames.remove,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mutableMapRemoveCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapRemoveCandidates.isEmpty {
                allCandidates = mutableMapRemoveCandidates
            }
        }
        if calleeName == knownNames.iterator,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        {
            let mutableMapIteratorCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapIteratorCandidates.isEmpty {
                allCandidates = mutableMapIteratorCandidates
            }
        }
        if calleeName == knownNames.getValue,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mapGetValueCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMapFQName
            }
            if !mapGetValueCandidates.isEmpty {
                allCandidates = mapGetValueCandidates
            }
        }

        let isNullLiteralReceiver = if case .nullLiteral = ast.arena.expr(receiverID) {
            true
        } else {
            false
        }

        // Same expect/actual dedup and visibility gate as the primary path.
        let candidateSet = Set(allCandidates)
        let resolvedCandidates = allCandidates.filter { candidate in
            if ctx.cachedSymbol(candidate)?.flags.contains(.localFunction) == true,
               locals[calleeName]?.symbol != candidate
            {
                return false
            }
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.flags.contains(.expectDeclaration)
            else {
                return true
            }
            guard let actual = sema.symbols.actualSymbol(for: candidate) else {
                return true
            }
            return !candidateSet.contains(actual)
        }
        let (visible, invisible) = ctx.filterByVisibility(resolvedCandidates)
        let memberName = interner.resolve(calleeName)
        if !safeCall,
           args.isEmpty,
           explicitTypeArgs.isEmpty,
           invisible.isEmpty,
           sema.types.nullability(of: receiverType) == .nullable,
           memberName == "toString" || memberName == "hashCode",
           !visible.contains(where: { candidate in
               guard let signature = sema.symbols.functionSignature(for: candidate),
                     signature.parameterTypes.isEmpty,
                     let declaredReceiver = signature.receiverType,
                     sema.types.nullability(of: declaredReceiver) == .nullable
               else {
                   return false
               }
               return sema.types.isSubtype(receiverType, declaredReceiver)
           })
        {
            let resultType = memberName == "toString" ? sema.types.stringType : sema.types.intType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        var candidates = preferMostSpecificMemberReceiverCandidates(
            visible,
            receiverType: lookupReceiverType,
            argumentTypes: argTypes,
            sema: sema,
            interner: interner
        )
        if calleeName == knownNames.forEach {
            let receiverClassification = ReceiverClassifier(sema: sema, interner: interner).classify(
                receiverID: receiverID,
                receiverType: lookupReceiverType,
                ast: ast
            )
            let isEligibleIterableReceiver = receiverClassification.isIterableReceiver
                || (
                    !receiverClassification.isCollectionReceiver
                        && !receiverClassification.isSequenceReceiver
                        && !receiverClassification.isArrayReceiver
                        && !receiverClassification.isMapReceiver
                        && !receiverClassification.isSetReceiver
                )
            if !isEligibleIterableReceiver {
                let iterableFQName = knownNames.kotlinCollectionsIterableFQName
                candidates.removeAll { candidate in
                    guard sema.symbols.isSourceBackedSymbol(candidate),
                          let signatureReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                          let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName == iterableFQName
                }
            }
        }
        if calleeName == knownNames.withDefault,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(lookupReceiverType)
        {
            let mutableMapCandidates = candidates.filter { candidate in
                guard sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapCandidates.isEmpty {
                candidates = mutableMapCandidates
            }
        }
        if calleeName == knownNames.coerceIn,
           !args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            candidates.removeAll { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == knownNames.closedFloatingPointRange
            }
        }
        if calleeName == knownNames.coerceIn,
           args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            let genericRangeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == knownNames.closedFloatingPointRange
            }
            candidates.append(contentsOf: genericRangeCandidates.filter { !candidates.contains($0) })
        }
        if calleeName == knownNames.toList {
            candidates = preferCollectionToListCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.take {
            candidates = preferListTakeCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.unzip {
            candidates = preferListUnzipCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if isNullLiteralReceiver,
           args.isEmpty,
           calleeName == knownNames.isNullOrEmpty,
           let charSequenceType = syntheticCharSequenceType(sema: sema),
           candidates.contains(where: { candidate in
               sema.symbols.functionSignature(for: candidate)?.receiverType == sema.types.makeNullable(charSequenceType)
           })
        {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0003",
                "Ambiguous overload resolution.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let hasLeadingLocaleArgument = calleeName == knownNames.format
            && argTypes.first.map { isJavaUtilLocaleType($0, sema: sema, interner: interner) } == true
        if hasLeadingLocaleArgument {
            candidates.removeAll { candidate in
                isSyntheticStringFormatCandidate(candidate, sema: sema, interner: interner)
            }
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let hasTrailingLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false
        let memberNameText = memberName
        let isMutableMapIteratorSource = memberNameText == "iterator"
            && ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        let isUniqueIteratorSource = memberNameText == "iterator" && candidates.count == 1
        let isArrayJoinToString = memberNameText == "joinToString"
            && isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isArraySourceBackedMember = isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
            && !collectArraySourceBackedCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                ctx: ctx,
                sema: sema,
                interner: interner
            ).isEmpty
        let isSourceBackedMemberName = (calleeName == knownNames.zip
            && isSequenceLikeType(lookupReceiverType, sema: sema, interner: interner))
            || Self.sourceBackedCollectionMemberNames.contains(memberNameText)
            || (Self.sourceBackedTrailingLambdaMemberNames.contains(memberNameText) && !isArrayJoinToString)
            || isArraySourceBackedMember
            || isMutableMapIteratorSource
            || isUniqueIteratorSource
        let hasSourceBackedCandidate = isSourceBackedMemberName
            && (isArraySourceBackedMember || !Self.sourceBackedCollectionMemberNames.contains(memberNameText) || !hasTrailingLambdaArg)
            && candidates.contains { candidateID in
                sema.symbols.isSourceBackedSymbol(candidateID)
            }
        // The collection fallback is member-shaped, but it ran on the member
        // candidate set in the primary pass; the source-backed gate differs on
        // the extension set, so re-evaluate it before generic resolution.
        if !hasSourceBackedCandidate, let fallbackType = tryCollectionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            expectedType: expectedType,
            locals: &locals
        ) {
            return fallbackType
        }

        var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral, .callableRef:
                continue
            default:
                cachedNonLambdaArgTypes[index] = argTypes[index]
            }
        }
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            expectedTypeOverrides: {
                let isLongRangeLiteralContainsCall = calleeName == knownNames.contains
                    && args.count == 1
                    && MemberRuntimeDispatch.rangeReceiverKind(
                        receiverExpr: receiverID,
                        receiverType: receiverType,
                        sema: sema,
                        interner: interner
                    ) == .longRange
                    && driver.callChecker.isContextualizableIntegerLiteral(args[0].expr, ast: ast)
                if isLongRangeLiteralContainsCall {
                    return [0: sema.types.longType]
                }
                let isULongRangeLiteralContainsCall = calleeName == knownNames.contains
                    && args.count == 1
                    && MemberRuntimeDispatch.rangeReceiverKind(
                        receiverExpr: receiverID,
                        receiverType: receiverType,
                        sema: sema,
                        interner: interner
                    ) == .ulongRange
                    && driver.callChecker.isContextualizableUnsignedIntegerLiteral(args[0].expr, ast: ast)
                if isULongRangeLiteralContainsCall {
                    return [0: sema.types.ulongType]
                }
                return [:]
            }(),
            contextualCallResultType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: memberLookupType,
            ctx: ctx,
            locals: &locals
        )
        if memberNameText == "replace",
           args.count == 2,
           sema.types.makeNonNullable(argTypes[0]) == sema.types.stringType,
           preparedArgs.lambdaLiteralIndices.contains(1),
           case let .functionType(lambdaType) = sema.types.kind(
               of: sema.types.makeNonNullable(preparedArgs.argTypes[1])
           ),
           sema.types.isSubtype(lambdaType.returnType, sema.types.stringType)
        {
            let regexStringBridgeCandidates = candidates.filter {
                sema.symbols.externalLinkName(for: $0) == "__kk_regex_replace_lambda"
            }
            if !regexStringBridgeCandidates.isEmpty {
                candidates = regexStringBridgeCandidates
            }
        }
        var resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: range,
            calleeName: calleeName,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: expectedType,
            implicitReceiverType: memberLookupType,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: ctx
        )
        if resolved.diagnostic != nil {
            if let retried = retryResolutionReinferringNestedCallArguments(
                candidates: candidates,
                args: args,
                argTypes: preparedArgs.argTypes,
                range: range,
                calleeName: calleeName,
                explicitTypeArgs: explicitTypeArgs,
                expectedType: expectedType,
                implicitReceiverType: memberLookupType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx,
                locals: &locals
            ) {
                resolved = retried
            }
        }
        guard resolved.diagnostic == nil, let chosen = resolved.chosenCallee else {
            return nil
        }

        markRegexReplaceLambdaIfNeeded(chosenCallee: chosen, args: args, ctx: ctx)
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: ctx,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )

        // Same use-site variance projection check as the primary path.
        if let signature = sema.symbols.functionSignature(for: chosen),
           let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
               receiverType: lookupReceiverType,
               signature: signature,
               symbols: sema.symbols
           )
        {
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: sema, interner: interner),
               let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
               )
            {
                let paramType = sema.types.displayName(
                    of: signature.parameterTypes[violatingParamIndex],
                    symbols: sema.symbols,
                    interner: interner
                )
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: range
                )
                return sema.types.errorType
            }

            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let mergedSubstitution = resolved.substitutedTypeArguments.merging(
                varianceResult.covariantSubstitution,
                uniquingKeysWith: { _, projected in projected }
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: mergedSubstitution
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            let projectedReturnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: mergedSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            let finalType = safeCall ? sema.types.makeNullable(projectedReturnType) : projectedReturnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        contextualizeArrayReduceRightLambda(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        contextualizeResolvedIntegerArguments(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        applyContractEffects(
            id: id,
            chosen: chosen,
            args: args,
            ctx: ctx,
            locals: &locals
        )
        let adjustedReturnType: TypeID = if sema.symbols.externalLinkName(for: chosen) == "kk_kxmini_async_await" {
            deferredAwaitResultType(receiverID: receiverID, fallback: returnType, ast: ast, sema: sema)
        } else {
            returnType
        }
        let finalType = safeCall ? sema.types.makeNullable(adjustedReturnType) : adjustedReturnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
