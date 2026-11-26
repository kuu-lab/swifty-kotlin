import Foundation

extension JVMFunctionBuilder {
    /// Lowers a callable reference to a JVM text stub (`"abc"::endsWith`,
    /// `String::uppercase`). The stubs have no JVM method of their own; calls
    /// go through `JVMTextOperation.operations`, so the reference gets a helper
    /// that runs the same table emission as a direct call, with omitted
    /// defaults filled from the table's fallbacks (KUU-4733).
    func textOperationReference(_ id: ExprID, symbol: SymbolID, receiver: ExprID?, unbound: Bool) throws -> JVMValue? {
        // Stubs that already map to a real JVM method keep the regular reference lowering.
        guard program.methods[symbol] == nil, program.references[symbol] == nil, program.textLibraryMethods[symbol] == nil,
              context.jvmImports?.method(for: symbol) == nil,
              let name = textStubName(symbol),
              let signature = program.sema.symbols.functionSignature(for: symbol),
              let semanticReceiver = signature.receiverType else { return nil }
        let receiverType = try program.type(semanticReceiver)
        let candidates = textOperationCandidates(name, receiver: receiverType)
        guard !candidates.isEmpty else { return nil }
        let signatureTypes = try signature.parameterTypes.map(program.type)
        guard let op = exactTextOperation(candidates, parameterTypes: signatureTypes) else {
            throw fail("Unsupported JVM text reference overload: " + name + " (" + signatureTypes.map(\.descriptor).joined() + ").", id)
        }
        // Exact-signature references may carry no binding; that means identity mapping and no adaptation.
        let binding = program.sema.bindings.callableReferenceBinding(for: id)
        guard let function = functionType(id), function.contextReceivers.isEmpty,
              binding?.boundContextParameterTypes.isEmpty != false, !function.isSuspend else {
            throw fail("Unsupported JVM text reference adaptation.", id)
        }
        let bound = unbound ? nil : try receiver.map(requireValue) ?? instance(id)
        let captures = [bound].compactMap { $0 }
        let inputTypes = try ([function.receiver].compactMap { $0 } + function.params).map(program.type)
        let resultType = try program.type(function.returnType)
        let arity = inputTypes.count
        guard arity <= 22 else { throw fail("JVM callable reference arity exceeds 22.", id) }
        let number = program.nextClosure; program.nextClosure += 1
        let container = owner?.name ?? program.facadeName, className = container + "$Reference" + String(number)
        let helperRef = JVMFunctionReference(name: "$lambdaText" + String(number), parameters: captures.map(\.type) + inputTypes, result: resultType, owner: container, ownerIsInterface: owner?.isInterface == true)
        let helper = JVMFunctionBuilder(program: program, declaration: FunDecl(range: arena.exprRange(id)!, name: context.interner.intern(helperRef.name), modifiers: [], body: .unit), reference: helperRef, owner: owner)
        helper.isStaticBody = true
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
        let returned = try helper.emitTextOperation(op, source: source, values: values)
        helper.instructions.append(.returnValue(resultType == .unit ? nil : try helper.convert(returned, to: resultType)))
        program.syntheticFunctions[container, default: []].append(helper.finish())
        let unitConversion = resultType == .unit && op.result != .unit
        let adapted = binding?.isCallableReferenceAdapter == true || binding?.hidesKCallable == true || unitConversion
        var generated = try program.closureClass(className, captures: captures.enumerated().map { ("capture\($0.offset)", $0.element.type) }, inputs: inputTypes, result: resultType, helper: helperRef, superclass: "kotlin/jvm/internal/" + (adapted ? "AdaptedFunctionReference" : "FunctionReferenceImpl"))
        program.functionArities.insert(arity)
        var flags: Int32 = 1
        if varargConversion { flags |= 2 }
        if unitConversion { flags |= 8 }
        let declared = [op.receiverType] + op.parameters.map { $0.variadic ? JVMValueType.reference("[" + $0.type.descriptor, nullable: false) : $0.type }
        let descriptor = "(" + declared.map(\.descriptor).joined() + ")" + op.result.descriptor
        try initializeReferenceSuperclass(&generated, arity: arity, bound: bound, sourceOwner: "kotlin/text/StringsKt", sourceName: name, sourceDescriptor: descriptor, flags: flags)
        program.closureClasses.append(generated)
        return try constructJDK(className, parameters: captures.map(\.type), arguments: captures)
    }
}
