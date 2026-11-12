import Foundation

// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {

    /// Extension-function candidates for a `receiver.calleeName(...)` call.
    /// Kotlin admits these when no member candidate exists, and (KUU-946)
    /// when every member proved inapplicable to the call.
    func collectExtensionCallCandidates(
        named calleeName: InternedString,
        memberLookupType: TypeID,
        isSuperCall: Bool,
        supertypeSymbols: Set<SymbolID>,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner,
        callShapeMatches: ((SymbolID) -> Bool)? = nil,
        requiresInfix: Bool = false
    ) -> [SymbolID] {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullReceiverForScope = sema.types.makeNonNullable(memberLookupType)
        let requiresScopedBitwiseExtension = (nonNullReceiverForScope == sema.types.byteType
            || nonNullReceiverForScope == sema.types.shortType)
            && ["and", "or", "xor", "inv", "shl", "shr", "ushr"].contains(interner.resolve(calleeName))
        // A nearer property is a separate callable namespace. Keep explicitly
        // imported function aliases available while comparing invocation tiers.
        // An imported-library extension whose source twin is compiled into
        // this module (e.g. vendored kotlinx-coroutines over the bundled
        // stdlib copy) must not survive as a second candidate: scope lookup
        // below bypasses `cachedScopeLookup`'s shadowing filter, so apply it
        // here (KUU-4249).
        func notShadowedBySource(_ candidate: SymbolID) -> Bool {
            !ctx.isImportedSymbolShadowedBySource(candidate)
        }
        func receiverMatches(_ candidate: SymbolID) -> Bool {
            guard notShadowedBySource(candidate),
                  let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  !requiresInfix || symbol.flags.contains(.infixFunction),
                  let signature = sema.symbols.functionSignature(for: candidate) else { return false }
            guard let recv = signature.receiverType else { return false }
            guard extensionReceiverMatchesDuringBuilderInference(
                callSiteReceiver: nonNullReceiverForScope,
                declaredReceiver: recv,
                ctx: ctx
            ) else { return false }
            if isSuperCall, !supertypeSymbols.isEmpty {
                return sema.symbols.parentSymbol(for: candidate).map { supertypeSymbols.contains($0) } ?? false
            }
            return true
        }
        if !isSuperCall {
            let localFunctionCandidates = ctx.scope.lookup(calleeName, matching: { candidate in
                ctx.cachedSymbol(candidate)?.flags.contains(.localFunction) == true
                    && receiverMatches(candidate)
                    && callShapeMatches?(candidate) != false
            })
            if !localFunctionCandidates.isEmpty {
                if localFunctionCandidates.count == 1,
                   let candidate = localFunctionCandidates.first,
                   let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                   let constraints = deferredBuilderReceiverConstraints(
                       callSiteReceiver: nonNullReceiverForScope,
                       declaredReceiver: receiver,
                       ctx: ctx
                   )
                {
                    ctx.builderInference?.constraints.append(contentsOf: constraints)
                }
                return localFunctionCandidates
            }
        }
        if !isSuperCall,
           let local = locals[calleeName],
           !requiresInfix || sema.symbols.symbol(local.symbol)?.flags.contains(.infixFunction) == true,
           callShapeMatches?(local.symbol) != false,
           let receiver = sema.symbols.functionSignature(for: local.symbol)?.receiverType,
           extensionReceiverMatchesDuringBuilderInference(
               callSiteReceiver: memberLookupType, declaredReceiver: receiver, ctx: ctx
           )
        {
            if let constraints = deferredBuilderReceiverConstraints(
                callSiteReceiver: memberLookupType,
                declaredReceiver: receiver,
                ctx: ctx
            ) {
                ctx.builderInference?.constraints.append(contentsOf: constraints)
            }
            return [local.symbol]
        }
        var scopeCandidates = ctx.scope.lookup(calleeName, matching: receiverMatches)
        if let callShapeMatches {
            // Walk outward only when the nearer tier has no potentially
            // applicable visible extension. Never merge tiers before comparing
            // receiver specificity: an applicable local Iterable extension
            // still takes precedence over an outer List extension.
            let applicableScopeCandidates = ctx.scope.lookup(calleeName, matching: { candidate in
                guard receiverMatches(candidate),
                      let symbol = ctx.cachedSymbol(candidate),
                      !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols),
                      ctx.visibilityChecker.isAccessible(
                          symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                      )
                else { return false }
                return callShapeMatches(candidate)
            })
            if !applicableScopeCandidates.isEmpty {
                scopeCandidates = applicableScopeCandidates
            }
        }
        let dispatchMembers = collectDispatchReceiverMemberExtensionCandidates(
            named: calleeName,
            extensionReceiverType: nonNullReceiverForScope,
            ctx: ctx
        ).filter { candidate in
            notShadowedBySource(candidate)
                && (!requiresInfix || sema.symbols.symbol(candidate)?.flags.contains(.infixFunction) == true)
        }
        if !dispatchMembers.isEmpty {
            scopeCandidates = dispatchMembers
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
        if !requiresInfix, !arrayConversionSourceCandidates.isEmpty {
            scopeCandidates = arrayConversionSourceCandidates
        } else if !requiresInfix, !primitiveArraySourceCandidates.isEmpty {
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
                guard notShadowedBySource(candidate),
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      !requiresInfix || symbol.flags.contains(.infixFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let recvType = signature.receiverType
                else { return false }
                // Importless recovery must not surface declarations the use
                // site cannot legally call: an inaccessible bundled internal
                // member can only produce a guaranteed INVISIBLE_MEMBER
                // diagnostic, so it is never a real candidate (KUU-4103).
                guard ctx.visibilityChecker.isAccessible(
                    symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                ) else { return false }
                guard isUnsignedRandomExtensionVisible(symbol, named: calleeName, ctx: ctx) else {
                    return false
                }
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
                // kotlin.reflect.full is not a Kotlin default import: its
                // extensions are visible only through an explicit import or
                // from the same package (KUU-4070). The short-name fallback
                // must not surface them unqualified — this package check
                // subsumes the earlier findAnnotation-only special case.
                let reflectFullPackage = knownNames.kotlinReflectFullPackage
                if Array(symbol.fqName.dropLast()) == reflectFullPackage,                   !scopedCandidates.contains(candidate) {
                    guard let file = ctx.currentASTFile,
                          file.packageFQName == reflectFullPackage || file.imports.contains(where: { importDecl in
                              if importDecl.isWildcard { return importDecl.path == reflectFullPackage }
                              return importDecl.path == symbol.fqName
                                  && (importDecl.alias ?? symbol.name) == calleeName
                          }) else { return false }
                }
                // Bundled source-backed extensions obey Kotlin's package
                // visibility: without an explicit import they are only
                // callable from their own package or a default-import
                // package (KUU-4299). The `kotlin.reflect` shim package is the
                // exception: KSP-496 keeps those KClass members importless,
                // while `kotlin.reflect.full` remains gated above. The lenient
                // short-name recovery stays
                // for bundled-stdlib call sites, which rely on it for
                // cross-package helpers such as kotlinx.io.unsafe.
                // Member functions surfaced through this path (for example an
                // interface's `operator fun next` reached via an implementing
                // receiver whose own override hides it from member lookup)
                // are governed by member visibility, not package imports, so
                // the gate only applies to symbols that are not true class
                // members. KSP-INF-011 reparents top-level extensions under
                // their receiver nominal, so a class-like parent alone does
                // not make a symbol a member — true members keep an FQ name
                // nested inside the parent's (e.g.
                // kotlin.collections.Iterator.next).
                let isClassMember = sema.symbols.parentSymbol(for: candidate)
                    .flatMap { sema.symbols.symbol($0) }
                    .map { parent in
                        switch parent.kind {
                        case .class, .interface, .enumClass, .object, .annotationClass:
                            return Array(symbol.fqName.dropLast()) == parent.fqName
                        default:
                            return false
                        }
                    } ?? false
                if isSourceBackedExtension, !scopedCandidates.contains(candidate),
                   !isClassMember,
                   let file = ctx.currentASTFile,
                   driver.sourceManager?.origin(of: ctx.currentFileID) == .user
                {
                    let candidatePackage = Array(symbol.fqName.dropLast())
                    let visibleWithoutImport = candidatePackage == file.packageFQName
                        || candidatePackage == knownNames.kotlinReflectPackage
                        || TypeCheckScopeBuilder().makeDefaultImportPackages(interner: interner)
                            .contains(candidatePackage)
                    let explicitlyImported = file.imports.contains { importDecl in
                        if importDecl.isWildcard { return importDecl.path == candidatePackage }
                        return importDecl.path == symbol.fqName
                            && (importDecl.alias ?? symbol.name) == calleeName
                    }
                    guard visibleWithoutImport || explicitlyImported else { return false }
                }
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
                return extensionReceiverMatchesDuringBuilderInference(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: recvType,
                    ctx: ctx
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
                guard notShadowedBySource(candidate),
                      let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      !requiresInfix || symbol.flags.contains(.infixFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let recv = signature.receiverType
                else { return false }
                if let parentID = sema.symbols.parentSymbol(for: candidate),
                   let parentSym = sema.symbols.symbol(parentID),
                   parentSym.kind == .property
                {
                    return false
                }
                return extensionReceiverMatchesDuringBuilderInference(
                    callSiteReceiver: nonNullReceiverForChain,
                    declaredReceiver: recv,
                    ctx: ctx
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
            ).filter {
                notShadowedBySource($0)
                    && (!requiresInfix || sema.symbols.symbol($0)?.flags.contains(.infixFunction) == true)
            }
        }
        if scopeCandidates.count == 1,
           let candidate = scopeCandidates.first,
           let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
           let constraints = deferredBuilderReceiverConstraints(
               callSiteReceiver: nonNullReceiverForScope,
               declaredReceiver: receiver,
               ctx: ctx
           )
        {
            ctx.builderInference?.constraints.append(contentsOf: constraints)
        }
        return shadowFilteredExtensionCandidates(scopeCandidates, sema: sema)
    }

    /// A user-source declaration shadows a bundled-stdlib declaration with
    /// an identical signature: compiling e.g. kotlinx-coroutines sources
    /// against the bundled stdlib must not see each extension twice.
    private func shadowFilteredExtensionCandidates(
        _ candidates: [SymbolID],
        sema: SemaModule
    ) -> [SymbolID] {
        func sameCallableSignature(_ lhs: SymbolID, _ rhs: SymbolID) -> Bool {
            guard let lhsSymbol = sema.symbols.symbol(lhs),
                  let rhsSymbol = sema.symbols.symbol(rhs),
                  lhsSymbol.fqName == rhsSymbol.fqName,
                  let lhsSignature = sema.symbols.functionSignature(for: lhs),
                  let rhsSignature = sema.symbols.functionSignature(for: rhs)
            else {
                return false
            }
            return lhsSignature.receiverType == rhsSignature.receiverType
                && lhsSignature.parameterTypes == rhsSignature.parameterTypes
                && lhsSignature.returnType == rhsSignature.returnType
                && lhsSignature.typeParameterSymbols.count == rhsSignature.typeParameterSymbols.count
                && lhsSignature.isSuspend == rhsSignature.isSuspend
        }
        func isBundledStdlibDecl(_ symbol: SymbolID) -> Bool {
            if sema.symbols.isImportedStdlibSymbol(symbol) {
                return true
            }
            guard let file = sema.symbols.symbol(symbol)?.declSite?.start.file else {
                return false
            }
            return driver.sourceManager?.origin(of: file)?.isBundledStdlib == true
        }
        return candidates.filter { candidate in
            guard isBundledStdlibDecl(candidate) else {
                return true
            }
            return !candidates.contains { other in
                other != candidate
                    && !isBundledStdlibDecl(other)
                    && sameCallableSignature(candidate, other)
            }
        }
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

        // A `super.` call can never bind an extension, and a class-name
        // receiver only sees static members.
        guard !isClassNameReceiver, !isSuperCall else {
            return nil
        }
        let scopedExtensionCandidates = Set(request.ctx.scope.lookupMergingChain(request.calleeName))
        // Receiver lambdas expose their owner's member extensions through the
        // dispatch receiver rather than the lexical/import scope. Keep those
        // candidates when an explicit receiver's ordinary members cannot
        // accept the call (e.g. Parser.parse(source) beside State.Parser.parse()).
        let dispatchExtensionCandidates = Set(collectDispatchReceiverMemberExtensionCandidates(
            named: request.calleeName,
            extensionReceiverType: memberLookupType,
            ctx: request.ctx
        ))
        let allowsImportlessAtomicExtensions = isAtomicMigrationReceiver(memberLookupType, sema: request.sema, interner: request.interner)
        var allCandidates = collectExtensionCallCandidates(
            named: request.calleeName,
            memberLookupType: memberLookupType,
            isSuperCall: false,
            supertypeSymbols: [],
            ctx: request.ctx,
            locals: locals,
            sema: request.sema,
            interner: request.interner,
            callShapeMatches: {
                self.extensionCandidateMatchesCallShape(
                    $0, request: request, argumentTypes: argTypes, receiverType: memberLookupType
                )
            },
            requiresInfix: request.ast.arena.isInfixCall(request.id)
        ).filter { candidate in
            !request.sema.symbols.isSourceBackedSymbol(candidate)
                || scopedExtensionCandidates.contains(candidate)
                || dispatchExtensionCandidates.contains(candidate)
                || locals[request.calleeName]?.symbol == candidate
                || allowsImportlessAtomicExtensions
        }
        guard !allCandidates.isEmpty else {
            return nil
        }

        if request.calleeName == request.knownNames.remove,
           ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType),
           request.args.count == 1
        {
            let mutableMapRemoveCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                guard let candidateSymbol = request.sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || request.sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                      let symbol = request.sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == request.knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapRemoveCandidates.isEmpty {
                allCandidates = mutableMapRemoveCandidates
            }
        }
        if request.calleeName == request.knownNames.iterator,
           ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType)
        {
            let mutableMapIteratorCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                guard request.sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                      let symbol = request.sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == request.knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapIteratorCandidates.isEmpty {
                allCandidates = mutableMapIteratorCandidates
            }
        }
        if request.calleeName == request.knownNames.getValue,
           ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType),
           request.args.count == 1
        {
            let mapGetValueCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                guard let candidateSymbol = request.sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || request.sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                      let symbol = request.sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == request.knownNames.kotlinCollectionsMapFQName
            }
            if !mapGetValueCandidates.isEmpty {
                allCandidates = mapGetValueCandidates
            }
        }

        let isNullLiteralReceiver = if case .nullLiteral = request.ast.arena.expr(request.receiverID) {
            true
        } else {
            false
        }

        let candidateSet = Set(allCandidates)
        let visibleLocalFunctionCandidates = request.ctx.scope.lookup(request.calleeName, matching: { candidate in
            request.ctx.cachedSymbol(candidate)?.flags.contains(.localFunction) == true
        })
        let resolvedCandidates = allCandidates.filter { candidate in
            if request.ctx.cachedSymbol(candidate)?.flags.contains(.localFunction) == true,
               !visibleLocalFunctionCandidates.contains(candidate)
            {
                return false
            }
            guard let symbol = request.ctx.cachedSymbol(candidate),
                  symbol.flags.contains(.expectDeclaration)
            else {
                return true
            }
            guard let actual = request.sema.symbols.actualSymbol(for: candidate) else {
                return true
            }
            return !candidateSet.contains(actual)
        }
        let (visible, invisible) = request.ctx.filterByVisibility(resolvedCandidates)
        let memberName = request.interner.resolve(request.calleeName)
        if !request.safeCall,
           request.args.isEmpty,
           request.explicitTypeArgs.isEmpty,
           invisible.isEmpty,
           request.sema.types.nullability(of: receiverType) == .nullable,
           memberName == "toString" || memberName == "hashCode",
           !visible.contains(where: { candidate in
               guard let signature = request.sema.symbols.functionSignature(for: candidate),
                     signature.parameterTypes.isEmpty,
                     let declaredReceiver = signature.receiverType,
                     request.sema.types.nullability(of: declaredReceiver) == .nullable
               else {
                   return false
               }
               return request.sema.types.isSubtype(receiverType, declaredReceiver)
           })
        {
            let resultType = memberName == "toString" ? request.sema.types.stringType : request.sema.types.intType
            request.sema.bindings.bindExprType(request.id, type: resultType)
            return resultType
        }
        var candidates = preferMostSpecificMemberReceiverCandidates(
            visible,
            receiverType: lookupReceiverType,
            argumentTypes: argTypes,
            sema: request.sema,
            interner: request.interner
        )
        if request.calleeName == request.knownNames.forEach {
            let receiverClassification = ReceiverClassifier(sema: request.sema, interner: request.interner).classify(
                receiverID: request.receiverID,
                receiverType: lookupReceiverType,
                ast: request.ast
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
                let iterableFQName = request.knownNames.kotlinCollectionsIterableFQName
                candidates.removeAll { candidate in
                    guard request.sema.symbols.isSourceBackedSymbol(candidate),
                          let signatureReceiver = request.sema.symbols.functionSignature(for: candidate)?.receiverType,
                          let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: request.sema)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName == iterableFQName
                }
            }
        }
        if request.calleeName == request.knownNames.withDefault,
           ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(lookupReceiverType)
        {
            let mutableMapCandidates = candidates.filter { candidate in
                guard request.sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                      let symbol = request.sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == request.knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapCandidates.isEmpty {
                candidates = mutableMapCandidates
            }
        }
        if request.calleeName == request.knownNames.coerceIn,
           !request.args.contains(where: { request.sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            candidates.removeAll { candidate in
                guard let signature = request.sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: request.sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == request.knownNames.closedFloatingPointRange
            }
        }
        if request.calleeName == request.knownNames.coerceIn,
           request.args.contains(where: { request.sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            let genericRangeCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                guard let symbol = request.sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      request.sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: request.sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == request.knownNames.closedFloatingPointRange
            }
            candidates.append(contentsOf: genericRangeCandidates.filter { !candidates.contains($0) })
        }
        if request.calleeName == request.knownNames.toList {
            candidates = preferCollectionToListCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner
            )
        }
        if request.calleeName == request.knownNames.take {
            candidates = preferListTakeCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner
            )
        }
        if request.calleeName == request.knownNames.unzip {
            candidates = preferListUnzipCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner
            )
        }
        if isNullLiteralReceiver,
           request.args.isEmpty,
           request.calleeName == request.knownNames.isNullOrEmpty,
           let charSequenceType = syntheticCharSequenceType(sema: request.sema),
           candidates.contains(where: { candidate in
               request.sema.symbols.functionSignature(for: candidate)?.receiverType == request.sema.types.makeNullable(charSequenceType)
           })
        {
            request.ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0003",
                "Ambiguous overload resolution.",
                range: request.range
            )
            request.sema.bindings.bindExprType(request.id, type: request.sema.types.errorType)
            return request.sema.types.errorType
        }
        let hasLeadingLocaleArgument = request.calleeName == request.knownNames.format
            && argTypes.first.map { isJavaUtilLocaleType($0, sema: request.sema, interner: request.interner) } == true
        if hasLeadingLocaleArgument {
            candidates.removeAll { candidate in
                isSyntheticStringFormatCandidate(candidate, sema: request.sema, interner: request.interner)
            }
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let hasTrailingLambdaArg = request.args.last.map { request.ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false
        let memberNameText = memberName
        let isMutableMapIteratorSource = memberNameText == "iterator"
            && ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType)
        let isUniqueIteratorSource = memberNameText == "iterator" && candidates.count == 1
        let isArrayJoinToString = memberNameText == "joinToString"
            && isArrayLikeReceiver(receiverID: request.receiverID, sema: request.sema, interner: request.interner)
        let isArraySourceBackedMember = isArrayLikeReceiver(receiverID: request.receiverID, sema: request.sema, interner: request.interner)
            && !collectArraySourceBackedCandidates(
                named: request.calleeName,
                receiverType: memberLookupType,
                ctx: request.ctx,
                sema: request.sema,
                interner: request.interner
            ).isEmpty
        let isSourceBackedMemberName = (request.calleeName == request.knownNames.zip
            && isSequenceLikeType(lookupReceiverType, sema: request.sema, interner: request.interner))
            || request.knownNames.sourceBackedCollectionMemberNames.contains(request.calleeName)
            || (request.knownNames.sourceBackedTrailingLambdaMemberNames.contains(request.calleeName) && !isArrayJoinToString)
            || isArraySourceBackedMember
            || isMutableMapIteratorSource
            || isUniqueIteratorSource
        let hasSourceBackedCandidate = isSourceBackedMemberName
            && (isArraySourceBackedMember || !request.knownNames.sourceBackedCollectionMemberNames.contains(request.calleeName) || !hasTrailingLambdaArg)
            && candidates.contains { candidateID in
                request.sema.symbols.isSourceBackedSymbol(candidateID)
            }
        // The collection fallback is member-shaped, but it ran on the member
        // candidate set in the primary pass; the source-backed gate differs on
        // the extension set, so re-evaluate it before generic resolution.
        if !hasSourceBackedCandidate, let fallbackType = tryCollectionMemberFallback(
            request.id,
            calleeName: request.calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: request.safeCall,
            receiverID: request.receiverID,
            args: request.args,
            ctx: request.ctx,
            expectedType: request.expectedType,
            locals: &locals
        ) {
            return fallbackType
        }

        var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in request.args.enumerated() {
            guard let argumentExpr = request.ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral, .callableRef:
                continue
            default:
                cachedNonLambdaArgTypes[index] = argTypes[index]
            }
        }
        // The losing member attempt may have inferred these arguments
        // against its own parameter list and left error diagnostics inside
        // their ranges. The extension retry re-infers them, so stale
        // argument errors must not leak past a winning candidate (KUU-3145).
        var removedArgumentDiagnostics: [(ExprID, Diagnostic)] = []
        for argument in request.args {
            guard let argumentRange = request.ast.arena.exprRange(argument.expr) else { continue }
            for removed in request.sema.diagnostics.removeErrorDiagnostics(containedIn: argumentRange) {
                removedArgumentDiagnostics.append((argument.expr, removed))
            }
        }
        defer {
            // An argument still bound to the error type was not recovered by
            // the retry, so its removed diagnostics remain genuine failures
            // that nothing re-emitted (KUU-3750).
            for (argumentExpr, diagnostic) in removedArgumentDiagnostics
            where request.sema.bindings.exprType(for: argumentExpr) == request.sema.types.errorType {
                request.sema.diagnostics.emit(diagnostic)
            }
        }
        let preparedArgs = prepareCallArguments(
            args: request.args,
            callRange: request.range,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            expectedTypeOverrides: {
                let isLongRangeLiteralContainsCall = request.calleeName == request.knownNames.contains
                    && request.args.count == 1
                    && MemberRuntimeDispatch.rangeReceiverKind(
                        receiverExpr: request.receiverID,
                        receiverType: receiverType,
                        sema: request.sema,
                        interner: request.interner
                    ) == .longRange
                    && driver.callChecker.isContextualizableIntegerLiteral(request.args[0].expr, ast: request.ast)
                if isLongRangeLiteralContainsCall {
                    return [0: request.sema.types.longType]
                }
                let isULongRangeLiteralContainsCall = request.calleeName == request.knownNames.contains
                    && request.args.count == 1
                    && MemberRuntimeDispatch.rangeReceiverKind(
                        receiverExpr: request.receiverID,
                        receiverType: receiverType,
                        sema: request.sema,
                        interner: request.interner
                    ) == .ulongRange
                    && driver.callChecker.isContextualizableUnsignedIntegerLiteral(request.args[0].expr, ast: request.ast)
                if isULongRangeLiteralContainsCall {
                    return [0: request.sema.types.ulongType]
                }
                return [:]
            }(),
            contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                ? request.sema.types.unitType : request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs,
            receiverType: memberLookupType,
            ctx: request.ctx,
            locals: &locals
        )
        if memberNameText == "replace",
           request.args.count == 2,
           request.sema.types.makeNonNullable(argTypes[0]) == request.sema.types.stringType,
           preparedArgs.lambdaLiteralIndices.contains(1),
           case let .functionType(lambdaType) = request.sema.types.kind(
               of: request.sema.types.makeNonNullable(preparedArgs.argTypes[1])
           ),
           request.sema.types.isSubtype(lambdaType.returnType, request.sema.types.stringType)
        {
            let regexStringBridgeCandidates = candidates.filter {
                request.sema.symbols.externalLinkName(for: $0) == "__kk_regex_replace_lambda"
            }
            if !regexStringBridgeCandidates.isEmpty {
                candidates = regexStringBridgeCandidates
            }
        }
        var resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: request.args,
            argTypes: preparedArgs.argTypes,
            range: request.range,
            calleeName: request.calleeName,
            explicitTypeArgs: request.explicitTypeArgs,
            expectedType: request.expectedType,
            implicitReceiverType: memberLookupType,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: request.ctx
        )
        if resolved.diagnostic != nil {
            if let retried = retryResolutionReinferringNestedCallArguments(
                candidates: candidates,
                args: request.args,
                argTypes: preparedArgs.argTypes,
                range: request.range,
                calleeName: request.calleeName,
                explicitTypeArgs: request.explicitTypeArgs,
                expectedType: request.expectedType,
                implicitReceiverType: memberLookupType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: request.ctx,
                locals: &locals
            ) {
                resolved = retried
            }
        }
        guard resolved.diagnostic == nil, let chosen = resolved.chosenCallee else {
            return nil
        }
        // Same as the primary member-call binder: a call that resolved to a
        // local extension function is a lexical reference to that local
        // declaration, so keep the identifier binding on the call expr.
        if request.sema.symbols.symbol(chosen)?.flags.contains(.localFunction) == true {
            request.sema.bindings.bindIdentifier(request.id, symbol: chosen)
        }

        markRegexReplaceLambdaIfNeeded(chosenCallee: chosen, args: request.args, ctx: request.ctx)
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: request.sema,
            interner: request.interner,
            range: request.range,
            diagnostics: request.ctx.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: request.ctx,
            range: request.range,
            diagnostics: request.ctx.sema.diagnostics
        )

        if let signature = request.sema.symbols.functionSignature(for: chosen),
           let varianceResult = request.sema.types.buildVarianceProjectionSubstitutions(
               receiverType: lookupReceiverType,
               signature: signature,
               symbols: request.sema.symbols
           )
        {
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: request.sema, interner: request.interner),
               let violatingParamIndex = request.sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols,
                   nullableWriteSymbols: varianceResult.nullableWriteSymbols,
                   argumentTypes: argTypes,
                   parameterMapping: resolved.parameterMapping
               )
            {
                let paramType = request.sema.types.displayName(
                    of: signature.parameterTypes[violatingParamIndex],
                    symbols: request.sema.symbols,
                    interner: request.interner
                )
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(request.interner.resolve(request.calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: request.range
                )
                return request.sema.types.errorType
            }

            let typeVarBySymbol = request.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let mergedSubstitution = resolved.substitutedTypeArguments.merging(
                varianceResult.covariantSubstitution,
                uniquingKeysWith: { _, projected in projected }
            )
            if !validateReifiedTypeArguments(
                for: chosen,
                substitutedTypeArguments: mergedSubstitution,
                range: request.range,
                sema: request.sema
            ) {
                return request.sema.types.errorType
            }
            request.sema.bindings.bindCall(
                request.id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: mergedSubstitution
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
            request.sema.bindings.bindCallableTarget(request.id, target: .symbol(chosen))
            let projectedReturnType = request.sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: mergedSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            let finalType = request.safeCall ? request.sema.types.makeNullable(projectedReturnType) : projectedReturnType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }

        contextualizeArrayReduceRightLambda(args: request.args, resolved: resolved, ctx: request.ctx, locals: &locals)
        contextualizeResolvedIntegerArguments(args: request.args, resolved: resolved, ctx: request.ctx, locals: &locals)
        let returnType = bindCallAndResolveReturnType(request.id, chosen: chosen, resolved: resolved, sema: request.sema)
        applyContractEffects(
            id: request.id,
            chosen: chosen,
            args: request.args,
            ctx: request.ctx,
            locals: &locals
        )
        let adjustedReturnType: TypeID = if request.sema.symbols.externalLinkName(for: chosen) == "kk_kxmini_async_await" {
            deferredAwaitResultType(receiverID: request.receiverID, fallback: returnType, ast: request.ast, sema: request.sema)
        } else {
            returnType
        }
        let finalType = request.safeCall ? request.sema.types.makeNullable(adjustedReturnType) : adjustedReturnType
        request.sema.bindings.bindExprType(request.id, type: finalType)
        return finalType
    }

}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
