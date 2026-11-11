struct JVMCompose {
    static let composer = "androidx/compose/runtime/Composer"
    static let composerType = JVMValueType.reference(composer, nullable: false)
    static let suffix: [JVMValueType] = [composerType, .int]
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
            let identity = (reference.owner ?? program.facadeName) + "." + reference.name + reference.descriptor
            let offset = arena.exprRange(id)?.start.offset ?? 0
            // Distinguish branches calling the same composable at different sites.
            try beginComposeGroup(composer, key: JVMCompose.key(identity + "@" + String(offset)))
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
