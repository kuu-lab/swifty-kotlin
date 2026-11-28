import Foundation

private enum JVMTextReferenceTarget {
    case operation(JVMTextOperation)
    case facade(JVMForeignMethod, [ValueParamDecl])

    var parameters: [JVMTextParameter] {
        switch self {
        case let .operation(op): op.parameters
        case let .facade(method, _): method.parameters.dropFirst().enumerated().map { JVMTextParameter(name: "p\($0.offset)", type: $0.element) }
        }
    }
}

extension JVMFunctionBuilder {
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
            return .facade(method, entry.declarations)
        }
        guard let site = declared.declSite, context.sourceManager.path(of: site.start.file).hasPrefix("<kswiftk-jvm>/text") else { return nil }
        let receiver = try program.type(semanticReceiver)
        let receiverName: String
        switch receiver.referenceName {
        case "[C": receiverName = "CharArray"
        case "java/lang/CharSequence": receiverName = receiver.isNullable ? "CharSequence?" : "CharSequence"
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
        let defaultedTail = operation == nil ? JVMTextOperation.operations.first { op in
            guard op.name == name, op.receiver == receiverName, op.parameters.count > parameterTypes.count else { return false }
            return zip(parameterTypes, op.parameters).allSatisfy { $0.descriptor == $1.type.descriptor && !$1.variadic }
                && op.parameters.dropFirst(parameterTypes.count).allSatisfy { $0.fallback != nil }
        } : nil
        return (operation ?? defaultedTail).map(JVMTextReferenceTarget.operation)
    }

    func textReference(_ id: ExprID, symbol: SymbolID, receiver: ExprID?, unbound: Bool) throws -> JVMValue? {
        guard let signature = program.sema.symbols.functionSignature(for: symbol),
              let target = try textReferenceTarget(symbol, signature: signature) else { return nil }
        let binding = program.sema.bindings.callableReferenceBinding(for: id)
        guard let function = functionType(id), function.contextReceivers.isEmpty,
              binding?.boundContextParameterTypes.isEmpty != false else {
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
        helper.isStaticBody = true; helper.isSuspendBody = function.isSuspend
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
        var masks = Array(repeating: UInt32(0), count: (parameters.count + 31) / 32)
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
                if case let .facade(_, declarations) = target, declarations.indices.contains(index), declarations[index].hasDefaultValue {
                    masks[index / 32] |= UInt32(1) << UInt32(index % 32)
                    values.append(try helper.zero(parameter.type))
                } else { values.append(try helper.textFallback(parameter, source: source, id: id)) }
            } else { throw fail("Invalid JVM text callable reference argument mapping.", id) }
        }
        let returned: JVMValue?
        let physicalResult: JVMValueType
        let sourceOwner: String, signatureName: String?, sourceDescriptor: String
        let parameterTypes = parameters.map { $0.variadic ? JVMValueType.reference("[" + $0.type.descriptor, nullable: false) : $0.type }
        switch target {
        case let .operation(op):
            returned = try helper.emitTextOperation(op, source: source, values: values)
            physicalResult = try program.type(signature.returnType)
            let isJDKStringIntern = op.name == "intern" && op.owner == "java/lang/String" && op.instance
            // JVM stubs narrow some CharSequence extensions to String (`String.isBlank`).
            // Recording the stub's receiver breaks `KFunction.call`, which looks the
            // method up by this descriptor; kotlinc records the real declaration.
            let realReceiver = !op.instance && op.method == nil && op.owner == "kotlin/text/StringsKt"
                && op.receiverType.descriptor != receiverType.descriptor && op.result.descriptor == physicalResult.descriptor
            sourceOwner = isJDKStringIntern ? op.owner : "kotlin/text/StringsKt"
            signatureName = isJDKStringIntern ? (op.method ?? op.name) : nil
            let sourceParameters = isJDKStringIntern ? parameterTypes : [realReceiver ? op.receiverType : receiverType] + parameterTypes
            sourceDescriptor = "(" + sourceParameters.map(\.descriptor).joined() + ")" + physicalResult.descriptor
        case let .facade(method, _):
            physicalResult = method.result
            sourceOwner = method.owner
            signatureName = method.name
            sourceDescriptor = method.descriptor
            let output = method.result == .unit ? nil : try helper.value(method.result)
            var arguments = [try helper.convert(source, to: method.parameters[0])] + values
            var target = method
            if masks.contains(where: { $0 != 0 }) {
                arguments += try helper.maskArguments(masks, constructor: false)
                let types = method.parameters + Array(repeating: JVMValueType.int, count: masks.count) + [.reference("java/lang/Object", nullable: true)]
                target = JVMForeignMethod(owner: method.owner, name: method.name + "$default", descriptor: "(" + types.map(\.descriptor).joined() + ")" + method.result.descriptor, parameters: types, result: method.result, isStatic: true, isInterface: false, isAbstract: false)
            }
            helper.instructions.append(.foreignCall(target, receiver: nil, arguments: arguments, result: output))
            returned = output
        }
        helper.instructions.append(.returnValue(resultType == .unit ? nil : try returned.map { try helper.convert($0, to: resultType) }))
        program.syntheticFunctions[container, default: []].append(helper.finish())
        let unitConversion = resultType == .unit && physicalResult != .unit
        let adapted = binding?.isCallableReferenceAdapter == true || unitConversion || function.isSuspend
            || parameters.count != signature.parameterTypes.count
        var generated = try program.closureClass(name, captures: captures.enumerated().map { ("capture\($0.offset)", $0.element.type) }, inputs: inputTypes, result: resultType, helper: helperRef, suspend: function.isSuspend, superclass: "kotlin/jvm/internal/" + (adapted ? "AdaptedFunctionReference" : "FunctionReferenceImpl"))
        let arity = inputTypes.count + (function.isSuspend ? 1 : 0)
        guard arity <= 22 else { throw fail("JVM callable reference arity exceeds 22.", id) }
        program.functionArities.insert(arity)
        var flags: Int32 = 1
        if adapted, varargConversion { flags |= 2 }
        if function.isSuspend { flags |= 4 }
        if unitConversion { flags |= 8 }
        let sourceName = context.interner.resolve(program.sema.symbols.symbol(symbol)!.name)
        try initializeReferenceSuperclass(&generated, arity: arity, bound: bound, sourceOwner: sourceOwner, sourceName: sourceName, signatureName: signatureName, sourceDescriptor: sourceDescriptor, flags: flags)
        program.closureClasses.append(generated)
        return try constructJDK(name, parameters: captures.map(\.type), arguments: captures)
    }
}
