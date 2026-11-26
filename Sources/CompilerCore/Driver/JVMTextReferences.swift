import Foundation

/// How a text callable reference invokes its target once the receiver and
/// every parameter value are known.
private enum JVMTextReferenceTarget {
    /// A `JVMTextOperation` row: the same lowering a direct call uses, which
    /// covers `@InlineOnly` functions that have no runtime body (`String.trim()`).
    case operation(JVMTextOperation)
    /// A runtime-facade text declaration with a public static body.
    case facade(JVMForeignMethod)

    var parameters: [JVMTextParameter] {
        switch self {
        case let .operation(op): op.parameters
        case let .facade(method): method.parameters.dropFirst().enumerated().map { JVMTextParameter(name: "p\($0.offset)", type: $0.element) }
        }
    }
}

extension JVMFunctionBuilder {
    /// Resolve a text extension that has no ordinary JVM method or reference
    /// entry. Only declarations from the JVM text surface qualify, so user and
    /// classpath functions with the same name are never redirected here.
    private func textReferenceTarget(_ symbol: SymbolID, signature: FunctionSignature) throws -> JVMTextReferenceTarget? {
        guard program.methods[symbol] == nil, context.jvmImports?.method(for: symbol) == nil, program.references[symbol] == nil,
              program.inlineDeclarations[symbol] == nil, !signature.isSuspend,
              let semanticReceiver = signature.receiverType,
              let declared = program.sema.symbols.symbol(symbol) else { return nil }
        if let entry = program.textLibraryMethods[symbol] {
            let method = entry.method
            guard entry.adaptation == nil, entry.extensionReceiver != nil, method.isStatic, !method.isConstructor,
                  !method.isSuspend, method.owner.hasPrefix("kotlin/text/"), !method.name.contains("$"),
                  !entry.declarations.contains(where: \.isVararg) else { return nil }
            return .facade(method)
        }
        guard let site = declared.declSite, context.sourceManager.path(of: site.start.file).hasPrefix("<kswiftk-jvm>/text") else { return nil }
        let receiver = try program.type(semanticReceiver)
        let receiverName: String
        switch receiver.referenceName {
        case "[C": receiverName = "CharArray"
        case "java/lang/CharSequence": receiverName = "CharSequence"
        case "java/lang/String": receiverName = receiver.isNullable ? "String?" : "String"
        default: return nil
        }
        let name = context.interner.resolve(declared.name)
        let parameterTypes = try signature.parameterTypes.map(program.type)
        let operation = JVMTextOperation.operations.first { op in
            guard op.name == name, op.receiver == receiverName, op.parameters.count == parameterTypes.count else { return false }
            return zip(parameterTypes, op.parameters).allSatisfy { actual, parameter in
                actual.descriptor == parameter.type.descriptor || parameter.variadic && actual.descriptor == "[" + parameter.type.descriptor
            }
        }
        return operation.map(JVMTextReferenceTarget.operation)
    }

