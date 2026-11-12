import Foundation

extension JVMProgramBuilder {
    func jvmOverloads(
        _ function: JVMFunction,
        declaration: FunDecl,
        symbol: SymbolID,
        owner: JVMClassPlan?
    ) throws -> [JVMFunction] {
        guard sema.symbols.annotations(for: symbol).contains(where: { KnownCompilerAnnotation.jvmOverloads.matches($0.annotationFQName) }),
              let signature = sema.symbols.functionSignature(for: symbol)
        else {
            return []
        }

        let defaults = signature.valueParameterHasDefaultValues
        guard defaults.count == declaration.valueParams.count,
              signature.parameterTypes.count == defaults.count,
              signature.valueParameterSymbols.count == defaults.count,
              signature.valueParameterIsVararg.count == defaults.count,
              function.reference.parameters.count == (extensionSymbols.contains(symbol) ? 1 : 0) + defaults.count
        else {
            throw JVMFrontendError(message: "Unsupported JVM @JvmOverloads function signature.", range: declaration.range)
        }

        let defaultIndices = defaults.indices.filter { defaults[$0] }
        guard !defaultIndices.isEmpty else { return [] }

        let receiverCount = extensionSymbols.contains(symbol) ? 1 : 0
        let defaultTarget = try defaultReference(defaultOwner(symbol))
        var result: [JVMFunction] = []

        for omittedDefaultIndex in defaultIndices.reversed() {
            let omittedIndices = defaults.indices.filter { $0 >= omittedDefaultIndex && defaults[$0] }
            let omittedSet = Set(omittedIndices)
            let keptIndices = defaults.indices.filter { !omittedSet.contains($0) }
            let wrapperSignature = signature.selectingValueParameters(keptIndices)
            let wrapperParameters = keptIndices.map { declaration.valueParams[$0] }
            let wrapperDeclaration = FunDecl(
                range: declaration.range,
                name: declaration.name,
                modifiers: declaration.modifiers,
                typeParams: declaration.typeParams,
                receiverType: declaration.receiverType,
                contextReceivers: declaration.contextReceivers,
                valueParams: wrapperParameters,
                returnType: declaration.returnType,
                isSuspend: declaration.isSuspend
            )
            let wrapperReference = JVMFunctionReference(
                name: function.reference.name,
                parameters: Array(function.reference.parameters.prefix(receiverCount)) + keptIndices.map { function.reference.parameters[receiverCount + $0] },
                result: function.reference.result,
                owner: function.reference.owner,
                ownerIsInterface: function.reference.ownerIsInterface,
                isSuspend: function.reference.isSuspend
            )
            let builder = JVMFunctionBuilder(program: self, declaration: wrapperDeclaration, reference: wrapperReference, owner: owner)
            builder.functionSymbol = symbol
            builder.semanticSignature = wrapperSignature
            try builder.prepareParameters()

            var arguments: [JVMValue] = []
            if owner != nil {
                guard let receiver = builder.thisValue else {
                    throw JVMFrontendError(message: "Missing JVM @JvmOverloads dispatch receiver.", range: declaration.range)
                }
                arguments.append(receiver)
            }
            if let extensionReceiver = builder.extensionValue { arguments.append(extensionReceiver) }

            var masks = Array(repeating: UInt32(0), count: (defaults.count + 31) / 32)
            for index in defaults.indices {
                if omittedSet.contains(index) {
                    arguments.append(try builder.zero(function.reference.parameters[receiverCount + index]))
                    masks[index / 32] |= UInt32(1) << UInt32(index % 32)
                } else {
                    arguments.append(try builder.lookup(declaration.valueParams[index].name).value)
                }
            }
            arguments += try builder.maskArguments(masks, constructor: false)

            let callResult = function.reference.result == .unit ? nil : try builder.value(function.reference.result)
            builder.instructions.append(.call(defaultTarget, arguments, callResult))
            builder.instructions.append(.returnValue(callResult))

            var wrapper = builder.finish()
            wrapper.parameterDefaultFlags = Array(repeating: false, count: keptIndices.count)
            wrapper = try describe(
                wrapper,
                signature: wrapperSignature,
                parameters: declaration.typeParams,
                sourceDeclaration: (symbol, wrapperDeclaration)
            )
            wrapper = try annotated(wrapper, symbol: symbol, signature: wrapperSignature)
            result.append(wrapper)
        }
        return result
    }
}

private extension FunctionSignature {
    func selectingValueParameters(_ indices: [Int]) -> FunctionSignature {
        func select<T>(_ values: [T]) -> [T] {
            indices.compactMap { values.indices.contains($0) ? values[$0] : nil }
        }

        return FunctionSignature(
            receiverType: receiverType,
            contextReceiverTypes: contextReceiverTypes,
            contextParameterSymbols: contextParameterSymbols,
            contextParameterTypes: contextParameterTypes,
            parameterTypes: select(parameterTypes),
            returnType: returnType,
            isSuspend: isSuspend,
            canThrow: canThrow,
            valueParameterSymbols: select(valueParameterSymbols),
            valueParameterUnsafeVarianceTypeParameterSymbols: select(valueParameterUnsafeVarianceTypeParameterSymbols),
            valueParameterHasDefaultValues: Array(repeating: false, count: indices.count),
            valueParameterIsVararg: select(valueParameterIsVararg),
            valueParameterAllowsNonLocalReturn: select(valueParameterAllowsNonLocalReturn),
            hasExplicitInlineParameterMetadata: hasExplicitInlineParameterMetadata,
            hasStableParameterNames: hasStableParameterNames,
            typeParameterSymbols: typeParameterSymbols,
            reifiedTypeParameterIndices: reifiedTypeParameterIndices,
            typeParameterUpperBounds: typeParameterUpperBounds,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList,
            classTypeParameterCount: classTypeParameterCount
        )
    }
}
