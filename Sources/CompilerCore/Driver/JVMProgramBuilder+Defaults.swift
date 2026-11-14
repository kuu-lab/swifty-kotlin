import Foundation

extension JVMProgramBuilder {
    func defaultOwner(_ symbol: SymbolID) -> SymbolID {
        var current = symbol, seen: Set<SymbolID> = []
        while seen.insert(current).inserted {
            if let forwarded = sema.symbols.classDelegationForwardingMethodInfo(for: current) { current = forwarded.interfaceMethodSymbol; continue }
            if sourceParameters[current]?.contains(where: \.hasDefaultValue) == true { return current }
            guard let parent = sema.symbols.overrideDefaultsBaseSymbol(for: current) else { return current }
            current = parent
        }
        return current
    }

    func defaultReference(_ symbol: SymbolID) throws -> JVMFunctionReference {
        let method = methods[symbol], ref = references[symbol]
        guard let params = sourceParameters[symbol], ref != nil || method != nil else { throw JVMFrontendError(message: "Missing JVM default declaration.") }
        let masks = (params.count + 31) / 32
        let parameters = (method.map { [JVMValueType.reference($0.owner, nullable: false)] } ?? []) + (ref?.parameters ?? method!.parameters) + Array(repeating: JVMValueType.int, count: masks) + [.reference("java/lang/Object", nullable: true)]
        guard parameters.reduce(0, { $0 + $1.width }) + ((ref?.isSuspend ?? method?.isSuspend ?? false) ? 1 : 0) <= 255 else { throw JVMFrontendError(message: "JVM default method parameter slot limit exceeded.") }
        var result = JVMFunctionReference(name: (ref?.name ?? method!.name) + "$default", parameters: parameters, result: ref?.result ?? method!.result, owner: ref?.owner ?? method!.owner, ownerIsInterface: ref?.ownerIsInterface == true || method?.isInterface == true, isSuspend: ref?.isSuspend ?? method?.isSuspend ?? false)
        result.suspendDefaultMasks = result.isSuspend ? masks : 0
        return result
    }

    func applyDefaults(_ b: JVMFunctionBuilder, parameters: [ValueParamDecl], inputs: [JVMValue], masks: [JVMValue], inline: Bool = false) throws {
        for (i, parameter) in parameters.enumerated() {
            if let expression = parameter.defaultValue {
                let skip = b.label()
                b.instructions.append(.defaultArgument(masks[i / 32], Int32(bitPattern: UInt32(1) << UInt32(i % 32)), skip))
                if inline, !parameter.isCrossinline, !parameter.isNoinline, case .lambdaLiteral = ast.arena.expr(expression) {
                    _ = try b.closure(expression, destination: inputs[i])
                } else {
                    let source = try b.expression(expression)
                    if !b.terminated {
                        guard let source else { throw JVMFrontendError(message: "Default argument requires a value.") }
                        b.instructions.append(.copy(try b.convert(source, to: inputs[i].type), inputs[i]))
                    }
                }
                b.mark(skip)
            }
            var local = JVMFunctionBuilder.Local(value: inputs[i], mutable: false)
            if let symbol = b.functionSymbol, let signature = sema.symbols.functionSignature(for: symbol) {
                if signature.valueParameterSymbols.indices.contains(i) { local.symbol = signature.valueParameterSymbols[i] }
                if signature.parameterTypes.indices.contains(i), case let .functionType(f) = sema.types.kind(of: signature.parameterTypes[i]) { local.functionType = f }
            }
            b.scopes[0][parameter.name] = local
        }
    }

