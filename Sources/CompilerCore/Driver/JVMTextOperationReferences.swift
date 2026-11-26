import Foundation

extension JVMFunctionBuilder {
    func textOperationReference(_ id: ExprID, symbol: SymbolID, receiver: ExprID?, unbound: Bool) throws -> JVMValue? {
        guard program.methods[symbol] == nil, program.references[symbol] == nil, program.textLibraryMethods[symbol] == nil,
              context.jvmImports?.method(for: symbol) == nil,
              let name = textStubName(symbol),
              let signature = program.sema.symbols.functionSignature(for: symbol),
              let semanticReceiver = signature.receiverType else { return nil }
        let receiverType = try program.type(semanticReceiver)
        let candidates = textOperationCandidates(name, receiver: receiverType)
        guard !candidates.isEmpty else { return nil }
        let signatureTypes = try signature.parameterTypes.map(program.type)
        let defaultedTail = candidates.first { op in
            signatureTypes.count < op.parameters.count
                && zip(signatureTypes, op.parameters).allSatisfy { $0.descriptor == $1.type.descriptor && !$1.variadic }
                && op.parameters.dropFirst(signatureTypes.count).allSatisfy { $0.fallback != nil }
        }
        guard let op = exactTextOperation(candidates, parameterTypes: signatureTypes) ?? defaultedTail else {
            throw fail("Unsupported JVM text reference overload: " + name + " (" + signatureTypes.map(\.descriptor).joined() + ").", id)
        }
        let binding = program.sema.bindings.callableReferenceBinding(for: id)
        guard let function = functionType(id), function.contextReceivers.isEmpty,
              binding?.boundContextParameterTypes.isEmpty != false else {
            throw fail("Unsupported JVM text reference adaptation.", id)
        }
        let bound = unbound ? nil : try receiver.map(requireValue) ?? instance(id)
        let captures = [bound].compactMap { $0 }
        let inputTypes = try ([function.receiver].compactMap { $0 } + function.params).map(program.type)
        let resultType = try program.type(function.returnType)
        let arity = inputTypes.count + (function.isSuspend ? 1 : 0)
        guard arity <= 22 else { throw fail("JVM callable reference arity exceeds 22.", id) }
        let number = program.nextClosure; program.nextClosure += 1
        let container = owner?.name ?? program.facadeName, className = container + "$Reference" + String(number)
        let helperRef = JVMFunctionReference(name: "$lambdaText" + String(number), parameters: captures.map(\.type) + inputTypes, result: resultType, owner: container, ownerIsInterface: owner?.isInterface == true)
        let helper = JVMFunctionBuilder(program: program, declaration: FunDecl(range: arena.exprRange(id)!, name: context.interner.intern(helperRef.name), modifiers: [], body: .unit), reference: helperRef, owner: owner)
        helper.isStaticBody = true; helper.isSuspendBody = function.isSuspend
        let inputs = try helperRef.parameters.map { try helper.value($0) }
        var arguments = Array(inputs.dropFirst(captures.count))
        if bound == nil, arguments.isEmpty { throw fail("Missing JVM text reference receiver.", id) }
        let source = try helper.convert(bound == nil ? arguments.removeFirst() : inputs[0], to: receiverType)
        var provided: [Int: [JVMValue]] = [:]
        for (index, argument) in arguments.enumerated() {
            let parameter = binding?.parameterMapping[index] ?? index
            guard op.parameters.indices.contains(parameter) else { throw fail("Invalid JVM text reference argument mapping.", id) }
            provided[parameter, default: []].append(argument)
        }
        var supplied: [Int: JVMValue] = [:]
        var varargConversion = false
        for (index, values) in provided {
            let parameter = op.parameters[index]
            guard parameter.variadic else {
                guard values.count == 1 else { throw fail("Invalid JVM text reference argument mapping.", id) }
                supplied[index] = values[0]; continue
            }
            if values.count == 1, values[0].type.descriptor == "[" + parameter.type.descriptor {
                supplied[index] = values[0]
            } else {
                varargConversion = true
                supplied[index] = try helper.textVararg(values.map { ($0, false) }, element: parameter.type)
            }
        }
        let values = try helper.completeTextArguments(op, supplied: supplied, source: source, id: id)
        let bridge = try textOperationBridge(op, id: id)
        let bridgeArguments = try zip([source] + values, bridge.parameters).map { try helper.convert($0.0, to: $0.1) }
        let returned = try helper.value(bridge.result)
        helper.instructions.append(.call(bridge, bridgeArguments, returned))
        helper.instructions.append(.returnValue(resultType == .unit ? nil : try helper.convert(returned, to: resultType)))
        program.syntheticFunctions[container, default: []].append(helper.finish())
        let unitConversion = resultType == .unit && bridge.result != .unit
        let adapted = binding?.isCallableReferenceAdapter == true || binding?.hidesKCallable == true || unitConversion || function.isSuspend
            || op.parameters.count != signatureTypes.count
        var generated = try program.closureClass(className, captures: captures.enumerated().map { ("capture\($0.offset)", $0.element.type) }, inputs: inputTypes, result: resultType, helper: helperRef, suspend: function.isSuspend, superclass: "kotlin/jvm/internal/" + (adapted ? "AdaptedFunctionReference" : "FunctionReferenceImpl"))
        program.functionArities.insert(arity)
        var flags: Int32 = 1
        if varargConversion { flags |= 2 }
        if function.isSuspend { flags |= 4 }
        if unitConversion { flags |= 8 }
        // The row's own target (e.g. String.codePointAt, or the inline-emitted uppercase) has no
        // static StringsKt method, so a reflective `call` resolved from owner/signature would fail.
        try initializeReferenceSuperclass(&generated, arity: arity, bound: bound, sourceOwner: bridge.owner!, sourceName: bridge.name, sourceDescriptor: bridge.descriptor, flags: flags, displayName: name)
        program.closureClasses.append(generated)
        return try constructJDK(className, parameters: captures.map(\.type), arguments: captures)
    }

    func textOperationBridge(_ op: JVMTextOperation, id: ExprID) throws -> JVMFunctionReference {
        let parameters = [op.receiverType] + op.parameters.map { $0.variadic ? JVMValueType.reference("[" + $0.type.descriptor, nullable: false) : $0.type }
        let result: JVMValueType = op.sourceResult == "String" ? .string : op.result
        let shape = "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor
        let container = program.facadeName
        let reference = JVMFunctionReference(name: op.name + "$textBridge$" + JVMNameHash.suffix(op.owner + "." + (op.method ?? op.name) + shape), parameters: parameters, result: result, owner: container)
        if program.syntheticFunctions[container]?.contains(where: { $0.reference.name == reference.name }) == true { return reference }
        let bridge = JVMFunctionBuilder(program: program, declaration: FunDecl(range: arena.exprRange(id)!, name: context.interner.intern(reference.name), modifiers: [], body: .unit), reference: reference, owner: nil)
        bridge.isStaticBody = true
        let inputs = try parameters.map { try bridge.value($0) }
        let returned = try bridge.emitTextOperation(op, source: inputs[0], values: Array(inputs.dropFirst()))
        bridge.instructions.append(.returnValue(try bridge.convert(returned, to: result)))
        program.syntheticFunctions[container, default: []].append(bridge.finish())
        return reference
    }
}
