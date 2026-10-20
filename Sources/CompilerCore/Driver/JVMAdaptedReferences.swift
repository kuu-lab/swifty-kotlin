import Foundation

extension JVMFunctionBuilder {
    /// Adapt the selected function shape without changing the target's public ABI.
    func adaptedReference(_ id: ExprID, symbol: SymbolID, receiver: ExprID?, unbound: Bool) throws -> JVMValue {
        guard let binding = program.sema.bindings.callableReferenceBinding(for: id), let function = functionType(id),
              let signature = program.sema.symbols.functionSignature(for: symbol),
              function.contextReceivers.isEmpty, binding.boundContextParameterTypes.isEmpty else {
            throw fail("Missing JVM callable reference adaptation.", id)
        }
        let method = program.methods[symbol] ?? context.jvmImports?.methods[symbol], ref = program.references[symbol]
        guard method != nil || ref != nil else { throw fail("Missing JVM adapted reference target.", id) }
        let constructor = method?.isConstructor == true, extensionMember = program.extensionSymbols.contains(symbol)
        let member = method?.isStatic == false && !constructor
        let plan = method.flatMap { m in program.classes.values.first { $0.name == m.owner } }
        let innerConstructor = constructor && plan?.isInner == true
        let bound = unbound || (!member && !extensionMember && !innerConstructor) ? nil : try receiver.map(requireValue) ?? instance(id)
        let dispatch = member && extensionMember ? try instance(id) : nil
        let captures = [bound, dispatch].compactMap { $0 }
        let inputTypes = try ([function.receiver].compactMap { $0 } + function.params).map(program.type)
        let resultType = try program.type(function.returnType)
        let number = program.nextClosure; program.nextClosure += 1
        let container = owner?.name ?? program.facadeName, name = container + "$Reference" + String(number)
        let helperRef = JVMFunctionReference(name: "$lambdaAdapter" + String(number), parameters: captures.map(\.type) + inputTypes, result: resultType, owner: container, ownerIsInterface: owner?.isInterface == true)
        let helper = JVMFunctionBuilder(program: program, declaration: FunDecl(range: arena.exprRange(id)!, name: context.interner.intern(helperRef.name), modifiers: [], body: .unit), reference: helperRef, owner: owner)
        helper.isStaticBody = true; helper.isSuspendBody = function.isSuspend
        let inputs = try helperRef.parameters.map { try helper.value($0) }
        var arguments = Array(inputs.dropFirst(captures.count))
        var targetReceiver: JVMValue?, prefix: [JVMValue] = []
        if member && !extensionMember { targetReceiver = bound == nil ? arguments.removeFirst() : inputs[0] }
        if extensionMember || innerConstructor { prefix = [bound == nil ? arguments.removeFirst() : inputs[0]] }
        if dispatch != nil { targetReceiver = inputs[bound == nil ? 0 : 1] }
        let allTypes = ref?.parameters ?? method!.parameters
        let parameterTypes = Array(allTypes.dropFirst(prefix.count))
        let defaultSymbol = program.defaultOwner(binding.defaultArgumentOwner ?? symbol)
        let declarations = program.sourceParameters[defaultSymbol] ?? program.sourceParameters[symbol]
        let saved = program.inlineTypeArguments
        defer { program.inlineTypeArguments = saved }
        let typeArguments = binding.substitutedTypeArguments.map { program.specialized($0) }
        let typeParameters = signature.typeParameterSymbols.count == typeArguments.count ? signature.typeParameterSymbols : Array(signature.typeParameterSymbols.suffix(typeArguments.count))
        for (parameter, argument) in zip(typeParameters, typeArguments) { program.inlineTypeArguments[parameter] = argument }
        var supplied: [Int: [JVMValue]] = [:]
        for (index, argument) in arguments.enumerated() { supplied[binding.parameterMapping[index] ?? index, default: []].append(argument) }
        var values = try zip(prefix, allTypes).map { try helper.convert($0.0, to: $0.1) }
        var masks = Array(repeating: UInt32(0), count: (parameterTypes.count + 31) / 32)
        var hasVarargConversion = false
        for (index, type) in parameterTypes.enumerated() {
            let provided = supplied[index] ?? []
            if provided.isEmpty, declarations?.indices.contains(index) == true, declarations![index].hasDefaultValue {
                masks[index / 32] |= UInt32(1) << UInt32(index % 32); values.append(try helper.zero(type))
            } else if signature.valueParameterIsVararg.indices.contains(index), signature.valueParameterIsVararg[index] {
                // Generic varargs need the specialized component class, even
                // though the target method accepts an erased Object array.
                let physicalElement = try helper.arrayComponent(type)
                let logicalElement = try program.type(signature.parameterTypes[index])
                let element = physicalElement.referenceName != nil ? JVMClasspathIndex.boxed(logicalElement) : physicalElement
                let arrayType = JVMValueType.reference("[" + element.descriptor, nullable: false)
                if provided.count == 1, provided[0].type.descriptor == arrayType.descriptor {
                    values.append(try helper.convert(provided[0], to: type))
                } else {
                    hasVarargConversion = true
                    let array = try helper.value(arrayType), count = try helper.constant(.int(Int32(provided.count)), .int)
                    helper.instructions.append(.newArray(element, count: count, result: array))
                    for (offset, argument) in provided.enumerated() {
                        let slot = try helper.constant(.int(Int32(offset)), .int)
                        helper.instructions.append(.arraySet(array, slot, try helper.convert(argument, to: element)))
                    }
                    values.append(try helper.convert(array, to: type))
                }
            } else if provided.count == 1 { values.append(try helper.convert(provided[0], to: type)) }
            else { throw fail("Invalid JVM adapted reference argument mapping.", id) }
        }
        let physicalResult = ref?.result ?? method!.result
        let returned = constructor ? try helper.value(method!.result) : (physicalResult == .unit ? nil : try helper.value(physicalResult))
        if constructor, let returned { helper.instructions.append(.allocate(method!.owner, returned)) }
        if masks.contains(where: { $0 != 0 }) {
            if constructor {
                values += try helper.maskArguments(masks, constructor: true)
                let types = allTypes + Array(repeating: JVMValueType.int, count: masks.count) + [.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)]
                let target = JVMForeignMethod(owner: method!.owner, name: "<init>", descriptor: "(" + types.map(\.descriptor).joined() + ")V", parameters: types, result: method!.result, isStatic: false, isInterface: false, isAbstract: false)
                helper.instructions.append(.foreignCall(target, receiver: returned, arguments: values, result: nil))
            } else {
                let target = try program.defaultReference(defaultSymbol)
                var defaultArguments = (targetReceiver.map { [$0] } ?? []) + values + (try helper.maskArguments(masks, constructor: false))
                // Inherited defaults can erase a concrete primitive parameter to Object.
                guard defaultArguments.count == target.parameters.count else { throw fail("Invalid JVM adapted default argument count.", id) }
                defaultArguments = try zip(defaultArguments, target.parameters).map { try helper.convert($0.0, to: $0.1) }
                helper.instructions.append(.call(target, defaultArguments, returned))
            }
        } else if let method { helper.instructions.append(.foreignCall(method, receiver: returned.flatMap { constructor ? $0 : nil } ?? targetReceiver, arguments: values, result: constructor ? nil : returned)) }
        else { helper.instructions.append(.call(ref!, values, returned)) }
        helper.instructions.append(.returnValue(resultType == .unit ? nil : try returned.map { try helper.convert($0, to: resultType) }))
        program.syntheticFunctions[container, default: []].append(helper.finish())
        var generated = try program.closureClass(name, captures: captures.enumerated().map { ("capture\($0.offset)", $0.element.type) }, inputs: inputTypes, result: resultType, helper: helperRef, suspend: function.isSuspend, superclass: "kotlin/jvm/internal/AdaptedFunctionReference")
        let arity = inputTypes.count + (function.isSuspend ? 1 : 0)
        guard arity <= 22 else { throw fail("JVM adapted reference arity exceeds 22.", id) }
        program.functionArities.insert(arity)
        var flags: Int32 = member || constructor ? 0 : 1
        if hasVarargConversion { flags |= 2 }
        if !signature.isSuspend && function.isSuspend { flags |= 4 }
        if resultType == .unit && physicalResult != .unit { flags |= 8 }
        try initializeReferenceSuperclass(&generated, arity: arity, bound: bound, sourceOwner: ref?.owner ?? method!.owner, sourceName: constructor ? "<init>" : ref?.name ?? method!.name, sourceDescriptor: ref?.descriptor ?? method!.descriptor, flags: flags)
        program.closureClasses.append(generated)
        return try constructJDK(name, parameters: captures.map(\.type), arguments: captures)
    }

    func initializeReferenceSuperclass(_ generated: inout JVMClass, arity: Int, bound: JVMValue?, sourceOwner: String, sourceName: String, sourceDescriptor: String, flags: Int32) throws {
        var ctor = generated.functions[0]
        var slot = ctor.locals.map { $0.slot + $0.type.width }.max() ?? 1
        func temporary(_ type: JVMValueType) -> JVMValue { let v = JVMValue(slot: slot, type: type); slot += type.width; ctor.locals.append(v); return v }
        let count = temporary(.int), klass = temporary(.reference("java/lang/Class", nullable: false)), methodName = temporary(.string), descriptor = temporary(.string), flag = temporary(.int)
        var code: [JVMInstruction] = [.constant(.int(Int32(arity)), count), .classLiteral(sourceOwner, klass), .constant(.string(sourceName.components(separatedBy: "$unsigned$")[0]), methodName), .callableSignature(sourceOwner, sourceName, sourceDescriptor, descriptor), .constant(.int(flags), flag)]
        var args = [count]
        if bound != nil { let object = temporary(.reference("java/lang/Object", nullable: true)); code.append(.copy(ctor.locals[1], object)); args.append(object) }
        args += [klass, methodName, descriptor, flag]
        let target = JVMForeignMethod(owner: generated.superclass, name: "<init>", descriptor: "(" + args.map { $0.type.descriptor }.joined() + ")V", parameters: args.map(\.type), result: .reference(generated.superclass, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        code.append(.foreignCall(target, receiver: ctor.locals[0], arguments: args, result: nil))
        ctor.instructions = code + ctor.instructions.dropFirst(); generated.functions[0] = ctor
    }
}
