struct JVMCompose {
    struct ImportedCall {
        let defaultMask: Int32
        var contentParameter: Int? = nil

        func usesDefault(at index: Int) -> Bool {
            UInt32(bitPattern: defaultMask) & (1 << index) != 0
        }
    }

    static let composer = "androidx/compose/runtime/Composer"
    static let composerType = JVMValueType.reference(composer, nullable: false)
    static let suffix: [JVMValueType] = [composerType, .int]
    static let lambdaFacade = "androidx/compose/runtime/internal/ComposableLambdaKt"
    static let currentComposer = ["androidx", "compose", "runtime", "currentComposer"]
    static let markers: Set<String> = [
        ComposePlugin.composableFQName,
        ComposePlugin.readonlyComposableFQName,
        ComposePlugin.disallowComposableCallsFQName,
        ComposePlugin.stableFQName,
        ComposePlugin.immutableFQName,
    ]

    static func key(_ text: String) -> Int32 {
        Int32(bitPattern: text.utf8.reduce(UInt32(2_166_136_261)) { hash, byte in
            (hash ^ UInt32(byte)) &* 16_777_619
        })
    }

    static let begin = "startReplaceableGroup"
    static let end = "endReplaceableGroup"
}

extension JVMFunctionBuilder {
    func composeContent(_ id: ExprID) throws -> JVMValue {
        guard case .lambdaLiteral = arena.expr(id) else {
            throw fail("JVM Compose content requires a composable lambda literal.", id)
        }
        let body = try closure(id, composable: true)
        let key = try constant(.int(composeCallKey(at: id)), .int)
        let tracked = try constant(.boolean(true), .boolean)
        let object = JVMValueType.reference("java/lang/Object", nullable: false)
        let lambda = JVMValueType.reference("androidx/compose/runtime/internal/ComposableLambda", nullable: false)
        return try jdkCall(JVMCompose.lambdaFacade, "composableLambdaInstance", [.int, .boolean, object], lambda,
                           arguments: [key, tracked, body])!
    }

    func importedComposableCall(_ method: JVMForeignMethod, contract: JVMCompose.ImportedCall, args: [CallArgument], binding: CallBinding?, id: ExprID) throws -> JVMIntrinsicResult {
        guard let composer = activeComposer else { throw fail("JVM @Composable calls require an active Composer.", id) }
        guard activeRegions.isEmpty else { throw fail("JVM @Composable calls are unsupported inside a try expression.", id) }
        let declared = method.parameters.dropLast(JVMCompose.suffix.count + 1)
        let explicitTypes = declared.enumerated().compactMap { contract.usesDefault(at: $0.offset) ? nil : $0.element }
        guard let binding, let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee),
              signature.parameterTypes.count == explicitTypes.count
        else { throw fail("Invalid JVM Compose library signature.", id) }
        let explicit = try arguments(args, binding: binding, parameters: explicitTypes, declarations: nil, id: id,
                                     composableParameter: contract.contentParameter)
        var supplied = explicit.values.makeIterator()
        let values = try declared.enumerated().map { index, type in
            if contract.usesDefault(at: index) { return try zero(type) }
            guard let next = supplied.next() else { throw fail("Missing JVM Compose library argument.", id) }
            return next
        }
        let changed = try constant(.int(0), .int)
        let defaults = try constant(.int(contract.defaultMask), .int)
        try beginComposeGroup(composer, key: composeCallKey(at: id))
        instructions.append(.foreignCall(method, receiver: nil, arguments: values + [composer, changed, defaults], result: nil))
        _ = try jdkCall(JVMCompose.composer, JVMCompose.end, [], .unit, receiver: composer, interface: true)
        return JVMIntrinsicResult(value: nil)
    }

    private func composeCallKey(at id: ExprID) -> Int32 {
        let identity = (reference.owner ?? program.facadeName) + "." + reference.name + reference.descriptor
        return JVMCompose.key(identity + "@" + String(arena.exprRange(id)?.start.offset ?? 0))
    }

    func beginComposableBody() throws {
        guard let symbol = functionSymbol, program.jvmComposableFunctions.contains(symbol) else { return }
        let composer = try value(JVMCompose.composerType)
        _ = try value(.int)
        activeComposer = composer
        guard !program.sema.readonlyComposableFunctions.contains(symbol) else { return }
        let identity = (reference.owner ?? program.facadeName) + "." + reference.name + reference.descriptor
        try beginComposeGroup(composer, key: JVMCompose.key(identity))
    }

    func beginComposeGroup(_ composer: JVMValue, key: Int32) throws {
        let keyValue = try constant(.int(key), .int)
        _ = try jdkCall(JVMCompose.composer, JVMCompose.begin, [.int], .unit, receiver: composer, arguments: [keyValue], interface: true)
    }

    func composableCall(_ target: JVMFunctionReference, symbol: SymbolID, arguments: [JVMValue], result: JVMValue?, at id: ExprID) throws {
        guard let composer = activeComposer else { throw fail("JVM @Composable calls require an active Composer.", id) }
        guard activeRegions.isEmpty else { throw fail("JVM @Composable calls are unsupported inside a try expression.", id) }
        let needsGroup = !program.sema.readonlyComposableFunctions.contains(symbol)
        if needsGroup {
            // Distinguish branches calling the same composable at different sites.
            try beginComposeGroup(composer, key: composeCallKey(at: id))
        }
        let changed = try constant(.int(0), .int)
        instructions.append(.call(target, arguments + [composer, changed], result))
        if needsGroup { _ = try jdkCall(JVMCompose.composer, JVMCompose.end, [], .unit, receiver: composer, interface: true) }
    }

    func finishComposableBody() {
        guard let composer = activeComposer, let symbol = functionSymbol,
              !program.sema.readonlyComposableFunctions.contains(symbol) else { return }
        let end = JVMForeignMethod(owner: JVMCompose.composer, name: JVMCompose.end, descriptor: "()V", parameters: [], result: .unit, isStatic: false, isInterface: true, isAbstract: true)
        // Every ordinary exit must close the replaceable group. Exceptions
        // unwind through the enclosing Compose composition's abort path.
        instructions = instructions.flatMap { instruction in
            guard case .returnValue = instruction else { return [instruction] }
            return [.foreignCall(end, receiver: composer, arguments: [], result: nil), instruction]
        }
    }

    func readCurrentComposer(_ id: ExprID) throws -> JVMValue? {
        guard context.jvmImports?.hasComposeRuntime == true,
              let symbol = program.sema.bindings.identifierSymbol(for: id),
              let entry = program.sema.symbols.symbol(symbol),
              entry.fqName.map(context.interner.resolve) == JVMCompose.currentComposer,
              let site = entry.declSite,
              context.sourceManager.path(of: site.start.file) == JVMClasspathIndex.composeIntrinsicPath
        else { return nil }
        guard let activeComposer else { throw fail("currentComposer requires a JVM @Composable function.", id) }
        return activeComposer
    }
}
