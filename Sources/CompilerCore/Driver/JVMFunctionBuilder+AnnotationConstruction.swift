extension JVMFunctionBuilder {
    /// Annotation classes are JVM interfaces. Their public reflection constructor
    /// works with both the repository runtime and the official Kotlin runtime.
    func annotationConstruction(_ args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard let binding = program.sema.bindings.callBinding(for: id),
              program.sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor,
              let owner = program.sema.symbols.parentSymbol(for: binding.chosenCallee),
              program.sema.symbols.symbol(owner)?.kind == .annotationClass,
              let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee) else { return nil }
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let map: JVMValueType = .reference("java/util/Map", nullable: false)
        let values = try constructJDK("java/util/LinkedHashMap")
        var supplied: Set<Int> = []
        for (index, argument) in args.enumerated() {
            let parameter = binding.parameterMapping[index] ?? index
            guard !argument.isSpread, signature.valueParameterSymbols.indices.contains(parameter),
                  supplied.insert(parameter).inserted,
                  let symbol = program.sema.symbols.symbol(signature.valueParameterSymbols[parameter]) else {
                throw fail("Unsupported JVM annotation constructor argument mapping.", id)
            }
            let name = try constant(.string(context.interner.resolve(symbol.name)), .string)
            let value = try requireValue(argument.expr)
            _ = try jdkCall("java/util/Map", "put", [object, object], object,
                            receiver: values, arguments: [name, value], interface: true)
        }
        let type = try program.expressionType(id)
        let klass = try jdkCall("kotlin/jvm/internal/Reflection", "getOrCreateKotlinClass",
                                [.reference("java/lang/Class", nullable: false)], .reference("kotlin/reflect/KClass", nullable: false),
                                arguments: [javaClass(type)])!
        let constructors = try jdkCall("kotlin/reflect/KClass", "getConstructors", [], .reference("java/util/Collection", nullable: false), receiver: klass, interface: true)!
        let constructorIterator = try jdkCall("java/util/Collection", "iterator", [], .reference("java/util/Iterator", nullable: false), receiver: constructors, interface: true)!
        let constructor = try jdkCall("java/util/Iterator", "next", [], object, receiver: constructorIterator, interface: true, resolved: .reference("kotlin/reflect/KFunction", nullable: false))!
        let parameters = try jdkCall("kotlin/reflect/KCallable", "getParameters", [], .reference("java/util/List", nullable: false), receiver: constructor, interface: true)!
        let iterator = try jdkCall("java/lang/Iterable", "iterator", [], .reference("java/util/Iterator", nullable: false), receiver: parameters, interface: true)!
        let arguments = try constructJDK("java/util/LinkedHashMap")
        let loop = label(), end = label(), next = label()
        mark(loop)
        let available = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)!
        instructions.append(.jumpIfFalse(available, end))
        let parameter = try jdkCall("java/util/Iterator", "next", [], object, receiver: iterator, interface: true, resolved: .reference("kotlin/reflect/KParameter", nullable: false))!
        let name = try jdkCall("kotlin/reflect/KParameter", "getName", [], .reference("java/lang/String", nullable: true), receiver: parameter, interface: true)!
        let hasArgument = try jdkCall("java/util/Map", "containsKey", [object], .boolean, receiver: values, arguments: [name], interface: true)!
        instructions.append(.jumpIfFalse(hasArgument, next))
        let value = try jdkCall("java/util/Map", "get", [object], object, receiver: values, arguments: [name], interface: true)!
        _ = try jdkCall("java/util/Map", "put", [object, object], object, receiver: arguments, arguments: [parameter, value], interface: true)
        mark(next); jump(loop); mark(end)
        let result = try jdkCall("kotlin/reflect/KCallable", "callBy", [map], object, receiver: constructor, arguments: [arguments], interface: true, resolved: type)
        return JVMIntrinsicResult(value: result)
    }
}
