extension JVMForeignMethod {
    func composePropertyABI(hasReceiver: Bool) -> Bool {
        let receiverCount = hasReceiver ? 1 : 0
        return parameters.count == receiverCount + 2
            && parameters[receiverCount].referenceName == JVMCompose.composer
            && parameters.last == .int
            && annotations.contains { $0.descriptor == "Landroidx/compose/runtime/Composable;" }
    }

    /// Compose appends a Composer, change masks and an optional default mask
    /// to a source signature. The classfile annotation and exact descriptor
    /// distinguish this entry point from ordinary Kotlin functions.
    func composeABI(for function: JVMKotlinFunction) -> (changes: Int, defaults: Int)? {
        guard !function.isSuspend, function.descriptor == descriptor,
              annotations.contains(where: { $0.descriptor == "Landroidx/compose/runtime/Composable;" }),
              function.parameters.count <= 31 else { return nil }
        let firstHidden = function.parameters.count + function.leadingParameterCount
        guard parameters.indices.contains(firstHidden), parameters[firstHidden].referenceName == JVMCompose.composer
        else { return nil }
        let masks = parameters.dropFirst(firstHidden + 1)
        let defaults = function.parameters.contains(where: \.hasDefaultValue) ? 1 : 0
        guard defaults == 0 || function.contextParameters.isEmpty,
              masks.count > defaults, masks.allSatisfy({ $0 == .int }) else { return nil }
        return (changes: masks.count - defaults, defaults: defaults)
    }

    var kotlinComposeABI: (changes: Int, defaults: Int)? {
        kotlinFunction.flatMap { composeABI(for: $0) }
    }

    /// An ordinary member can accept a composable lambda. Compose adds its
    /// Composer and change mask to the callback, leaving the member's arity intact.
    func matchesComposeCallbackMember(parameters logical: [JVMValueType], names: [String?]) -> Bool {
        guard !isStatic, kotlinComposeABI == nil, let function = kotlinFunction,
              !function.isSuspend, function.parameters.map(\.name) == names,
              parameters.count == logical.count else { return false }
        let callbacks = function.composableParameters
        guard !callbacks.isEmpty else { return false }
        let functionPrefix = "kotlin/jvm/functions/Function"
        return zip(parameters, logical).enumerated().allSatisfy { index, pair in
            let (physical, source) = pair
            guard callbacks.contains(index - function.leadingParameterCount) else {
                return physical.descriptor == source.descriptor
            }
            guard let carrier = source.referenceName, carrier.hasPrefix(functionPrefix),
                  let arity = Int(carrier.dropFirst(functionPrefix.count)) else { return false }
            return physical.referenceName == functionPrefix + String(arity + 2)
        }
    }
}

extension JVMFunctionBuilder {
    func readCompositionLocal(_ id: ExprID, receiver: ExprID) throws -> JVMValue? {
        let sema = program.sema
        guard let getter = context.jvmImports?.compositionLocalGetter,
              let selected = sema.bindings.identifierSymbol(for: id) ?? sema.bindings.callBinding(for: id)?.chosenCallee,
              let property = sema.symbols.symbol(sema.symbols.propertySymbol(forAccessor: selected) ?? selected),
              property.kind == .property, context.interner.resolve(property.name) == "current",
              let parent = sema.symbols.parentSymbol(for: property.id),
              try program.className(parent) == getter.owner else { return nil }
        guard let composer = activeComposer else { throw fail("JVM CompositionLocal.current requires an active Composer.", id) }
        let object = try convert(requireValue(receiver), to: .reference(getter.owner, nullable: false))
        let unchanged = try constant(.int(0), .int)
        return try jdkCall(getter.owner, getter.name, getter.parameters, getter.result,
                           receiver: object, arguments: [composer, unchanged], resolved: program.expressionType(id))
    }

    func metadataComposeCall(
        _ method: JVMForeignMethod,
        signature: JVMKotlinFunction,
        abi: (changes: Int, defaults: Int),
        args: [CallArgument],
        binding: CallBinding?,
        receiver: ExprID?,
        receiverValue: JVMValue?,
        expectedResult: JVMValueType?,
        id: ExprID
    ) throws -> JVMIntrinsicResult {
        guard let composer = activeComposer else { throw fail("JVM @Composable calls require an active Composer.", id) }
        guard activeRegions.isEmpty else { throw fail("JVM @Composable calls are unsupported inside a try expression.", id) }
        let dispatch: JVMValue?
        if method.isStatic {
            dispatch = nil
        } else if signature.receiver != nil {
            dispatch = try instance(id)
        } else {
            let value = try receiverValue ?? receiver.map(requireValue) ?? instance(id)
            dispatch = try convert(value, to: .reference(method.owner, nullable: false))
        }
        var prefix = try importedContextArguments(binding, method: method, id: id)
        if signature.receiver != nil {
            guard let value = try receiverValue ?? receiver.map(requireValue) ?? implicitExtensionReceiver(id) else {
                throw fail("Missing JVM Compose extension receiver.", id)
            }
            prefix.append(try convert(value, to: method.parameters[prefix.count]))
        }
        let parameters = Array(method.parameters.dropFirst(prefix.count).prefix(signature.parameters.count))
        let composableParameters = binding.flatMap { context.jvmImports?.importedComposableParameters[$0.chosenCallee] } ?? []
        let explicit = try arguments(args, binding: binding, parameters: parameters, declarations: nil, id: id,
                                     composableParameters: composableParameters,
                                     importedDefaults: signature.parameters.map(\.hasDefaultValue))
        let unchanged = try constant(.int(0), .int)
        var hidden = [composer] + Array(repeating: unchanged, count: abi.changes)
        if abi.defaults != 0 {
            hidden.append(try constant(.int(Int32(bitPattern: explicit.masks[0])), .int))
        }
        let resultType = try expectedResult ?? program.expressionType(id)
        let result = method.result == .unit ? nil : try value(foreignResultType(method.result, resolved: resultType))
        let needsGroup = !method.annotations.contains { $0.descriptor == "Landroidx/compose/runtime/ReadOnlyComposable;" }
        if needsGroup { try beginComposeGroup(composer, key: composeCallKey(at: id)) }
        instructions.append(.foreignCall(method, receiver: dispatch, arguments: prefix + explicit.values + hidden, result: result))
        if needsGroup {
            _ = try jdkCall(JVMCompose.composer, JVMCompose.end, [], .unit, receiver: composer, interface: true)
        }
        return JVMIntrinsicResult(value: try result.map { try convert($0, to: resultType) })
    }
}
