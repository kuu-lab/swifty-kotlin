
struct NormalizedCallResult {
    let arguments: [KIRExprID]
    let defaultMask: Int64
}

/// A captured value forwarded by the `$default` stub of a local function.
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
            if case let .localNominalDecl(declID, _) = expr {
                collectFunctionDefaults(declID, ast: ast, sema: sema, mapping: &mapping)
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
            // Collect default arguments for primary constructor parameters.
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
        // Primary constructor default arguments.
        let primaryDefaults = classDecl.primaryConstructorParams.map(\.defaultValue)
        if primaryDefaults.contains(where: { $0 != nil }) {
            let ctorSymbols = sema.symbols.symbols(atDeclSite: classDecl.range).compactMap { sema.symbols.symbol($0) }.filter {
                $0.kind == .constructor
            }
            if let primaryCtorSymbol = ctorSymbols.first {
                mapping[primaryCtorSymbol.id] = primaryDefaults
            }
        }
        // Secondary constructor default arguments.
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

    /// KUU-655: resolves the symbol whose `$default` stub a call site must
    /// actually route through. An `override` that inherits its defaults from
    /// an overridden declaration (`OverrideDefaultArgumentInheritance`) never
    /// gets a stub generated for itself -- its own AST has no default value
    /// expressions to evaluate -- only the overridden declaration that
    /// actually owns them does. Every call-site consumer of
    /// `defaultStubSymbol(for:)`/`externalLinkName(for:)` must resolve
    /// through this first, or it looks up a stub that was never emitted.
    func defaultStubOwnerSymbol(for symbol: SymbolID, sema: SemaModule) -> SymbolID {
        sema.symbols.overrideDefaultsBaseSymbol(for: symbol) ?? symbol
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
        let paramCount = signature.parameterTypes.count

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.setCurrentFunctionSymbol(originalSymbol)

        // A local function's lifted body takes its captured values as leading
        // parameters; the stub mirrors them and forwards them to the original.
        var params: [KIRParameter] = captures.map(\.param)
        var captureArgExprs: [KIRExprID] = []
        var dispatchReceiverBinding: (symbol: SymbolID, exprID: KIRExprID)?
        if let receiverType = signature.receiverType {
            // Member extensions (`fun T.m(...)` declared inside a nominal
            // type) carry a dispatch receiver (`this@Owner`) ahead of the
            // extension receiver, so the stub's ABI is
            // [dispatch, extension, params..., mask] and its inner call
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
        let isVararg = normalizeBoolFlags(signature.valueParameterIsVararg, count: paramCount)
        var effectiveParameterTypes: [TypeID] = []
        effectiveParameterTypes.reserveCapacity(paramCount)
        for (index, (paramSymbol, paramType)) in zip(signature.valueParameterSymbols, signature.parameterTypes).enumerated() {
            let effectiveType: TypeID
            if index < isVararg.count, isVararg[index] {
                // Default stubs receive the already-packed vararg collection,
                // just like the original function's call boundary. Keeping the
                // erased collection type here prevents a String/Char element
                // type from being flattened into the aggregate ABI.
                let listFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]
                if let listSymbol = sema.symbols.lookup(fqName: listFQName) {
                    effectiveType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(paramType)],
                        nullability: .nonNull
                    )))
                } else {
                    effectiveType = paramType
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
            }
        }
        let maskSymbol = defaultStubMaskSymbol(for: originalSymbol)
        params.append(KIRParameter(symbol: maskSymbol, type: intType))

        var body: [KIRInstruction] = [.beginBlock]
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
            if capture.isBoxedMutable {
                driver.ctx.setMutableCaptureCell(captureExpr, for: capture.capturedSymbol)
            } else {
                driver.ctx.setLocalValue(captureExpr, for: capture.capturedSymbol)
            }
            captureArgExprs.append(captureExpr)
        }

        let maskExpr = arena.appendExpr(.symbolRef(maskSymbol), type: intType)
        body.append(.constValue(result: maskExpr, value: .symbolRef(maskSymbol)))

        var resolvedParamExprs: [KIRExprID] = []
        for i in 0 ..< paramCount {
            let paramSymbol = signature.valueParameterSymbols[i]
            let effectiveParamType = effectiveParameterTypes[i]
            let paramExpr = arena.appendExpr(.symbolRef(paramSymbol), type: effectiveParamType)
            body.append(.constValue(result: paramExpr, value: .symbolRef(paramSymbol)))

            if i < defaultExpressions.count, let defaultExprID = defaultExpressions[i] {
                let bitValue = Int64(1) << i
                let divisorExpr = arena.appendExpr(.intLiteral(bitValue), type: intType)
                body.append(.constValue(result: divisorExpr, value: .intLiteral(bitValue)))
                let dividedExpr = arena.appendTemporary(type: intType)
                body.append(.binary(op: .divide, lhs: maskExpr, rhs: divisorExpr, result: dividedExpr))
                let twoExpr = arena.appendExpr(.intLiteral(2), type: intType)
                body.append(.constValue(result: twoExpr, value: .intLiteral(2)))
                let bitExpr = arena.appendTemporary(type: intType)
                body.append(.binary(op: .modulo, lhs: dividedExpr, rhs: twoExpr, result: bitExpr))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))

                let skipLabel = driver.ctx.makeLoopLabel()
                let afterLabel = driver.ctx.makeLoopLabel()
                body.append(.jumpIfEqual(lhs: bitExpr, rhs: zeroExpr, target: skipLabel))

                driver.ctx.setLocalValue(paramExpr, for: paramSymbol)
                let defaultVal = driver.lowerExpr(
                    defaultExprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &body
                )
                // A function-typed parameter is consumed through kk_function_invoke,
                // which needs a boxed function value. Call-site lambdas are wrapped
                // by materializeSourceBackedFunctionValueArguments; do the same for
                // a default lambda / callable reference so it isn't a raw fn pointer.
                var defaultValueForCopy = defaultVal
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

        let receiverExprForCall = driver.ctx.activeImplicitReceiverExprID()
        var callArgs: [KIRExprID] = captureArgExprs
        if let dispatchReceiverBinding {
            callArgs.append(dispatchReceiverBinding.exprID)
        }
        if let receiverExprForCall {
            callArgs.append(receiverExprForCall)
        }
        callArgs.append(contentsOf: resolvedParamExprs)
        for tokenSym in reifiedTokenSymbols {
            let tokenExpr = arena.appendExpr(.symbolRef(tokenSym), type: intType)
            body.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSym)))
            callArgs.append(tokenExpr)
        }

        let result = arena.appendTemporary(type: signature.returnType)
        let directCallInstruction = KIRInstruction.call(
            symbol: originalSymbol,
            callee: originalName,
            arguments: callArgs,
            result: result,
            canThrow: false,
            thrownResult: nil
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
        // `super.f()` with an omitted default argument is the one caller
        // that must bypass this and always reach `originalSymbol` directly.
        // Kotlin's own `$default` takes an extra marker parameter for
        // exactly this; here the caller instead sets a reserved high bit
        // (30) of the existing mask parameter (see the `isSuperCall`
        // mask-bit edits in `CallLowerer+MemberCallEmission.swift` and
        // `CallLowerer+SafeMemberCalls.swift`). Bit 30 stays clear of the
        // sign bit and leaves bits 0..29 for up to 30 defaultable
        // parameters, matching the pre-existing (unenforced) limit of this
        // Int64-mask scheme.
        if let receiverExprForCall, signature.receiverType != nil,
           let virtualInstruction = driver.callLowerer.tryEmitVirtualDispatch(
               chosenCallee: originalSymbol,
               calleeName: originalName,
               receiverExpr: nil,
               // Member extensions dispatch on the enclosing owner (the
               // leading `callArgs` entry), not the extension receiver —
               // the extension receiver is an ordinary leading argument.
               loweredReceiverID: dispatchReceiverBinding?.exprID ?? receiverExprForCall,
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
            let superCallBitValue = Int64(1) << 30
            let superCallDivisorExpr = arena.appendExpr(.intLiteral(superCallBitValue), type: intType)
            body.append(.constValue(result: superCallDivisorExpr, value: .intLiteral(superCallBitValue)))
            let superCallDividedExpr = arena.appendTemporary(type: intType)
            body.append(.binary(op: .divide, lhs: maskExpr, rhs: superCallDivisorExpr, result: superCallDividedExpr))
            let superCallTwoExpr = arena.appendExpr(.intLiteral(2), type: intType)
            body.append(.constValue(result: superCallTwoExpr, value: .intLiteral(2)))
            let superCallBitExpr = arena.appendTemporary(type: intType)
            body.append(.binary(op: .modulo, lhs: superCallDividedExpr, rhs: superCallTwoExpr, result: superCallBitExpr))
            let superCallOneExpr = arena.appendExpr(.intLiteral(1), type: intType)
            body.append(.constValue(result: superCallOneExpr, value: .intLiteral(1)))

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
            isInline: false
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
        mask: Int64,
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
        for index in normalized.indices where mask & (Int64(1) << index) != 0 {
            guard index < defaults.count, defaults[index] != nil else { return false }
        }
        let paramSymbols = signature.valueParameterSymbols
        let savedLocals = paramSymbols.map { ctx.localValue(for: $0) }
        var expanded = normalized
        for index in normalized.indices {
            if mask & (Int64(1) << index) != 0, let defaultExpr = defaults[index] {
                let value = driver.lowerExpr(
                    defaultExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let resolved = arena.appendTemporary(type: signature.parameterTypes[index])
                instructions.append(.copy(from: value, to: resolved))
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

        let parameterCount = signature.parameterTypes.count
        guard parameterCount > 0 else {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }
        let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee)
        let isVararg = normalizeBoolFlags(signature.valueParameterIsVararg, count: parameterCount)
        let hasDefaultValues = normalizeBoolFlags(signature.valueParameterHasDefaultValues, count: parameterCount)
        let isSourceBackedPrimitiveArrayFactory = isSourceBackedPrimitiveArrayFactory(
            chosenCallee,
            sema: sema,
            interner: interner
        )
        let preserveArrayVarargs = externalLinkName == "kk_array_of"
            || externalLinkName == "__kk_sequence_of"
            || externalLinkName == "kk_atomic_ref_array_of"
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
            return NormalizedCallResult(arguments: [packedArray, countExpr], defaultMask: 0)
        }

        var normalized: [KIRExprID] = []
        normalized.reserveCapacity(parameterCount)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        var mask: Int64 = 0

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
                        resultType: primitiveArrayType,
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.anyType,
                        types: sema.types,
                        symbols: sema.symbols,
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
            if isVararg[paramIndex] {
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
                    resultType: primitiveArrayType,
                    instructions: &instructions
                )
                // Primitive varargs keep raw array storage, just like the
                // non-empty path. Only reference varargs use the List bridge.
                normalized.append(preserveArrayVarargs || primitiveArrayType != nil
                    ? emptyArray
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
            mask |= Int64(1) << paramIndex
            let sentinel = arena.appendExpr(.intLiteral(0), type: signature.parameterTypes[paramIndex])
            instructions.append(.constValue(result: sentinel, value: .intLiteral(0)))
            normalized.append(sentinel)
        }

        if mask != 0,
           expandSelfTailrecDefaults(
               normalized: &normalized,
               mask: mask,
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
        if mask != 0 {
            for paramIndex in 0 ..< parameterCount {
                let parameterKind = sema.types.kind(of: signature.parameterTypes[paramIndex])
                guard mask & (Int64(1) << paramIndex) == 0,
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
                    into: &instructions
                )
            }
        }
        return NormalizedCallResult(arguments: normalized, defaultMask: mask)
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
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        types: TypeSystem,
        symbols: SymbolTable? = nil,
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
            return typed
        }

        if argIndices.count == 1, allSpread {
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
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, markerIdxExpr, markerExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
                let valueIdxExpr = arena.appendExpr(.intLiteral(Int64(pairIdx * 2 + 1)), type: intType)
                instructions.append(.constValue(result: valueIdxExpr, value: .intLiteral(Int64(pairIdx * 2 + 1))))
                let elementValue = (isSpread || !boxPrimitiveElements)
                    ? providedArguments[idx]
                    : boxVarargElementIfNeeded(
                        providedArguments[idx],
                        types: types,
                        symbols: symbols,
                        arena: arena,
                        interner: interner,
                        anyType: anyType,
                        instructions: &instructions
                    )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, valueIdxExpr, elementValue],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            let pairCountExpr = arena.appendExpr(.intLiteral(Int64(pairsCount)), type: intType)
            instructions.append(.constValue(result: pairCountExpr, value: .intLiteral(Int64(pairsCount))))
            let concatResult = arena.appendTemporary(type: anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_vararg_spread_concat"),
                arguments: [pairsArray, pairCountExpr],
                result: concatResult,
                canThrow: false,
                thrownResult: nil
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
                    arena: arena,
                    interner: interner,
                    anyType: anyType,
                    instructions: &instructions
                )
                : providedArguments[argIndex]
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayID, indexExpr, elementValue],
                result: nil,
                canThrow: false,
                thrownResult: nil
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
        return arrayID
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
            into: &instructions
        )
    }

    private func emitArrayToList(
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