    func defaultFunction(symbol: SymbolID, declaration: FunDecl, plan: JVMClassPlan?) throws -> JVMFunction {
        let ref = try defaultReference(symbol)
        let continuation: JVMValueType = .reference("kotlin/coroutines/Continuation", nullable: false)
        let physical = ref.isSuspend ? ref.suspendABI : ref
        let fake = FunDecl(range: declaration.range, name: context.interner.intern(ref.name), modifiers: [], valueParams: [], body: .unit, isInline: declaration.isInline)
        let b = JVMFunctionBuilder(program: self, declaration: fake, reference: physical, owner: plan)
        b.isStaticBody = true; b.functionSymbol = symbol
        let values = try physical.parameters.map { try b.value($0) }
        var index = 0
        if plan != nil { b.thisValue = values[index]; index += 1; try b.prepareEnclosingInstances() }
        if declaration.receiverType != nil { b.extensionValue = values[index]; index += 1 }
        if let receiver = b.extensionValue ?? b.thisValue { b.contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)] = receiver }
        let inputs = Array(values[index..<(index + declaration.valueParams.count)])
        let maskIndex = index + inputs.count + (ref.isSuspend ? 1 : 0)
        try applyDefaults(b, parameters: declaration.valueParams, inputs: inputs, masks: Array(values[maskIndex..<(values.count - 1)]), inline: declaration.isInline)
        var args = (b.extensionValue.map { [$0] } ?? []) + inputs
        if ref.isSuspend { args.append(values[index + inputs.count]); assert(args.last!.type == continuation) }
        if declaration.isInline {
            b.scopes.append([:])
            switch declaration.body {
            case let .expr(body, _):
                let result = try b.expression(body, discarded: physical.result == .unit)
                if !b.terminated { b.instructions.append(.returnValue(try result.map { try b.convert($0, to: physical.result) })) }
            case let .block(body, _):
                for expression in body where !b.terminated { _ = try b.expression(expression, discarded: true) }
                if !b.terminated { b.instructions.append(.returnValue(nil)) }
            case .unit: throw JVMFrontendError(message: "Inline default function needs a body.")
            }
        } else {
            let result = physical.result == .unit ? nil : try b.value(physical.result)
            if let method = methods[symbol] { b.instructions.append(.foreignCall(ref.isSuspend ? method.suspendABI : method, receiver: b.thisValue, arguments: args, result: result)) }
            else { b.instructions.append(.call(ref.isSuspend ? references[symbol]!.suspendABI : references[symbol]!, args, result)) }
            b.instructions.append(.returnValue(result))
        }
        var f = b.finish(); f.access = 0x1009; f.isInline = declaration.isInline; f.checksParameters = false
        if declaration.isInline && ref.isSuspend { f.inlineContinuation = values[index + inputs.count] }
        return f
    }

    func defaultConstructorMethods(_ plan: JVMClassPlan, symbol: SymbolID, declaration: ConstructorDecl, original: JVMFunction, primary: Bool) throws -> [JVMFunction] {
        let marker: JVMValueType = .reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)
        let masks = (declaration.valueParams.count + 31) / 32
        let params = original.reference.parameters + Array(repeating: JVMValueType.int, count: masks) + [marker]
        guard params.reduce(1, { $0 + $1.width }) <= 255 else { throw JVMFrontendError(message: "JVM default constructor parameter slot limit exceeded.") }
        let b = try nominalBuilder(plan, name: "<init>", parameters: params)
        b.functionSymbol = symbol; b.beforeDelegation = true
        let values = Array(b.locals.dropFirst()), hidden = original.kotlinParameterOffset
        b.scopes = [[:]]
        if plan.isInner, let outer = plan.outer { try b.bindEnclosingInstance(classes[outer]!, value: values[0]) }
        if !plan.captures.isEmpty { try b.bindCaptureValues(plan.captures, values: Array(values.prefix(plan.captures.count))) }
        let inputs = Array(values.dropFirst(hidden).prefix(declaration.valueParams.count))
        try applyDefaults(b, parameters: declaration.valueParams, inputs: inputs, masks: Array(values.dropFirst(original.reference.parameters.count).prefix(masks)))
        let target = JVMForeignMethod(owner: plan.name, name: "<init>", descriptor: original.reference.descriptor, parameters: original.reference.parameters, result: b.thisValue!.type, isStatic: false, isInterface: false, isAbstract: false)
        b.instructions += [.foreignCall(target, receiver: b.thisValue, arguments: Array(values.prefix(original.reference.parameters.count)), result: nil), .returnValue(nil)]
        var f = b.finish(constructor: true); f.access = access(declaration.modifiers) | 0x1000; f.checksParameters = false
        var results = [f]
        // A primary constructor with all defaults also has a no-arg JVM
        // entry point. Explicit overloads reuse the same mask constructor.
        let hasJvmOverloads = declaration.annotations.contains {
            ["JvmOverloads", "kotlin.jvm.JvmOverloads"].contains($0.name)
        }
        let defaulted = declaration.valueParams.indices.reversed().filter {
            declaration.valueParams[$0].hasDefaultValue
        }
        let automaticNoArg = primary && !plan.isValue && !plan.isInner && !plan.isEnum
            && !declaration.valueParams.isEmpty && defaulted.count == declaration.valueParams.count
            && !plan.constructors.contains(where: { !$0.2 && $0.1.valueParams.isEmpty })
        let counts = hasJvmOverloads ? Array(1...defaulted.count) : (automaticNoArg ? [defaulted.count] : [])
        for count in counts {
            let omitted = Set(defaulted.prefix(count))
            let included = original.reference.parameters.indices.filter { $0 < hidden || !omitted.contains($0 - hidden) }
            let overloadParameters = included.map { original.reference.parameters[$0] }
            let overload = try nominalBuilder(plan, name: "<init>", parameters: overloadParameters)
            let inputs = Dictionary(uniqueKeysWithValues: zip(included, overload.locals.dropFirst()))
            var arguments: [JVMValue] = []
            for (i, parameter) in original.reference.parameters.enumerated() {
                if let input = inputs[i] { arguments.append(input) }
                else { arguments.append(try overload.zero(parameter)) }
            }
            var bits = Array(repeating: UInt32(0), count: masks)
            for index in omitted { bits[index / 32] |= UInt32(1) << UInt32(index % 32) }
            arguments += try overload.maskArguments(bits, constructor: true)
            let target = JVMForeignMethod(owner: plan.name, name: "<init>", descriptor: f.reference.descriptor,
                                          parameters: params, result: overload.thisValue!.type,
                                          isStatic: false, isInterface: false, isAbstract: false)
            overload.instructions += [
                .foreignCall(target, receiver: overload.thisValue, arguments: arguments, result: nil),
                .returnValue(nil)
            ]
            var result = overload.finish(constructor: true)
            result.access = access(declaration.modifiers)
            result.isSynthetic = !hasJvmOverloads
            if hasJvmOverloads {
                result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/jvm/JvmOverloads;", visible: false))
            }
            results.append(result)
        }
        return results
    }
}
