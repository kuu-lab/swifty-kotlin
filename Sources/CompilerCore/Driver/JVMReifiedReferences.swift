import Foundation

extension JVMFunctionBuilder {
    /// Invocation uses a specialized body; reflection still describes the source
    /// declaration, exactly as FunctionReferenceImpl does for Kotlin references.
    func reifiedReference(_ id: ExprID, symbol: SymbolID, receiver: ExprID?, unbound: Bool) throws -> JVMValue {
        guard let declaration = program.inlineDeclarations[symbol], let signature = program.sema.symbols.functionSignature(for: symbol),
              let binding = program.sema.bindings.callableReferenceBinding(for: id), let function = functionType(id),
              function.contextReceivers.isEmpty, binding.boundContextParameterTypes.isEmpty else { throw fail("Missing JVM reified reference specialization.", id) }
        let method = program.methods[symbol], ref = program.references[symbol]
        guard method != nil || ref != nil else { throw fail("Missing JVM reified reference declaration.", id) }
        let member = method?.isStatic == false, extensionMember = declaration.receiverType != nil
        let bound = unbound || (!member && !extensionMember) ? nil : try receiver.map(requireValue) ?? instance(id)
        let dispatch = member && extensionMember ? try instance(id) : nil
        let inputTypes = try ([function.receiver].compactMap { $0 } + function.params).map(program.type)
        let resultType = try program.type(function.returnType)
        let saved = program.inlineTypeArguments
        defer { program.inlineTypeArguments = saved }
        let arguments = binding.substitutedTypeArguments.map { program.specialized($0) }
        let symbols = signature.typeParameterSymbols.count == arguments.count ? signature.typeParameterSymbols : Array(signature.typeParameterSymbols.suffix(arguments.count))
        for (parameter, argument) in zip(symbols, arguments) {
            if program.sema.symbols.symbol(parameter)?.flags.contains(.reifiedTypeParameter) == true, !program.validReifiedArgument(argument) { throw fail("A non-reified type parameter cannot specialize a reified reference.", id) }
            program.inlineTypeArguments[parameter] = argument
        }
        let number = program.nextClosure; program.nextClosure += 1
        let container = owner?.name ?? program.facadeName, name = container + "$Reference" + String(number)
        var captures: [(String, JVMValue)] = []
        if let bound { captures.append(("bound", bound)) }
        let dispatchIndex = dispatch == nil ? nil : captures.count
        if let dispatch { captures.append(("dispatch", dispatch)) }
        let tokenIndex = captures.count
        let targetOwner = program.sema.symbols.parentSymbol(for: symbol).flatMap { program.classes[$0] }
        let ownedTokens = Set(targetOwner?.captures.compactMap(\.reifiedClass) ?? [])
        var tokenTypes: [TypeID]
        switch declaration.body {
        case let .expr(body, _): tokenTypes = reifiedCaptureTypes(body)
        case let .block(body, _): tokenTypes = Array(Set(body.flatMap { reifiedCaptureTypes($0) })).sorted { $0.rawValue < $1.rawValue }
        case .unit: throw fail("Reified reference requires a body.", id)
        }
        tokenTypes = Array(Set(tokenTypes + declaration.valueParams.compactMap(\.defaultValue).flatMap { reifiedCaptureTypes($0) })).sorted { $0.rawValue < $1.rawValue }
        tokenTypes.removeAll { type in
            if case let .typeParam(t) = program.sema.types.kind(of: program.specialized(type)) { return ownedTokens.contains(t.symbol) }; return false
        }
        for (i, type) in tokenTypes.enumerated() {
            let token = try materializeReifiedToken(type)
            captures.append(("type\(i)", token.klass)); captures.append(("nullable\(i)", token.nullable))
            captures.append(("mutableKind\(i)", token.mutableKind))
        }
        let helperRef = JVMFunctionReference(name: "$lambdaReified" + String(number), parameters: captures.map { $0.1.type } + inputTypes, result: resultType, owner: container, ownerIsInterface: owner?.isInterface == true)
        guard helperRef.parameters.reduce(0, { $0 + $1.width }) + (function.isSuspend ? 1 : 0) <= 255,
              captures.reduce(1, { $0 + $1.1.type.width }) <= 255 else { throw fail("JVM reified reference parameter slot limit exceeded.", id) }
        let helper = JVMFunctionBuilder(program: program, declaration: FunDecl(range: declaration.range, name: context.interner.intern(helperRef.name), modifiers: [], body: .unit), reference: helperRef, owner: owner)
        helper.isStaticBody = true; helper.isSuspendBody = function.isSuspend; helper.functionSymbol = symbol
        helper.inlineStack = inlineStack.union([symbol])
        let inputs = try helperRef.parameters.map { try helper.value($0) }
        for (i, type) in tokenTypes.enumerated() {
            if case let .typeParam(t) = program.sema.types.kind(of: type) {
                let offset = tokenIndex + i * ReifiedRuntimeToken.captureWidth
                helper.reifiedRuntimeTokens[t.symbol] = ReifiedRuntimeToken(klass: inputs[offset], nullable: inputs[offset + 1], mutableKind: inputs[offset + 2])
            }
        }
        var values = Array(inputs.dropFirst(captures.count))
        if member && !extensionMember {
            helper.thisValue = bound == nil ? values.removeFirst() : inputs[0]
        } else if extensionMember {
            helper.extensionValue = bound == nil ? values.removeFirst() : inputs[0]
            if let dispatchIndex { helper.thisValue = inputs[dispatchIndex] }
        }
        if let targetOwner, helper.thisValue != nil {
            let explicitExtension = helper.extensionValue
            try helper.prepareEnclosingInstances(targetOwner)
            if let explicitExtension { helper.extensionValue = explicitExtension }
        }
        if let own = helper.thisValue, let parent = program.sema.symbols.parentSymbol(for: symbol) {
            helper.contextualReceivers[parent] = own
            helper.contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: parent)] = own
        }
        if let own = helper.extensionValue ?? helper.thisValue { helper.contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)] = own }
        var supplied: [Int: JVMValue] = [:]
        for (i, input) in values.enumerated() { supplied[binding.parameterMapping[i] ?? i] = input }
        for (i, parameter) in declaration.valueParams.enumerated() {
            let input: JVMValue
            if let value = supplied[i] { input = try helper.convert(value, to: program.type(signature.parameterTypes[i])) }
            else if let expression = parameter.defaultValue { input = try helper.requireValue(expression) }
            else { throw fail("Missing reified reference argument.", id) }
            var local = Local(value: input, mutable: false, symbol: signature.valueParameterSymbols.indices.contains(i) ? signature.valueParameterSymbols[i] : nil)
            if case let .functionType(f) = program.sema.types.kind(of: program.specialized(signature.parameterTypes[i])) { local.functionType = f }
            helper.scopes[0][parameter.name] = local
        }
        helper.scopes.append([:])
        let result = resultType == .unit ? nil : try helper.value(resultType), end = helper.label()
        helper.inlineReturns = [InlineReturn(lambda: nil, result: result, end: end, finalizerDepth: 0)]
        switch declaration.body {
        case let .expr(body, _):
            let returned = try helper.expression(body, discarded: result == nil)
            if !helper.terminated, let result, let returned { helper.instructions.append(.copy(try helper.convert(returned, to: result.type), result)) }
        case let .block(body, _): for expr in body where !helper.terminated { _ = try helper.expression(expr, discarded: true) }
        case .unit: break
        }
        helper.mark(end); helper.instructions.append(.returnValue(result))
        program.syntheticFunctions[container, default: []].append(helper.finish())
        let suspendConversion = !declaration.isSuspend && function.isSuspend
        let sourceResult = try program.type(signature.returnType)
        let unitConversion = resultType == .unit && sourceResult != .unit
        let adapted = binding.isCallableReferenceAdapter || suspendConversion || unitConversion
        let superclass = "kotlin/jvm/internal/" + (adapted ? "AdaptedFunctionReference" : "FunctionReferenceImpl")
        var generated = try program.closureClass(name, captures: captures.map { ($0.0, $0.1.type) }, inputs: inputTypes, result: resultType, helper: helperRef, suspend: function.isSuspend, superclass: superclass)
        let arity = inputTypes.count + (function.isSuspend ? 1 : 0)
        program.functionArities.insert(arity)
        let sourceOwner = ref?.owner ?? method!.owner, sourceName = ref?.name ?? method!.name, sourceDescriptor = ref?.descriptor ?? method!.descriptor
        var ctor = generated.functions[0]
        var slot = ctor.locals.map { $0.slot + $0.type.width }.max() ?? 1
        func temporary(_ type: JVMValueType) -> JVMValue { let v = JVMValue(slot: slot, type: type); slot += type.width; ctor.locals.append(v); return v }
        let count = temporary(.int), klass = temporary(.reference("java/lang/Class", nullable: false)), methodName = temporary(.string), descriptor = temporary(.string), flags = temporary(.int)
        var adaptationFlags: Int32 = member ? 0 : 1
        if suspendConversion { adaptationFlags |= 4 }
        if unitConversion { adaptationFlags |= 8 }
        var code: [JVMInstruction] = [.constant(.int(Int32(arity)), count), .classLiteral(sourceOwner, klass), .constant(.string(sourceName.components(separatedBy: "$unsigned$")[0]), methodName), .callableSignature(sourceOwner, sourceName, sourceDescriptor, descriptor), .constant(.int(adaptationFlags), flags)]
        var superArgs = [count]
        if bound != nil { let object = temporary(.reference("java/lang/Object", nullable: true)); code.append(.copy(ctor.locals[1], object)); superArgs.append(object) }
        superArgs += [klass, methodName, descriptor, flags]
        let superMethod = JVMForeignMethod(owner: generated.superclass, name: "<init>", descriptor: "(" + superArgs.map { $0.type.descriptor }.joined() + ")V", parameters: superArgs.map(\.type), result: .reference(generated.superclass, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        code.append(.foreignCall(superMethod, receiver: ctor.locals[0], arguments: superArgs, result: nil))
        ctor.instructions = code + ctor.instructions.dropFirst()
        generated.functions[0] = ctor; program.closureClasses.append(generated)
        return try constructJDK(name, parameters: captures.map { $0.1.type }, arguments: captures.map(\.1))
    }
}
