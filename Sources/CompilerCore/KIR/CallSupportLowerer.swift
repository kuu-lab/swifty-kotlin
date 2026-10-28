
struct DefaultArgumentMask: Equatable, Sendable {
    // Each mask word is passed as a Kotlin Int, so keep every word within
    // Kotlin Int's 32-bit representation even though the scratch value is Int64.
    // Generated default-stub mask words use Kotlin Long to preserve all bits.
    static let bitsPerWord = Int64.bitWidth

    /// In-band `super.f(...)` marker bit of the single-word ABI. It stays
    /// clear of parameter bits only while every parameter index sits below
    /// it — a stub whose signature can hold index 30 must carry the marker
    /// in a separate trailing word instead.
    static let superCallMarkerBitIndex = 30

    private let parameterCount: Int

    private(set) var words: [Int64]

    init(parameterCount: Int) {
        self.parameterCount = parameterCount
        let wordCount = max(1, (parameterCount + Self.bitsPerWord - 1) / Self.bitsPerWord)
        words = Array(repeating: 0, count: wordCount)
    }


    var hasSetBits: Bool {
        words.contains { $0 != 0 }
    }

    /// Wide default stubs use a separate trailing word for the super-call
    /// marker so it never shares a bit with a default parameter. "Wide"
    /// starts where a parameter can occupy the marker's in-band position —
    /// index 30, well before the second mask word.
    var stubWords: [Int64] {
        words.count > 1 || parameterCount > Self.superCallMarkerBitIndex
            ? words + [0]
            : words
    }

    func contains(_ parameterIndex: Int) -> Bool {
        guard parameterIndex >= 0 else { return false }
        let wordIndex = parameterIndex / Self.bitsPerWord
        guard words.indices.contains(wordIndex) else { return false }
        let bit = Int64(1) << (parameterIndex % Self.bitsPerWord)
        return words[wordIndex] & bit != 0
    }

    mutating func insert(_ parameterIndex: Int) {
        precondition(parameterIndex >= 0, "Default-argument indices must be non-negative.")
        let wordIndex = parameterIndex / Self.bitsPerWord
        while words.count <= wordIndex {
            words.append(0)
        }
        words[wordIndex] |= Int64(1) << (parameterIndex % Self.bitsPerWord)
    }
}

struct NormalizedCallResult {
    let arguments: [KIRExprID]
    let defaultMaskWords: [Int64]

    var defaultMask: Int64 { defaultMaskWords.first ?? 0 }
    var hasOmittedDefaultArguments: Bool { defaultMaskWords.contains { $0 != 0 } }

    init(arguments: [KIRExprID], defaultMask: Int64) {
        self.arguments = arguments
        defaultMaskWords = [defaultMask]
    }

    init(arguments: [KIRExprID], defaultMaskWords: [Int64]) {
        self.arguments = arguments
        self.defaultMaskWords = defaultMaskWords.isEmpty ? [0] : defaultMaskWords
    }
}

struct DefaultStubCapture {
    let capturedSymbol: SymbolID
    let param: KIRParameter
    let isBoxedMutable: Bool
}

