import Foundation

/// Lowers `@Composable` functions and call sites for the Compose compiler plugin
/// (`androidx.compose.compiler.plugins.kotlin`).
///
/// Runs after `InlineLoweringPass` (so `@Composable` inline helpers and lambda
/// arguments are expanded into their enclosing composable caller) and before
/// `ABILoweringPass`:
///   - Appends `$composer: androidx.compose.runtime.Composer?` and `$changed: kotlin.Int`
///     parameters to each `@Composable` `KIRFunction` and its `FunctionSignature`.
///   - Passes the enclosing `$composer` (or `null` outside `@Composable` scope) and
///     changed mask `0` at every `@Composable` `.call` / `.virtualCall` site.
final class ComposeLoweringPass: LoweringPass {
    static let name = "ComposeLowering"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .propertyLowered

    func shouldRun(module _: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema,
              sema.composePluginEnabled,
              sema.composeComposerType != nil,
              !sema.composableFunctions.isEmpty
        else {
            return false
        }
        return true
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema,
              let composerType = sema.composeComposerType
        else {
            module.recordLowering(Self.name)
            return
        }

        let interner = ctx.interner
        let intType = sema.types.intType
        let composerName = interner.intern("$composer")
        let changedName = interner.intern("$changed")
        let composerSymNonNullType = sema.composeComposerSymbol.map {
            sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
        }

        var currentComposerGetterSymbols: Set<SymbolID> = []
        let currentComposerFQ = ["androidx", "compose", "runtime", "currentComposer"].map { interner.intern($0) }
        for propSym in sema.symbols.lookupAll(fqName: currentComposerFQ) {
            currentComposerGetterSymbols.insert(propSym)
            currentComposerGetterSymbols.insert(SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propSym))
            if let extGetter = sema.symbols.extensionPropertyGetterAccessor(for: propSym) {
                currentComposerGetterSymbols.insert(extGetter)
            }
        }
        let currentComposerCalleeName = interner.intern("<get-currentComposer>")

        // Collect all @Composable KIRFunctions that need ($composer, $changed) injected.
        var injectedParamsByFunction: [SymbolID: (composer: SymbolID, changed: SymbolID)] = [:]
        var composableCalleeSymbols: Set<SymbolID> = []

        for symID in sema.composableFunctions {
            if let sym = sema.symbols.symbol(symID), sym.kind == .function || sym.kind == .constructor {
                composableCalleeSymbols.insert(symID)
            } else if SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(symID) {
                composableCalleeSymbols.insert(symID)
            }
        }