    /// `String::trimIndent`, `"abc"::take`, ... compile to a reference class
    /// whose `invoke` calls a static helper performing the call-site lowering,
    /// so the reference works on runtimes without kotlin-reflect and for
    /// functions the Kotlin stdlib only provides as inline bodies.
    func textReference(_ id: ExprID, symbol: SymbolID, receiver: ExprID?, unbound: Bool) throws -> JVMValue? {
        guard let signature = program.sema.symbols.functionSignature(for: symbol),
              let target = try textReferenceTarget(symbol, signature: signature) else { return nil }
        // Plain references resolve through the identifier binding alone; only
        // adapted shapes (defaults, varargs, Unit results) carry a reference binding.
        let binding = program.sema.bindings.callableReferenceBinding(for: id)
        guard let function = functionType(id), function.contextReceivers.isEmpty,
              binding?.boundContextParameterTypes.isEmpty != false, !function.isSuspend else {
            throw fail("Unsupported JVM text callable reference shape.", id)
        }
        let bound = unbound ? nil : try receiver.map(requireValue) ?? implicitExtensionReceiver(id)
        guard unbound || bound != nil else { throw fail("Missing JVM text callable reference receiver.", id) }
        let captures = [bound].compactMap { $0 }
        let inputTypes = try ([function.receiver].compactMap { $0 } + function.params).map(program.type)
        let resultType = try program.type(function.returnType)
        let receiverType = try program.type(signature.receiverType!)
        let number = program.nextClosure; program.nextClosure += 1
        let container = owner?.name ?? program.facadeName, name = container + "$Reference" + String(number)
        let helperRef = JVMFunctionReference(name: "$textReference" + String(number), parameters: captures.map(\.type) + inputTypes, result: resultType, owner: container, ownerIsInterface: owner?.isInterface == true)
        let helper = JVMFunctionBuilder(program: program, declaration: FunDecl(range: arena.exprRange(id)!, name: context.interner.intern(helperRef.name), modifiers: [], body: .unit), reference: helperRef, owner: owner)
        helper.isStaticBody = true
        let inputs = try helperRef.parameters.map { try helper.value($0) }
        var arguments = Array(inputs.dropFirst(captures.count))
        guard bound != nil || !arguments.isEmpty else { throw fail("Missing JVM text callable reference receiver.", id) }
        let source = try helper.convert(bound == nil ? arguments.removeFirst() : inputs[0], to: receiverType)
        let parameters = target.parameters
        var supplied: [Int: [JVMValue]] = [:]
        for (index, argument) in arguments.enumerated() { supplied[binding?.parameterMapping[index] ?? index, default: []].append(argument) }
        guard supplied.keys.allSatisfy(parameters.indices.contains) else { throw fail("Invalid JVM text callable reference argument mapping.", id) }
        var values: [JVMValue] = []
        var varargConversion = false
        for (index, parameter) in parameters.enumerated() {
            let provided = supplied[index] ?? []
            if parameter.variadic {
                let array = JVMValueType.reference("[" + parameter.type.descriptor, nullable: false)
                if provided.count == 1, provided[0].type.descriptor == array.descriptor { values.append(provided[0]) }
                else {
                    varargConversion = true
                    values.append(try helper.textVararg(provided.map { ($0, false) }, element: parameter.type))
                }
            } else if provided.count == 1 {
                values.append(try helper.convert(provided[0], to: parameter.type))
            } else if provided.isEmpty {
                values.append(try helper.textFallback(parameter, source: source, id: id))
            } else { throw fail("Invalid JVM text callable reference argument mapping.", id) }
        }
        let returned: JVMValue?
        let physicalResult: JVMValueType
        let sourceOwner: String, sourceDescriptor: String
        switch target {
        case let .operation(op):
            returned = try helper.emitTextOperation(op, source: source, values: values)
            physicalResult = try program.type(signature.returnType)
            // Reflection describes the Kotlin facade declaration, as kotlinc does,
            // even when the call itself lowers to a JDK method.
            let declared = [receiverType] + parameters.map { $0.variadic ? JVMValueType.reference("[" + $0.type.descriptor, nullable: false) : $0.type }
            sourceOwner = "kotlin/text/StringsKt"
            sourceDescriptor = "(" + declared.map(\.descriptor).joined() + ")" + physicalResult.descriptor
        case let .facade(method):
            physicalResult = method.result
            sourceOwner = method.owner
            sourceDescriptor = method.descriptor
            let output = method.result == .unit ? nil : try helper.value(method.result)
            helper.instructions.append(.foreignCall(method, receiver: nil, arguments: [try helper.convert(source, to: method.parameters[0])] + values, result: output))
            returned = output
        }
        helper.instructions.append(.returnValue(resultType == .unit ? nil : try returned.map { try helper.convert($0, to: resultType) }))
        program.syntheticFunctions[container, default: []].append(helper.finish())
        let unitConversion = resultType == .unit && physicalResult != .unit
        let adapted = binding?.isCallableReferenceAdapter == true || unitConversion
        var generated = try program.closureClass(name, captures: captures.enumerated().map { ("capture\($0.offset)", $0.element.type) }, inputs: inputTypes, result: resultType, helper: helperRef, superclass: "kotlin/jvm/internal/" + (adapted ? "AdaptedFunctionReference" : "FunctionReferenceImpl"))
        let arity = inputTypes.count
        guard arity <= 22 else { throw fail("JVM callable reference arity exceeds 22.", id) }
        program.functionArities.insert(arity)
        var flags: Int32 = 1
        if adapted, varargConversion { flags |= 2 }
        if unitConversion { flags |= 8 }
        let sourceName = context.interner.resolve(program.sema.symbols.symbol(symbol)!.name)
        try initializeReferenceSuperclass(&generated, arity: arity, bound: bound, sourceOwner: sourceOwner, sourceName: sourceName, sourceDescriptor: sourceDescriptor, flags: flags)
        program.closureClasses.append(generated)
        return try constructJDK(name, parameters: captures.map(\.type), arguments: captures)
    }
}