final class CallSupportLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func collectFunctionDefaultArgumentExpressions(
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID: [ExprID?]] {
        var mapping: [SymbolID: [ExprID?]] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                collectFunctionDefaults(declID, ast: ast, sema: sema, mapping: &mapping)
            }
        }
        for expr in ast.arena.snapshot().expressions {
            switch expr {
            case let .localNominalDecl(declID, _):
                collectFunctionDefaults(declID, ast: ast, sema: sema, mapping: &mapping)
            case let .objectLiteral(_, declID, _):
                // Object literal members are expression-owned declarations.
                if let declID {
                    collectFunctionDefaults(declID, ast: ast, sema: sema, mapping: &mapping)
                }
            default:
                break
            }
        }
        return mapping
    }

    func collectFunctionDefaults(
        _ declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        mapping: inout [SymbolID: [ExprID?]]
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case let .funDecl(function):
            guard let symbol = sema.bindings.declSymbols[declID] else { return }
            let defaults = function.valueParams.map(\.defaultValue)
            if defaults.contains(where: { $0 != nil }) {
                mapping[symbol] = defaults
            }
        case let .classDecl(classDecl):
            collectConstructorDefaults(classDecl, ast: ast, sema: sema, mapping: &mapping)
            for item in classDecl.memberFunctions + classDecl.nestedClasses + classDecl.nestedObjects {
                collectFunctionDefaults(item, ast: ast, sema: sema, mapping: &mapping)
            }
            if let companion = classDecl.companionObject {
                collectFunctionDefaults(companion, ast: ast, sema: sema, mapping: &mapping)
            }
        case let .objectDecl(objectDecl):
            for item in objectDecl.memberFunctions + objectDecl.nestedClasses + objectDecl.nestedObjects {
                collectFunctionDefaults(item, ast: ast, sema: sema, mapping: &mapping)
            }
        case let .interfaceDecl(interfaceDecl):
            // KUU-655: an interface method's own default value expressions
            // (e.g. `interface I { fun m(x: Int = 5): String }`) were never
            // collected at all -- this case was missing entirely, so no
            // `m$default` stub was ever generated and any call through it
            // (directly, or via an override that omits the argument) failed
            // at link time with an undefined `_m$default` symbol.
            for item in interfaceDecl.memberFunctions + interfaceDecl.nestedClasses + interfaceDecl.nestedObjects {
                collectFunctionDefaults(item, ast: ast, sema: sema, mapping: &mapping)
            }
            if let companion = interfaceDecl.companionObject {
                collectFunctionDefaults(companion, ast: ast, sema: sema, mapping: &mapping)
            }
        default:
            break
        }
    }

    func collectConstructorDefaults(
        _ classDecl: ClassDecl,
        ast _: ASTModule,
        sema: SemaModule,
        mapping: inout [SymbolID: [ExprID?]]
    ) {
        let primaryDefaults = classDecl.primaryConstructorParams.map(\.defaultValue)
        if primaryDefaults.contains(where: { $0 != nil }) {
            let ctorSymbols = sema.symbols.symbols(atDeclSite: classDecl.range).compactMap { sema.symbols.symbol($0) }.filter {
                $0.kind == .constructor
            }
            if let primaryCtorSymbol = ctorSymbols.first {
                mapping[primaryCtorSymbol.id] = primaryDefaults
            }
        }
        for secondaryCtor in classDecl.secondaryConstructors {
            let secDefaults = secondaryCtor.valueParams.map(\.defaultValue)
            if secDefaults.contains(where: { $0 != nil }) {
                let secCtorSymbols = sema.symbols.symbols(atDeclSite: secondaryCtor.range).compactMap { sema.symbols.symbol($0) }.filter {
                    $0.kind == .constructor
                }
                if let secCtorSymbol = secCtorSymbols.first {
                    mapping[secCtorSymbol.id] = secDefaults
                }
            }
        }
    }

    func defaultStubSymbol(for originalSymbol: SymbolID) -> SymbolID {
        SyntheticSymbolScheme.defaultStubSymbol(for: originalSymbol)
    }

    func defaultStubMaskSymbol(for originalSymbol: SymbolID) -> SymbolID {
        SyntheticSymbolScheme.defaultMaskSymbol(for: originalSymbol)
    }

    func defaultStubMaskSymbols(for originalSymbol: SymbolID, wordCount: Int) -> [SymbolID] {
        guard wordCount > 0 else { return [] }
        return [defaultStubMaskSymbol(for: originalSymbol)]
            + (1 ..< wordCount).map { _ in driver.ctx.allocateSyntheticGeneratedSymbol() }
    }

    /// An `override` that inherits its defaults from an overridden
    /// declaration (`OverrideDefaultArgumentInheritance`) never gets a stub
    /// generated for itself -- its own AST has no default value expressions
    /// to evaluate -- only the overridden declaration that actually owns them
    /// does. Every call-site consumer of
    /// `defaultStubSymbol(for:)`/`externalLinkName(for:)` must resolve
    /// through this first, or it looks up a stub that was never emitted.
    func defaultStubOwnerSymbol(for symbol: SymbolID, sema: SemaModule, callBinding: CallBinding? = nil) -> SymbolID {
        var owner = callBinding?.defaultArgumentOwner ?? symbol
        var visited: Set<SymbolID> = []
        while visited.insert(owner).inserted,
              let base = sema.symbols.overrideDefaultsBaseSymbol(for: owner) {
            owner = base
        }
        return owner
    }

    /// The default ABI receives the same packed storage as the original body.
    private func runtimeReferenceVarargListType(
        at index: Int, functionSymbol: SymbolID, signature: FunctionSignature,
        sema: SemaModule, interner: StringInterner
    ) -> TypeID? {
        guard signature.valueParameterIsVararg.indices.contains(index), signature.valueParameterIsVararg[index],
              primitiveVarargArrayType(elementType: signature.parameterTypes[index], sema: sema, interner: interner) == nil,
              driver.callLowerer.kirIsRuntimeBridgedCallee(functionSymbol, sema: sema),
              !["kk_array_of", "__kk_sequence_of", "kk_atomic_ref_array_of"].contains(sema.symbols.externalLinkName(for: functionSymbol) ?? ""),
              let list = sema.symbols.lookupNominal(fqName: ["kotlin", "collections", "List"].map(interner.intern))
        else { return nil }
        return sema.types.make(.classType(ClassType(classSymbol: list, args: [.invariant(signature.parameterTypes[index])])))
    }

    /// The semantic signature continues to record each vararg's element type.
    private func defaultParameterStorageType(
        at index: Int,
        functionSymbol: SymbolID,
        signature: FunctionSignature,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let parameterType = signature.parameterTypes[index]
        if let list = runtimeReferenceVarargListType(
            at: index, functionSymbol: functionSymbol, signature: signature, sema: sema, interner: interner
        ) { return list }
        if signature.valueParameterIsVararg.indices.contains(index),
           signature.valueParameterIsVararg[index],
           sema.symbols.symbol(functionSymbol)?.flags.contains(.localFunction) == true
        {
            return primitiveVarargArrayType(elementType: parameterType, sema: sema, interner: interner)
                ?? referenceVarargArrayType(elementType: parameterType, sema: sema, interner: interner)
                ?? parameterType
        }
        return driver.constructorParameterStorageType(
            at: index, signature: signature, sema: sema, interner: interner
        )
    }

    /// Sema checks a vararg declaration default as its source array type.
    /// Source bodies and default stubs share packed array storage. Selecting
    /// a stored default must preserve the original array identity.
    private func normalizedDeclaredVarargDefault(
        _ value: KIRExprID,
        at index: Int,
        functionSymbol: SymbolID,
        signature: FunctionSignature,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if runtimeReferenceVarargListType(
            at: index, functionSymbol: functionSymbol, signature: signature, sema: sema, interner: interner
        ) != nil {
            return emitArrayToList(value, arena: arena, interner: interner, anyType: sema.types.anyType, instructions: &instructions)
        }
        // Source bodies and source $default stubs share packed Array storage.
        return value
    }

    func generateDefaultStubFunction(
        originalSymbol: SymbolID,
        originalName: InternedString,
        signature: FunctionSignature,
        defaultExpressions: [ExprID?],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        captures: [DefaultStubCapture] = []
    ) -> KIRDeclID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let maskType = sema.types.make(.primitive(.long, .nonNull))
        let paramCount = signature.parameterTypes.count

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.setCurrentFunctionSymbol(originalSymbol)

        // A local function's lifted body takes its captured values as leading
        // parameters; the stub mirrors them and forwards them to the original.
        var params: [KIRParameter] = captures.map(\.param)
        var captureArgExprs: [KIRExprID] = []
        var dispatchReceiverBinding: (symbol: SymbolID, exprID: KIRExprID)?
        var functionReceiverExpr: KIRExprID?
        if let receiverType = signature.receiverType {
            // Member extensions (`fun T.m(...)` declared inside a nominal
            // type) carry a dispatch receiver (`this@Owner`) ahead of the
            // extension receiver, so the stub's ABI is
            // [dispatch, extension, params..., mask words] and its inner call
            // forwards both receivers.
            if let ownerSymbol = driver.callLowerer.memberExtensionOwnerSymbol(for: originalSymbol, sema: sema),
               let ownerInfo = sema.symbols.symbol(ownerSymbol)
            {
                let ownerArgs: [TypeArg] = signature.typeParameterSymbols
                    .prefix(signature.classTypeParameterCount)
                    .map { .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))) }
                let dispatchReceiverType = sema.types.make(.classType(ClassType(
                    classSymbol: ownerSymbol, args: ownerArgs, nullability: .nonNull
                )))
                let dispatchReceiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: ownerSymbol)
                params.append(KIRParameter(symbol: dispatchReceiverSymbol, type: dispatchReceiverType))
                let dispatchReceiverExpr = arena.appendExpr(.symbolRef(dispatchReceiverSymbol), type: dispatchReceiverType)
                driver.ctx.setLocalValue(dispatchReceiverExpr, for: dispatchReceiverSymbol)
                driver.ctx.setLocalValue(dispatchReceiverExpr, for: ownerSymbol)
                driver.ctx.setLocalDeclaredType(dispatchReceiverType, for: ownerSymbol)
                driver.ctx.setQualifiedThisReceiver(dispatchReceiverExpr, for: ownerInfo.name)
                driver.ctx.setCapturedOuterReceiver(dispatchReceiverExpr, for: ownerSymbol)
                dispatchReceiverBinding = (dispatchReceiverSymbol, dispatchReceiverExpr)
            }
            let receiverSym = syntheticReceiverParameterSymbol(functionSymbol: originalSymbol)
            driver.ctx.setLocalDeclaredType(receiverType, for: receiverSym)
            params.append(KIRParameter(symbol: receiverSym, type: receiverType))
            let receiverExpr = arena.appendExpr(.symbolRef(receiverSym), type: receiverType)
            functionReceiverExpr = receiverExpr
            driver.ctx.setImplicitReceiver(symbol: receiverSym, exprID: receiverExpr)
            if sema.symbols.memberExtensionOwnerSymbol(for: originalSymbol) == nil,
               let owner = sema.symbols.parentSymbol(for: originalSymbol),
               case let .classType(classType) = sema.types.kind(of: receiverType),
               classType.classSymbol == owner
            {
                driver.ctx.setCapturedOuterReceiver(receiverExpr, for: owner)
                driver.ctx.setLocalValue(receiverExpr, for: owner)
                driver.ctx.setLocalDeclaredType(receiverType, for: owner)
            }
        }
        let contextParameters = Array(zip(signature.contextParameterSymbols, signature.contextParameterTypes))
        params.append(contentsOf: contextParameters.map { symbol, type in
            KIRParameter(symbol: symbol, type: type)
        })
        let isVararg = OverloadResolver.normalizeFlags(signature.valueParameterIsVararg, count: paramCount)
        var effectiveParameterTypes: [TypeID] = []
        effectiveParameterTypes.reserveCapacity(paramCount)
        for (index, (paramSymbol, paramType)) in zip(signature.valueParameterSymbols, signature.parameterTypes).enumerated() {
            let effectiveType: TypeID
            if index < isVararg.count, isVararg[index] {
                if let list = runtimeReferenceVarargListType(
                    at: index, functionSymbol: originalSymbol, signature: signature, sema: sema, interner: interner
                ) {
                    effectiveType = list
                } else if let primitiveArray = primitiveVarargArrayType(elementType: paramType, sema: sema, interner: interner) {
                    effectiveType = primitiveArray
                } else {
                    effectiveType = referenceVarargArrayType(
                        elementType: paramType, sema: sema, interner: interner
                    ) ?? paramType
                }
            } else {
                effectiveType = paramType
            }
            effectiveParameterTypes.append(effectiveType)
            params.append(KIRParameter(symbol: paramSymbol, type: effectiveType))
        }
        var reifiedTokenSymbols: [SymbolID] = []
        if !signature.reifiedTypeParameterIndices.isEmpty {
            for index in signature.reifiedTypeParameterIndices.sorted() {
                guard index < signature.typeParameterSymbols.count else { continue }
                let typeParamSymbol = signature.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                params.append(KIRParameter(symbol: tokenSymbol, type: intType))
                reifiedTokenSymbols.append(tokenSymbol)
                if !driver.callLowerer.kirIsRuntimeBridgedCallee(originalSymbol, sema: sema) {
                    let componentSymbol = SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: typeParamSymbol)
                    params.append(KIRParameter(symbol: componentSymbol, type: intType))
                    reifiedTokenSymbols.append(componentSymbol)
                }
            }
        }
        let defaultMask = DefaultArgumentMask(parameterCount: paramCount)
        let maskSymbols = defaultStubMaskSymbols(
            for: originalSymbol,
            wordCount: defaultMask.stubWords.count
        )
        params.append(contentsOf: maskSymbols.map { KIRParameter(symbol: $0, type: maskType) })

        var body: [KIRInstruction] = [.beginBlock]
        var contextArgumentExprs: [KIRExprID] = []
        var contextReceiverValues: [KIRLoweringContext.ContextReceiverValue] = []
        for (contextSymbol, contextType) in contextParameters {
            let expression = arena.appendExpr(.symbolRef(contextSymbol), type: contextType)
            body.append(.constValue(result: expression, value: .symbolRef(contextSymbol)))
            driver.ctx.setLocalValue(expression, for: contextSymbol)
            driver.ctx.setLocalDeclaredType(contextType, for: contextSymbol)
            contextArgumentExprs.append(expression)
            contextReceiverValues.append(.init(type: contextType, exprID: expression))
        }
        // Defaults can themselves capture reified parameters in a lambda.
        // Bind both hidden slots before lowering those expressions.
        for tokenSymbol in reifiedTokenSymbols {
            let token = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            body.append(.constValue(result: token, value: .symbolRef(tokenSymbol)))
            driver.ctx.setLocalValue(token, for: tokenSymbol)
            driver.ctx.setLocalDeclaredType(intType, for: tokenSymbol)
        }
        if let dispatchReceiverBinding {
            body.append(.constValue(result: dispatchReceiverBinding.exprID, value: .symbolRef(dispatchReceiverBinding.symbol)))
        }

        if let dispatchReceiverBinding {
            body.append(.constValue(result: dispatchReceiverBinding.exprID, value: .symbolRef(dispatchReceiverBinding.symbol)))
        }
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }

        driver.objectLiteralLowerer.restoreObjectLiteralCaptures(
            forMemberFunction: originalSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )

        for capture in captures {
            let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
            body.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
            if sema.symbols.delegateGetValueSymbol(for: capture.capturedSymbol) != nil {
                driver.ctx.setLocalDelegateStorage(captureExpr, for: capture.capturedSymbol)
            } else if capture.isBoxedMutable {
                driver.ctx.setMutableCaptureCell(captureExpr, for: capture.capturedSymbol)
            } else {
                driver.ctx.setLocalValue(captureExpr, for: capture.capturedSymbol)
            }
            if capture.param.symbol == scopeSnapshot.currentImplicitReceiverSymbol {
                // Default expressions are lowered in a fresh function scope;
                // restore a captured outer `this` so implicit member reads use it.
                driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: captureExpr)
            }
            captureArgExprs.append(captureExpr)
        }

        let maskExprs = maskSymbols.map { symbol in
            let expression = arena.appendExpr(.symbolRef(symbol), type: maskType)
            body.append(.constValue(result: expression, value: .symbolRef(symbol)))
            return expression
        }
        let defaultMaskExprs = Array(maskExprs.prefix(defaultMask.words.count))

        var resolvedParamExprs: [KIRExprID] = []
        for i in 0 ..< paramCount {
            let paramSymbol = signature.valueParameterSymbols[i]
            let effectiveParamType = effectiveParameterTypes[i]
            let paramExpr = arena.appendExpr(.symbolRef(paramSymbol), type: effectiveParamType)
            body.append(.constValue(result: paramExpr, value: .symbolRef(paramSymbol)))

            if i < defaultExpressions.count, let defaultExprID = defaultExpressions[i] {
                let bitValue = Int64(1) << (i % DefaultArgumentMask.bitsPerWord)
                let bitMaskExpr = arena.appendExpr(.intLiteral(bitValue), type: maskType)
                body.append(.constValue(result: bitMaskExpr, value: .intLiteral(bitValue)))
                let selectedExpr = arena.appendTemporary(type: maskType)
                body.append(.call(
                    callee: interner.intern("kk_bitwise_and"),
                    arguments: [defaultMaskExprs[i / DefaultArgumentMask.bitsPerWord], bitMaskExpr],
                    result: selectedExpr,
                    canThrow: false
                ))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: maskType)
                body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))

                let skipLabel = driver.ctx.makeLoopLabel()
                let afterLabel = driver.ctx.makeLoopLabel()
                body.append(.jumpIfEqual(lhs: selectedExpr, rhs: zeroExpr, target: skipLabel))

                driver.ctx.setLocalValue(paramExpr, for: paramSymbol)
                let defaultVal = driver.ctx.withContextReceiverValues(contextReceiverValues) {
                    driver.lowerExpr(
                        defaultExprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &body
                    )
                }
                // A function-typed parameter is consumed through kk_function_invoke,
                // which needs a boxed function value. Call-site lambdas are wrapped
                // by materializeSourceBackedFunctionValueArguments; do the same for
                // a default lambda / callable reference so it isn't a raw fn pointer.
                var defaultValueForCopy = normalizedDeclaredVarargDefault(
                    defaultVal, at: i, functionSymbol: originalSymbol, signature: signature,
                    sema: sema, arena: arena, interner: interner, instructions: &body
                )
                if case let .functionType(defaultFunctionType) = sema.types.kind(
                    of: sema.types.makeNonNullable(effectiveParamType)
                ) {
                    defaultValueForCopy = driver.callLowerer.materializeFunctionValueArgument(
                        loweredArgID: defaultVal,
                        argExprID: defaultExprID,
                        functionType: defaultFunctionType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &body
                    )
                }
                let resolvedExpr = arena.appendTemporary(type: effectiveParamType)
                body.append(.copy(from: defaultValueForCopy, to: resolvedExpr))
                body.append(.jump(afterLabel))

                body.append(.label(skipLabel))
                body.append(.copy(from: paramExpr, to: resolvedExpr))

                body.append(.label(afterLabel))
                driver.ctx.setLocalValue(resolvedExpr, for: paramSymbol)
                resolvedParamExprs.append(resolvedExpr)
            } else {
                driver.ctx.setLocalValue(paramExpr, for: paramSymbol)
                resolvedParamExprs.append(paramExpr)
            }
        }

        var callArgs: [KIRExprID] = captureArgExprs
        if let dispatchReceiverBinding {
            callArgs.append(dispatchReceiverBinding.exprID)
        }
        if let functionReceiverExpr {
            callArgs.append(functionReceiverExpr)
        }
        callArgs.append(contentsOf: contextArgumentExprs)
        callArgs.append(contentsOf: resolvedParamExprs)
        for tokenSym in reifiedTokenSymbols {
            let tokenExpr = arena.appendExpr(.symbolRef(tokenSym), type: intType)
            body.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSym)))
            callArgs.append(tokenExpr)
        }

        let result = arena.appendTemporary(type: signature.returnType)
        // The expect declaration owns the default expressions and therefore
        // this stub, but its paired actual owns the implementation to call.
        let implementationSymbol = sema.symbols.actualSymbol(for: originalSymbol) ?? originalSymbol
        let implementationName = sema.symbols.symbol(implementationSymbol)?.name ?? originalName
        let directCallInstruction = KIRInstruction.call(
            symbol: implementationSymbol,
            callee: implementationName,
            arguments: callArgs,
            result: result,
            canThrow: false
        )
        // KUU-655: `a.f()` reached through a base-typed receiver must still
        // dispatch to the *runtime* type's override -- Kotlin/JVM's own
        // `$default` synthesizes `this.f(...)` as an ordinary (virtual) call,
        // not a direct call to the declaring class's own implementation.
        // Attempt the same virtual dispatch the ordinary (non-default) call
        // path already uses; `tryEmitVirtualDispatch` itself returns nil
        // (falling back to `directCallInstruction`, unchanged from before
        // this fix) whenever virtual dispatch does not apply here: a
        // constructor (never virtual -- its symbol kind is `.constructor`,
        // not `.function`), a top-level function (no receiver), or a class
        // with no subtypes at all in this compilation (the vtable slot could
        // only ever resolve back to itself).
        //
        // `super.f()` with an omitted default argument must bypass virtual
        // dispatch and reach `originalSymbol` directly. The legacy single-word
        // ABI stores that marker in bit 30; wide masks carry it in an extra
        // trailing word so it cannot overlap a parameter bit.
        if let functionReceiverExpr, signature.receiverType != nil,
           let virtualInstruction = driver.callLowerer.tryEmitVirtualDispatch(
               chosenCallee: implementationSymbol,
               calleeName: implementationName,
               receiverExpr: nil,
               // Member extensions dispatch on the enclosing owner (the
               // leading `callArgs` entry), not the extension receiver —
               // the extension receiver is an ordinary leading argument.
               loweredReceiverID: dispatchReceiverBinding?.exprID ?? functionReceiverExpr,
               isSuperCall: false,
               // `tryEmitVirtualDispatch` strips the leading receiver from
               // `finalArguments` itself (see its `vcArguments.removeFirst()`)
               // -- the convention every other call site follows is to pass
               // it *with* the receiver still included, matching the direct
               // `.call` ABI's own argument list (`callArgs` here). Passing
               // it already-stripped double-strips and shifts every real
               // argument off by one.
               finalArguments: callArgs,
               result: result,
               sema: sema,
               arena: arena,
               interner: interner
           )
        {
            let superCallBitExpr: KIRExprID
            let superCallBitValue: Int64
            if maskExprs.count > defaultMaskExprs.count {
                superCallBitValue = 1
                superCallBitExpr = maskExprs[maskExprs.count - 1]
            } else {
                superCallBitValue = Int64(1) << DefaultArgumentMask.superCallMarkerBitIndex
                let superCallBitMaskExpr = arena.appendExpr(.intLiteral(superCallBitValue), type: maskType)
                body.append(.constValue(result: superCallBitMaskExpr, value: .intLiteral(superCallBitValue)))
                superCallBitExpr = arena.appendTemporary(type: intType)
                body.append(.call(
                    callee: interner.intern("kk_bitwise_and"),
                    arguments: [maskExprs[0], superCallBitMaskExpr],
                    result: superCallBitExpr,
                    canThrow: false
                ))
            }
            let superCallOneExpr = arena.appendExpr(.intLiteral(superCallBitValue), type: maskType)
            body.append(.constValue(result: superCallOneExpr, value: .intLiteral(superCallBitValue)))

            let directDispatchLabel = driver.ctx.makeLoopLabel()
            let afterDispatchLabel = driver.ctx.makeLoopLabel()
            body.append(.jumpIfEqual(lhs: superCallBitExpr, rhs: superCallOneExpr, target: directDispatchLabel))
            body.append(virtualInstruction)
            body.append(.jump(afterDispatchLabel))
            body.append(.label(directDispatchLabel))
            body.append(directCallInstruction)
            body.append(.label(afterDispatchLabel))
        } else {
            body.append(directCallInstruction)
        }
        body.append(.returnValue(result))
        body.append(.endBlock)

        let stubSym = defaultStubSymbol(for: originalSymbol)
        let stubName = interner.intern(interner.resolve(originalName) + "$default")

        let declID = arena.appendDecl(.function(KIRFunction(
            symbol: stubSym,
            name: stubName,
            params: params,
            returnType: signature.returnType,
            body: body,
            isSuspend: signature.isSuspend,
            // Inline callbacks retain their captures for call-site expansion.
            // The default stub must also expand instead of forwarding a raw
            // lambda symbol through an ordinary function-value boundary.
            isInline: sema.symbols.symbol(originalSymbol)?.flags.contains(.inlineFunction) == true
                || !signature.reifiedTypeParameterIndices.isEmpty
        )))

        driver.ctx.restoreScope(scopeSnapshot)

        return declID
    }

    /// A `tailrec` function calling itself with omitted defaults would normally
    /// detour through `f$default`, which calls `f` again and so defeats the
    /// self-call -> loop rewrite of `TailrecLoweringPass` (real recursion, stack
    /// overflow). Evaluate the omitted default expressions at the call site
    /// instead, exactly like the stub does: in parameter order, with earlier
    /// parameters bound to this call's resolved values. Returns `true` when every
    /// omitted default was expanded (the call then needs no mask).
    ///
    /// Restricted to functions without receivers: a default expression of a
    /// member/extension may read `this`, which for a call on a different
    /// receiver would bind to the wrong object here.
    private func expandSelfTailrecDefaults(
        normalized: inout [KIRExprID],
        mask: DefaultArgumentMask,
        chosenCallee: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> Bool {
        let ctx = driver.ctx
        guard ctx.activeFunctionSymbol() == chosenCallee,
              ctx.tailrecFunctionSymbols.contains(chosenCallee),
              signature.receiverType == nil,
              ctx.activeImplicitReceiver() == nil,
              signature.reifiedTypeParameterIndices.isEmpty,
              let defaults = ctx.defaultArguments(for: chosenCallee),
              normalized.count == signature.valueParameterSymbols.count
        else {
            return false
        }
        for index in normalized.indices where mask.contains(index) {
            guard index < defaults.count, defaults[index] != nil else { return false }
        }
        let paramSymbols = signature.valueParameterSymbols
        let savedLocals = paramSymbols.map { ctx.localValue(for: $0) }
        var expanded = normalized
        for index in normalized.indices {
            if mask.contains(index), let defaultExpr = defaults[index] {
                let value = driver.lowerExpr(
                    defaultExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let storageType = defaultParameterStorageType(
                    at: index, functionSymbol: chosenCallee, signature: signature,
                    sema: sema, interner: interner
                )
                let defaultValue = normalizedDeclaredVarargDefault(
                    value, at: index, functionSymbol: chosenCallee, signature: signature,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                let resolved = arena.appendTemporary(type: storageType)
                instructions.append(.copy(from: defaultValue, to: resolved))
                expanded[index] = resolved
            }
            ctx.setLocalValue(expanded[index], for: paramSymbols[index])
        }
        for (symbol, saved) in zip(paramSymbols, savedLocals) {
            if let saved { ctx.setLocalValue(saved, for: symbol) }
        }
        normalized = expanded
        return true
    }

    func normalizedCallArguments(
        providedArguments: [KIRExprID],
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        spreadFlags: [Bool],
        argumentLabels: [InternedString?] = [],
        sourceArgExprs: [ExprID] = [],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> NormalizedCallResult {
        guard let callBinding,
              let chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosenCallee)
        else {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }

        if !callBinding.contextParameterArgumentMapping.isEmpty {
            let explicitContextArgumentIndices = Set(callBinding.contextParameterArgumentMapping.keys)
            let retainedArgumentIndices = providedArguments.indices.filter {
                !explicitContextArgumentIndices.contains($0)
            }
            var compactIndexBySourceIndex: [Int: Int] = [:]
            for (compactIndex, sourceIndex) in retainedArgumentIndices.enumerated() {
                compactIndexBySourceIndex[sourceIndex] = compactIndex
            }
            let compactParameterMapping = Dictionary(uniqueKeysWithValues: callBinding.parameterMapping.compactMap {
                pair -> (Int, Int)? in
                guard let compactIndex = compactIndexBySourceIndex[pair.key] else { return nil }
                return (compactIndex, pair.value)
            })
            let compactBinding = CallBinding(
                chosenCallee: callBinding.chosenCallee,
                substitutedTypeArguments: callBinding.substitutedTypeArguments,
                parameterMapping: compactParameterMapping,
                defaultArgumentOwner: callBinding.defaultArgumentOwner,
                dispatchReceiverSymbol: callBinding.dispatchReceiverSymbol,
                contextParameterReceiverSymbols: callBinding.contextParameterReceiverSymbols,
                isCallableReferenceAdapter: callBinding.isCallableReferenceAdapter,
                boundContextParameterTypes: callBinding.boundContextParameterTypes
            )
            return normalizedCallArguments(
                providedArguments: retainedArgumentIndices.map { providedArguments[$0] },
                callBinding: compactBinding,
                chosenCallee: chosenCallee,
                spreadFlags: retainedArgumentIndices.map { spreadFlags.indices.contains($0) ? spreadFlags[$0] : false },
                argumentLabels: argumentLabels.count == providedArguments.count
                    ? retainedArgumentIndices.map { argumentLabels[$0] }
                    : [],
                sourceArgExprs: sourceArgExprs.count == providedArguments.count
                    ? retainedArgumentIndices.map { sourceArgExprs[$0] }
                    : [],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        let parameterCount = signature.parameterTypes.count
        guard parameterCount > 0 else {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }
        let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee)
        let isVararg = OverloadResolver.normalizeFlags(signature.valueParameterIsVararg, count: parameterCount)
        // Named vararg arguments contain arrays and use the same packing path
        // as explicit spread arguments. Ordinary named parameters remain scalar.
        var spreadFlags = OverloadResolver.normalizeFlags(spreadFlags, count: providedArguments.count)
        for (argIndex, paramIndex) in callBinding.parameterMapping
            where argumentLabels.indices.contains(argIndex)
            && argumentLabels[argIndex] != nil
            && isVararg.indices.contains(paramIndex) && isVararg[paramIndex]
            && spreadFlags.indices.contains(argIndex)
        {
            spreadFlags[argIndex] = true
        }
        let defaultSignature = callBinding.defaultArgumentOwner.flatMap {
            sema.symbols.functionSignature(for: $0)
        } ?? signature
        let hasDefaultValues = OverloadResolver.normalizeFlags(defaultSignature.valueParameterHasDefaultValues, count: parameterCount)
        let isSourceBackedPrimitiveArrayFactory = isSourceBackedPrimitiveArrayFactory(
            chosenCallee,
            sema: sema,
            interner: interner
        )
        let preserveArrayVarargs = externalLinkName == "kk_array_of"
            || externalLinkName == "__kk_sequence_of"
            || externalLinkName == "kk_atomic_ref_array_of"
            || !driver.callLowerer.kirIsRuntimeBridgedCallee(chosenCallee, sema: sema)
        if isStdlibCollectionFactory(chosenCallee, sema: sema) {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }
        var boxedArguments = providedArguments

        var argIndicesByParameter: [Int: [Int]] = [:]
        for (argIndex, paramIndex) in callBinding.parameterMapping {
            guard argIndex >= 0, argIndex < providedArguments.count else {
                continue
            }
            argIndicesByParameter[paramIndex, default: []].append(argIndex)
        }
        for key in Array(argIndicesByParameter.keys) {
            argIndicesByParameter[key]?.sort()
        }
        if isSourceBackedPrimitiveArrayFactory {
            let argIndices = argIndicesByParameter[0] ?? []
            let hasAnySpread = argIndices.contains { idx in
                idx < spreadFlags.count && spreadFlags[idx]
            }
            guard hasAnySpread else {
                return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
            }

            let intType = sema.types.make(.primitive(.int, .nonNull))
            let packed = packVarargArguments(
                argIndices: argIndices,
                providedArguments: providedArguments,
                spreadFlags: spreadFlags,
                listifyResult: false,
                boxPrimitiveElements: false,
                resultType: signature.returnType,
                arena: arena,
                interner: interner,
                intType: intType,
                anyType: sema.types.anyType,
                types: sema.types,
                symbols: sema.symbols,
                sema: sema,
                instructions: &instructions
            )
            return NormalizedCallResult(arguments: [packed], defaultMask: 0)
        }

        let hasOutOfRangeMapping = argIndicesByParameter.keys.contains(where: { $0 < 0 || $0 >= parameterCount })
        let hasMergedParameterMapping = argIndicesByParameter.values.contains(where: { $0.count > 1 })
        if hasOutOfRangeMapping {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }
        if hasMergedParameterMapping {
            let allMergedAreVararg = argIndicesByParameter.allSatisfy { paramIndex, argIndices in
                argIndices.count <= 1 || isVararg[paramIndex]
            }
            if !allMergedAreVararg {
                return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
            }
        }

        if (externalLinkName == "kk_array_of" || externalLinkName == "__kk_immutable_blob_of"),
           parameterCount == 1,
           isVararg.first == true
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let argIndices = argIndicesByParameter[0] ?? []
            let concreteArrayType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: Dictionary(uniqueKeysWithValues: zip(
                    signature.typeParameterSymbols.compactMap {
                        sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)[$0]
                    }, callBinding.substitutedTypeArguments
                )),
                typeVarBySymbol: sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            )
            let packedArray: KIRExprID
            if argIndices.isEmpty {
                packedArray = emitArrayNew(
                    count: 0,
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.anyType,
                    instructions: &instructions
                )
            } else {
                // A function-value element (e.g. `arrayOf(block)`) must be
                // wrapped via kk_function_create_N before the ordinary
                // primitive/value-class boxing below, which has no notion of
                // function values and would otherwise leave a non-capturing
                // lambda's bare, constant-folded symbolRef stored straight
                // into the erased array -- the same erased-boundary wrapping
                // a typeParam-typed argument gets in
                // materializeSourceBackedFunctionValueArguments (KUU-548).
                for argIndex in argIndices {
                    guard argIndex < boxedArguments.count,
                          argIndex < sourceArgExprs.count,
                          !(argIndex < spreadFlags.count && spreadFlags[argIndex]),
                          let materialized = driver.callLowerer.materializeCollectionFactoryFunctionValueElementIfNeeded(
                              boxedArguments[argIndex],
                              sourceArgExprID: sourceArgExprs[argIndex],
                              sema: sema,
                              arena: arena,
                              interner: interner,
                              instructions: &instructions
                          )
                    else {
                        continue
                    }
                    boxedArguments[argIndex] = materialized
                }
                // `kk_array_of` backs both generic arrayOf<T> and primitive array
                // factories. Preserve erased-type boxing and skip boxing for concrete
                // primitive storage.
                boxNonSpreadVarargArguments(
                    argIndices,
                    in: &boxedArguments,
                    elementType: signature.parameterTypes[0],
                    spreadFlags: spreadFlags,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                packedArray = packVarargArguments(
                    argIndices: argIndices,
                    providedArguments: boxedArguments,
                    spreadFlags: spreadFlags,
                    listifyResult: false,
                    boxPrimitiveElements: false,
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.anyType,
                    types: sema.types,
                    symbols: sema.symbols,
                    sema: sema,
                    instructions: &instructions
                )
            }

            let hasAnySpread = argIndices.contains { idx in
                idx < spreadFlags.count && spreadFlags[idx]
            }
            let countExpr: KIRExprID
            if hasAnySpread {
                countExpr = arena.appendTemporary(type: intType)
                emitNonThrowingCall(
                    callee: interner.intern("__kk_array_size"),
                    arg: packedArray,
                    result: countExpr,
                    into: &instructions
                )
            } else {
                countExpr = arena.appendExpr(.intLiteral(Int64(argIndices.count)), type: intType)
                instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(argIndices.count))))
            }
            let typedPackedArray = appendRuntimeArrayComponentTag(
                packedArray, arrayType: concreteArrayType, context: driver.ctx, sema: sema, arena: arena,
                interner: interner, instructions: &instructions
            )
            return NormalizedCallResult(arguments: [typedPackedArray, countExpr], defaultMask: 0)
        }

        let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution = Dictionary(uniqueKeysWithValues: zip(
            signature.typeParameterSymbols.compactMap { variables[$0] },
            callBinding.substitutedTypeArguments
        ))
        func allocatedElementType(_ index: Int) -> TypeID {
            sema.types.substituteTypeParameters(
                in: signature.parameterTypes[index], substitution: substitution,
                typeVarBySymbol: variables
            )
        }
        var normalized: [KIRExprID] = []
        normalized.reserveCapacity(parameterCount)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        var defaultMask = DefaultArgumentMask(parameterCount: parameterCount)

        for paramIndex in 0 ..< parameterCount {
            if let argIndices = argIndicesByParameter[paramIndex] {
                if isVararg[paramIndex] {
                    for argIndex in argIndices
                        where sourceArgExprs.indices.contains(argIndex)
                        && (!spreadFlags.indices.contains(argIndex) || !spreadFlags[argIndex])
                    {
                        boxedArguments[argIndex] = driver.callLowerer.adaptSuspendFunctionValueArgument(
                            providedArguments[argIndex],
                            sourceExpr: sourceArgExprs[argIndex],
                            parameterType: signature.parameterTypes[paramIndex],
                            sema: sema, arena: arena, interner: interner,
                            instructions: &instructions
                        )
                    }
                    let primitiveArrayType = primitiveVarargArrayType(
                        elementType: signature.parameterTypes[paramIndex],
                        sema: sema,
                        interner: interner
                    )
                    let localReferenceVarargArrayType = primitiveArrayType == nil
                        && !driver.callLowerer.kirIsRuntimeBridgedCallee(chosenCallee, sema: sema)
                        ? referenceVarargArrayType(
                            elementType: allocatedElementType(paramIndex),
                            sema: sema,
                            interner: interner
                        )
                        : nil
                    let packedArrayType = primitiveArrayType ?? localReferenceVarargArrayType
                    if (externalLinkName == nil || externalLinkName?.hasPrefix("kk_fn_") == true),
                       case .functionType = sema.types.kind(of: sema.types.makeNonNullable(signature.parameterTypes[paramIndex]))
                    {
                        for argIndex in argIndices {
                            guard sourceArgExprs.indices.contains(argIndex),
                                  !(argIndex < spreadFlags.count && spreadFlags[argIndex]),
                                  let materialized = driver.callLowerer.materializeCollectionFactoryFunctionValueElementIfNeeded(
                                      boxedArguments[argIndex],
                                      sourceArgExprID: sourceArgExprs[argIndex],
                                      sema: sema,
                                      arena: arena,
                                      interner: interner,
                                      instructions: &instructions
                                  )
                            else { continue }
                            boxedArguments[argIndex] = materialized
                        }
                    }
                    boxNonSpreadVarargArguments(
                        argIndices,
                        in: &boxedArguments,
                        elementType: signature.parameterTypes[paramIndex],
                        spreadFlags: spreadFlags,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    let packed = packVarargArguments(
                        argIndices: argIndices,
                        providedArguments: boxedArguments,
                        spreadFlags: spreadFlags,
                        listifyResult: !preserveArrayVarargs && primitiveArrayType == nil,
                        boxPrimitiveElements: !preserveArrayVarargs && primitiveArrayType == nil,
                        resultType: packedArrayType,
                        forceSpreadPacking: !driver.callLowerer.kirIsRuntimeBridgedCallee(chosenCallee, sema: sema),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.anyType,
                        types: sema.types,
                        symbols: sema.symbols,
                        sema: sema,
                        instructions: &instructions
                    )
                    normalized.append(packed)
                } else if let argIndex = argIndices.first {
                    let argument = providedArguments[argIndex]
                    if sourceArgExprs.indices.contains(argIndex) {
                        normalized.append(driver.callLowerer.adaptSuspendFunctionValueArgument(
                            argument,
                            sourceExpr: sourceArgExprs[argIndex],
                            parameterType: signature.parameterTypes[paramIndex],
                            sema: sema, arena: arena, interner: interner,
                            instructions: &instructions
                        ))
                    } else {
                        normalized.append(argument)
                    }
                }
                continue
            }
            // A declaration default takes precedence over the implicit empty
            // array used for an omitted non-optional vararg.
            if isVararg[paramIndex], !hasDefaultValues[paramIndex] {
                let primitiveArrayType = primitiveVarargArrayType(
                    elementType: signature.parameterTypes[paramIndex],
                    sema: sema,
                    interner: interner
                )
                let emptyArray = emitArrayNew(
                    count: 0,
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.anyType,
                    resultType: primitiveArrayType ?? (
                        !driver.callLowerer.kirIsRuntimeBridgedCallee(chosenCallee, sema: sema)
                            ? referenceVarargArrayType(
                                elementType: allocatedElementType(paramIndex),
                                sema: sema,
                                interner: interner
                            )
                            : nil
                    ),
                    instructions: &instructions
                )
                // Empty primitive and local reference varargs keep their array
                // representation. Other reference varargs use the List bridge.
                let typedEmptyArray = appendRuntimeArrayComponentTag(
                    emptyArray, arrayType: arena.exprType(emptyArray), context: driver.ctx, sema: sema,
                    arena: arena, interner: interner, instructions: &instructions
                )
                normalized.append(preserveArrayVarargs || primitiveArrayType != nil
                    ? typedEmptyArray
                    : emitArrayToList(
                        emptyArray,
                        arena: arena,
                        interner: interner,
                        anyType: sema.types.anyType,
                        instructions: &instructions
                    ))
                continue
            }
            // Use semantic hasDefaultValues flag (callee context) instead of
            // looking up AST default expressions at the caller site.
            guard hasDefaultValues[paramIndex] else {
                return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
            }
            defaultMask.insert(paramIndex)
            let sentinelType = defaultParameterStorageType(
                at: paramIndex, functionSymbol: chosenCallee, signature: signature,
                sema: sema, interner: interner
            )
            let sentinel = arena.appendExpr(.intLiteral(0), type: sentinelType)
            instructions.append(.constValue(result: sentinel, value: .intLiteral(0)))
            normalized.append(sentinel)
        }

        if defaultMask.hasSetBits,
           expandSelfTailrecDefaults(
               normalized: &normalized,
               mask: defaultMask,
               chosenCallee: chosenCallee,
               signature: signature,
               ast: ast,
               sema: sema,
               arena: arena,
               interner: interner,
               propertyConstantInitializers: propertyConstantInitializers,
               instructions: &instructions
           )
        {
            return NormalizedCallResult(arguments: normalized, defaultMask: 0)
        }

        // `$default` stubs are synthetic calls and therefore do not carry the
        // original function signature into ABILoweringPass. Preserve the erased
        // representation for explicitly supplied primitive arguments here when
        // a generic or Any-typed parameter is forwarded through such a stub.
        // Defaulted parameters remain sentinels and are materialized inside the
        // stub before the ordinary call boundary applies its own boxing rules.
        if defaultMask.hasSetBits {
            for paramIndex in 0 ..< parameterCount {
                let parameterKind = sema.types.kind(of: defaultSignature.parameterTypes[paramIndex])
                guard !defaultMask.contains(paramIndex),
                      paramIndex < normalized.count,
                      let sourceType = arena.exprType(normalized[paramIndex])
                else {
                    continue
                }
                let isErasedParameter: Bool
                switch parameterKind {
                case .any, .typeParam:
                    isErasedParameter = true
                default:
                    isErasedParameter = false
                }
                guard isErasedParameter else {
                    continue
                }
                normalized[paramIndex] = boxValueForAnySlot(
                    normalized[paramIndex],
                    sourceType: sourceType,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: interner,
                    arena: arena,
                    resultType: signature.parameterTypes[paramIndex],
                    sema: sema,
                    cache: driver.ctx.nominalDispatchCache,
                    into: &instructions
                )
            }
        }
        return NormalizedCallResult(arguments: normalized, defaultMaskWords: defaultMask.stubWords)
    }

    /// Boxes non-spread primitive arguments when the vararg's declared element type is Any/reference/type-param — e.g. `printAll(vararg items: Any)` — but not for a concrete-primitive element type like `IntArray`'s `intArrayOf(vararg elements: Int)`, which needs raw storage.
    func boxNonSpreadVarargArguments(
        _ argIndices: [Int],
        in arguments: inout [KIRExprID],
        elementType: TypeID,
        spreadFlags: [Bool],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard varargElementTypeIsBoxingBoundary(sema.types.kind(of: elementType)) else {
            return
        }
        for argIndex in argIndices {
            guard argIndex < arguments.count else { continue }
            let isSpread = argIndex < spreadFlags.count && spreadFlags[argIndex]
            guard !isSpread else { continue }
            arguments[argIndex] = boxVarargElementIfNeeded(
                arguments[argIndex],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
    }

    private func varargElementTypeIsBoxingBoundary(_ elementKind: TypeKind) -> Bool {
        if case .any = elementKind { return true }
        if case .classType = elementKind { return true }
        if case .typeParam = elementKind { return true }
        return false
    }

    private func boxVarargElementIfNeeded(
        _ argID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let argType = arena.exprType(argID) else {
            return argID
        }
        return boxValueForAnySlot(
            argID,
            sourceType: argType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner,
            arena: arena,
            sema: sema,
            cache: driver.ctx.nominalDispatchCache,
            into: &instructions
        )
    }

    private func isStdlibCollectionFactory(
        _ symbolID: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.wellKnownSymbols.collectionFactory(for: symbolID) != nil
    }

    func packVarargArguments(
        argIndices: [Int],
        providedArguments: [KIRExprID],
        spreadFlags: [Bool],
        listifyResult: Bool = true,
        boxPrimitiveElements: Bool = true,
        resultType: TypeID? = nil,
        forceSpreadPacking: Bool = false,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        types: TypeSystem,
        symbols: SymbolTable? = nil,
        sema: SemaModule? = nil,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let hasAnySpread = argIndices.contains { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }
        let allSpread = !argIndices.isEmpty && argIndices.allSatisfy { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }
        func typedResult(_ expression: KIRExprID) -> KIRExprID {
            guard !listifyResult, let resultType else {
                return expression
            }
            let typed = arena.appendTemporary(type: resultType)
            instructions.append(.copy(from: expression, to: typed))
            if let sema {
                return appendRuntimeArrayComponentTag(
                    typed, arrayType: resultType, context: driver.ctx, sema: sema, arena: arena,
                    interner: interner, instructions: &instructions
                )
            }
            return typed
        }

        if argIndices.count == 1, allSpread, forceSpreadPacking, !listifyResult {
            let copied = arena.appendTemporary(type: resultType ?? anyType)
            instructions.append(.call(
                callee: interner.intern("__kk_array_copyOf"),
                arguments: [providedArguments[argIndices[0]]], result: copied,
                canThrow: false
            ))
            return copied
        }

        if argIndices.count == 1, allSpread, !forceSpreadPacking {
            let spreadValue = providedArguments[argIndices[0]]
            if listifyResult {
                return emitArrayToList(
                    spreadValue,
                    arena: arena,
                    interner: interner,
                    anyType: anyType,
                    instructions: &instructions
                )
            }
            return typedResult(spreadValue)
        }

        if hasAnySpread {
            let pairsCount = argIndices.count
            let pairsArraySize = pairsCount * 2
            let pairsArray = emitArrayNew(
                count: pairsArraySize,
                arena: arena,
                interner: interner,
                intType: intType,
                anyType: anyType,
                instructions: &instructions
            )
            for (pairIdx, idx) in argIndices.enumerated() {
                let isSpread = idx < spreadFlags.count && spreadFlags[idx]
                let markerValue: Int64 = isSpread ? -1 : 1
                let markerExpr = arena.appendExpr(.intLiteral(markerValue), type: intType)
                instructions.append(.constValue(result: markerExpr, value: .intLiteral(markerValue)))
                let markerIdxExpr = arena.appendExpr(.intLiteral(Int64(pairIdx * 2)), type: intType)
                instructions.append(.constValue(result: markerIdxExpr, value: .intLiteral(Int64(pairIdx * 2))))
                instructions.append(.call(
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, markerIdxExpr, markerExpr],
                    result: nil,
                    canThrow: false
                ))
                let valueIdxExpr = arena.appendExpr(.intLiteral(Int64(pairIdx * 2 + 1)), type: intType)
                instructions.append(.constValue(result: valueIdxExpr, value: .intLiteral(Int64(pairIdx * 2 + 1))))
                let elementValue = (isSpread || !boxPrimitiveElements)
                    ? providedArguments[idx]
                    : boxVarargElementIfNeeded(
                        providedArguments[idx],
                        types: types,
                        symbols: symbols,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        anyType: anyType,
                        instructions: &instructions
                    )
                instructions.append(.call(
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, valueIdxExpr, elementValue],
                    result: nil,
                    canThrow: false
                ))
            }
            let pairCountExpr = arena.appendExpr(.intLiteral(Int64(pairsCount)), type: intType)
            instructions.append(.constValue(result: pairCountExpr, value: .intLiteral(Int64(pairsCount))))
            let concatResult = arena.appendTemporary(type: anyType)
            instructions.append(.call(
                callee: interner.intern("kk_vararg_spread_concat"),
                arguments: [pairsArray, pairCountExpr],
                result: concatResult,
                canThrow: false
            ))
            // Convert the concatenated array to a list since vararg parameters
            // are typed as List<T>.
            if listifyResult {
                return emitArrayToList(
                    concatResult,
                    arena: arena,
                    interner: interner,
                    anyType: anyType,
                    instructions: &instructions
                )
            }
            return typedResult(concatResult)
        }

        let count = argIndices.count
        let arrayID = emitArrayNew(
            count: count,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: anyType,
            resultType: resultType,
            instructions: &instructions
        )
        for (slotIndex, argIndex) in argIndices.enumerated() {
            let indexExpr = arena.appendExpr(.intLiteral(Int64(slotIndex)), type: intType)
            instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(slotIndex))))
            let elementValue = boxPrimitiveElements
                ? boxVarargElementIfNeeded(
                    providedArguments[argIndex],
                    types: types,
                    symbols: symbols,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    anyType: anyType,
                    instructions: &instructions
                )
                : providedArguments[argIndex]
            instructions.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [arrayID, indexExpr, elementValue],
                result: nil,
                canThrow: false
            ))
        }
        // Convert the packed array to a list since vararg parameters are typed
        // as List<T> and the callee uses kk_list_* operations.
        if listifyResult {
            return emitArrayToList(
                arrayID,
                arena: arena,
                interner: interner,
                anyType: anyType,
                instructions: &instructions
            )
        }
        return typedResult(arrayID)
    }

    // Vararg element type parameters are erased to the array's Any-typed slots,
    // so a primitive argument must be boxed to carry its concrete type — otherwise
    // e.g. a Char is stored as a bare code point and later misread as an Int. Skips
    // spread arguments (already-boxed array/list references, not scalars) and any
    // argument whose current type isn't a known primitive, so callers that already
    // box their elements (listOf/setOf/format) are not double-boxed.
    private func boxVarargElementIfNeeded(
        _ argID: KIRExprID,
        types: TypeSystem,
        symbols: SymbolTable?,
        sema: SemaModule?,
        arena: KIRArena,
        interner: StringInterner,
        anyType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let argType = arena.exprType(argID) else {
            return argID
        }
        return boxValueForAnySlot(
            argID,
            sourceType: argType,
            types: types,
            symbols: symbols,
            interner: interner,
            arena: arena,
            resultType: anyType,
            sema: sema,
            cache: driver.ctx.nominalDispatchCache,
            into: &instructions
        )
    }

    func emitArrayToList(
        _ arrayID: KIRExprID,
        arena: KIRArena,
        interner: StringInterner,
        anyType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let listID = arena.appendTemporary(type: anyType)
        emitNonThrowingCall(
            callee: interner.intern("__kk_array_toList"),
            arg: arrayID,
            result: listID,
            into: &instructions
        )
        return listID
    }

    func emitArrayNew(
        count: Int,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        resultType: TypeID? = nil,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let countExpr = arena.appendExpr(.intLiteral(Int64(count)), type: intType)
        instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
        let arrayID = arena.appendTemporary(type: resultType ?? anyType)
        emitNonThrowingCall(
            callee: interner.intern("kk_array_new"),
            arg: countExpr,
            result: arrayID,
            into: &instructions
        )
        return arrayID
    }
}
