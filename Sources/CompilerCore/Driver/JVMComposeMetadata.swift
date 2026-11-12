extension JVMForeignMethod {
    /// Compose appends a Composer, change masks and an optional default mask
    /// to a source signature. The classfile annotation and exact descriptor
    /// distinguish this entry point from ordinary Kotlin static functions.
    func composeABI(for function: JVMKotlinFunction) -> (changes: Int, defaults: Int)? {
        guard isStatic, !function.isSuspend, function.descriptor == descriptor,
              annotations.contains(where: { $0.descriptor == "Landroidx/compose/runtime/Composable;" }),
              function.parameters.count <= 31 else { return nil }
        let firstHidden = function.parameters.count + (function.receiver == nil ? 0 : 1)
        guard parameters.indices.contains(firstHidden), parameters[firstHidden].referenceName == JVMCompose.composer
        else { return nil }
        let masks = parameters.dropFirst(firstHidden + 1)
        let defaults = function.parameters.contains(where: \.hasDefaultValue) ? 1 : 0
        guard masks.count > defaults, masks.allSatisfy({ $0 == .int }) else { return nil }
        return (changes: masks.count - defaults, defaults: defaults)
    }

    var kotlinComposeABI: (changes: Int, defaults: Int)? {
        kotlinFunction.flatMap { composeABI(for: $0) }
    }
}

extension JVMFunctionBuilder {
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
        var prefix: [JVMValue] = []
        if signature.receiver != nil {
            guard let value = try receiverValue ?? receiver.map(requireValue) ?? implicitExtensionReceiver(id) else {
                throw fail("Missing JVM Compose extension receiver.", id)
            }
            prefix.append(try convert(value, to: method.parameters[0]))
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
        let result = method.result == .unit ? nil : try value(expectedResult ?? program.expressionType(id))
        try beginComposeGroup(composer, key: composeCallKey(at: id))
        instructions.append(.foreignCall(method, receiver: nil, arguments: prefix + explicit.values + hidden, result: result))
        _ = try jdkCall(JVMCompose.composer, JVMCompose.end, [], .unit, receiver: composer, interface: true)
        return JVMIntrinsicResult(value: result)
    }
}