        for decl in module.arena.declarations {
            guard case let .function(fn) = decl,
                  sema.composableFunctions.contains(fn.symbol),
                  !fn.params.contains(where: { sema.symbols.symbol($0.symbol)?.name == composerName })
            else { continue }

            composableCalleeSymbols.insert(fn.symbol)
            let ownerFQName = sema.symbols.symbol(fn.symbol)?.fqName ?? [fn.name]
            let composerParamSym = sema.symbols.define(
                kind: .valueParameter,
                name: composerName,
                fqName: ownerFQName + [composerName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let changedParamSym = sema.symbols.define(
                kind: .valueParameter,
                name: changedName,
                fqName: ownerFQName + [changedName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(fn.symbol, for: composerParamSym)
            sema.symbols.setParentSymbol(fn.symbol, for: changedParamSym)

            if let existingSig = sema.symbols.functionSignature(for: fn.symbol) {
                let updatedSig = appendComposeSignatureParams(
                    existingSig,
                    composerSymbol: composerParamSym,
                    composerType: composerType,
                    changedSymbol: changedParamSym,
                    intType: intType
                )
                sema.symbols.setFunctionSignature(updatedSig, for: fn.symbol)
            }

            injectedParamsByFunction[fn.symbol] = (composerParamSym, changedParamSym)
        }

        guard !composableCalleeSymbols.isEmpty else {
            module.recordLowering(Self.name)
            return
        }

        let arena = module.arena
        arena.transformFunctions { function in
            let injected = injectedParamsByFunction[function.symbol]
            let newParams: [KIRParameter]
            if let injected {
                newParams = function.params + [
                    KIRParameter(symbol: injected.composer, type: composerType),
                    KIRParameter(symbol: injected.changed, type: intType),
                ]
            } else {
                newParams = function.params
            }

            let hasComposableCall = function.body.contains { instr in
                switch instr {
                case let .call(symbol, callee, _, _, _, _, _, _):
                    if callee == currentComposerCalleeName {
                        return true
                    }
                    if let symbol, currentComposerGetterSymbols.contains(symbol) {
                        return true
                    }
                    return symbol.map { composableCalleeSymbols.contains($0) } ?? false
                case let .virtualCall(symbol, _, _, _, _, _, _, _):
                    return symbol.map { composableCalleeSymbols.contains($0) } ?? false
                default:
                    return false
                }
            }

            guard hasComposableCall || injected != nil else {
                return function
            }

            var newBody: [KIRInstruction] = []
            var newLocations: [SourceRange?] = []
            newBody.reserveCapacity(function.body.count + 4)
            newLocations.reserveCapacity(function.body.count + 4)

            var activeComposerExpr: KIRExprID?
            var zeroChangedExpr: KIRExprID?
            var insertedPreamble = false

            let explicitComposerParam: KIRParameter? = function.params.first { param in
                param.type == composerType || param.type == composerSymNonNullType
            }

            func emitPreambleIfNeeded() {
                guard hasComposableCall, !insertedPreamble else { return }
                insertedPreamble = true

                if let injected {
                    let compRef = arena.appendExpr(.symbolRef(injected.composer), type: composerType)
                    newBody.append(.constValue(result: compRef, value: .symbolRef(injected.composer)))
                    newLocations.append(function.sourceRange)
                    activeComposerExpr = compRef
                } else if let explicitComposerParam {
                    let compRef = arena.appendExpr(.symbolRef(explicitComposerParam.symbol), type: explicitComposerParam.type)
                    newBody.append(.constValue(result: compRef, value: .symbolRef(explicitComposerParam.symbol)))
                    newLocations.append(function.sourceRange)
                    activeComposerExpr = compRef
                } else {
                    let nullComp = arena.appendExpr(.null, type: composerType)
                    newBody.append(.constValue(result: nullComp, value: .null))
                    newLocations.append(function.sourceRange)
                    activeComposerExpr = nullComp
                }

                let changedZero = arena.appendExpr(.intLiteral(0), type: intType)
                newBody.append(.constValue(result: changedZero, value: .intLiteral(0)))
                newLocations.append(function.sourceRange)
                zeroChangedExpr = changedZero
            }

            if !function.body.contains(where: { if case .beginBlock = $0 { return true }; return false }) {
                emitPreambleIfNeeded()
            }

            for (index, instruction) in function.body.enumerated() {
                let loc = function.instructionLocations.indices.contains(index)
                    ? function.instructionLocations[index]
                    : nil

                switch instruction {
                case .beginBlock:
                    newBody.append(instruction)
                    newLocations.append(loc)
                    emitPreambleIfNeeded()

                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
                    let isCurrentComposerIntrinsic = callee == currentComposerCalleeName
                        || (symbol.map { currentComposerGetterSymbols.contains($0) } ?? false)
                    if isCurrentComposerIntrinsic, let compExpr = activeComposerExpr {
                        if let result {
                            newBody.append(.copy(from: compExpr, to: result))
                            newLocations.append(loc)
                        }
                    } else if let symbol, composableCalleeSymbols.contains(symbol),
                              let compExpr = activeComposerExpr,
                              let chgExpr = zeroChangedExpr
                    {
                        newBody.append(.call(
                            symbol: symbol,
                            callee: callee,
                            arguments: arguments + [compExpr, chgExpr],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall,
                            qualifiedSuperType: qualifiedSuperType
                        ))
                        newLocations.append(loc)
                    } else {
                        newBody.append(instruction)
                        newLocations.append(loc)
                    }

                case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
                    if let symbol, composableCalleeSymbols.contains(symbol),
                       let compExpr = activeComposerExpr,
                       let chgExpr = zeroChangedExpr
                    {
                        newBody.append(.virtualCall(
                            symbol: symbol,
                            callee: callee,
                            receiver: receiver,
                            arguments: arguments + [compExpr, chgExpr],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            dispatch: dispatch
                        ))
                        newLocations.append(loc)
                    } else {
                        newBody.append(instruction)
                        newLocations.append(loc)
                    }

                default:
                    newBody.append(instruction)
                    newLocations.append(loc)
                }
            }

            return KIRFunction(
                symbol: function.symbol,
                name: function.name,
                params: newParams,
                returnType: function.returnType,
                body: newBody,
                isSuspend: function.isSuspend,
                isInline: function.isInline,
                isInlineOnly: function.isInlineOnly,
                isTailrec: function.isTailrec,
                sourceRange: function.sourceRange,
                instructionLocations: newLocations
            )
        }

        module.recordLowering(Self.name)
    }

    private func appendComposeSignatureParams(
        _ signature: FunctionSignature,
        composerSymbol: SymbolID,
        composerType: TypeID,
        changedSymbol: SymbolID,
        intType: TypeID
    ) -> FunctionSignature {
        let originalCount = signature.parameterTypes.count
        var valueParams = signature.valueParameterSymbols
        while valueParams.count < originalCount {
            valueParams.append(composerSymbol)
        }
        valueParams.append(composerSymbol)
        valueParams.append(changedSymbol)

        var unsafeVariance = signature.valueParameterUnsafeVarianceTypeParameterSymbols
        if !unsafeVariance.isEmpty {
            while unsafeVariance.count < originalCount {
                unsafeVariance.append([])
            }
            unsafeVariance.append([])
            unsafeVariance.append([])
        }

        var hasDefaults = signature.valueParameterHasDefaultValues
        if !hasDefaults.isEmpty {
            while hasDefaults.count < originalCount {
                hasDefaults.append(false)
            }
            hasDefaults.append(false)
            hasDefaults.append(false)
        }

        var isVararg = signature.valueParameterIsVararg
        if !isVararg.isEmpty {
            while isVararg.count < originalCount {
                isVararg.append(false)
            }
            isVararg.append(false)
            isVararg.append(false)
        }

        var allowsNLR = signature.valueParameterAllowsNonLocalReturn
        if !allowsNLR.isEmpty {
            while allowsNLR.count < originalCount {
                allowsNLR.append(true)
            }
            allowsNLR.append(true)
            allowsNLR.append(true)
        }

        return FunctionSignature(
            receiverType: signature.receiverType,
            contextReceiverTypes: signature.contextReceiverTypes,
            contextParameterSymbols: signature.contextParameterSymbols,
            contextParameterTypes: signature.contextParameterTypes,
            parameterTypes: signature.parameterTypes + [composerType, intType],
            returnType: signature.returnType,
            isSuspend: signature.isSuspend,
            canThrow: signature.canThrow,
            valueParameterSymbols: valueParams,
            valueParameterUnsafeVarianceTypeParameterSymbols: unsafeVariance,
            valueParameterHasDefaultValues: hasDefaults,
            valueParameterIsVararg: isVararg,
            valueParameterAllowsNonLocalReturn: allowsNLR,
            hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
            hasStableParameterNames: signature.hasStableParameterNames,
            typeParameterSymbols: signature.typeParameterSymbols,
            reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
            typeParameterUpperBounds: signature.typeParameterUpperBounds,
            typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
            classTypeParameterCount: signature.classTypeParameterCount
        )
    }
}
