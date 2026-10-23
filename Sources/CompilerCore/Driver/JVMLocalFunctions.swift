import Foundation

struct JVMLocalFunctionPlan {
    let reference: JVMFunctionReference
    let captures: [JVMAnonymousCapture]
}

extension JVMFunctionBuilder {
    func localCaptureEnvironment() -> [InternedString: Local] {
        var visible: [InternedString: Local] = [:]
        for scope in scopes {
            for (name, local) in scope {
                if let outer = visible[name], let symbol = outer.symbol, symbol != local.symbol {
                    // Keep shadowed bindings addressable by semantic identity for
                    // environments required by an indirectly called local function.
                    let hidden = context.interner.intern("\0jvmCapturedLocal:" + String(symbol.rawValue))
                    visible[hidden] = outer
                }
                visible[name] = local
            }
        }
        return visible
    }

    func localReferenceCaptureSymbols(in body: ExprID) -> Set<SymbolID> {
        guard let range = arena.exprRange(body) else { return [] }
        var captured: Set<SymbolID> = []
        for i in arena.exprs.indices {
            let expression = ExprID(rawValue: Int32(i))
            guard let site = arena.exprRange(expression), site.start.file == range.start.file,
                  site.start.offset >= range.start.offset, site.end.offset <= range.end.offset,
                  let symbol = program.sema.bindings.callableReferenceBinding(for: expression)?.chosenCallee ?? program.sema.bindings.callBinding(for: expression)?.chosenCallee ?? program.sema.bindings.identifierSymbol(for: expression),
                  program.sema.symbols.symbol(symbol)?.flags.contains(.localFunction) == true else { continue }
            captured.formUnion(program.sema.bindings.localFunctionCaptureSymbols(for: symbol))
            captured.formUnion(program.localFunctions[symbol]?.captures.compactMap { $0.local?.symbol } ?? [])
        }
        return captured
    }

    func localFunctionCaptureValues(_ captures: [JVMAnonymousCapture]) throws -> [JVMValue] {
        try captures.map { capture in
            if let name = capture.name, let template = capture.local {
                let local: Local?
                if let symbol = template.symbol {
                    local = scopes.reversed().lazy.compactMap { scope in scope.values.first { $0.symbol == symbol } }.first
                } else { local = try? lookup(name) }
                guard let local else { throw fail("Missing JVM local function capture.") }
                return try convert(local.cell ?? local.value, to: capture.field.type)
            }
            for symbol in capture.receiverSymbols {
                if let receiver = contextualReceivers[symbol] { return try convert(receiver, to: capture.field.type) }
            }
            if capture.extensionReceiver, let extensionValue { return try convert(extensionValue, to: capture.field.type) }
            if let symbol = capture.reifiedClass ?? capture.reifiedNullable ?? capture.reifiedMutableKind {
                let type = program.sema.types.make(.typeParam(TypeParamType(symbol: symbol)))
                let token = try materializeReifiedToken(type)
                return capture.reifiedClass != nil ? token.klass : (capture.reifiedNullable != nil ? token.nullable : token.mutableKind)
            }
            throw fail("Missing JVM local function receiver capture.")
        }
    }

    func bindLocalFunctionCaptures(_ captures: [JVMAnonymousCapture], values: [JVMValue]) throws {
        for (capture, input) in zip(captures, values) {
            if let name = capture.name, let template = capture.local {
                var local: Local
                if template.cell != nil {
                    local = Local(value: try value(template.value.type), mutable: template.mutable, cell: input, functionType: template.functionType, symbol: template.symbol)
                } else { local = Local(value: input, mutable: false, functionType: template.functionType, symbol: template.symbol) }
                local.delegateSymbol = template.delegateSymbol; local.lateName = template.lateName
                scopes[0][name] = local
            }
            for symbol in capture.receiverSymbols { contextualReceivers[symbol] = input }
            if capture.extensionReceiver { extensionValue = input }
            if let owner, capture.receiverSymbols.contains(owner.symbol) { thisValue = input }
        }
        for (capture, klass) in zip(captures, values) {
            guard let symbol = capture.reifiedClass,
                  let nullable = zip(captures, values).first(where: { $0.0.reifiedNullable == symbol })?.1,
                  let mutableKind = zip(captures, values).first(where: { $0.0.reifiedMutableKind == symbol })?.1 else { continue }
            reifiedRuntimeTokens[symbol] = ReifiedRuntimeToken(klass: klass, nullable: nullable, mutableKind: mutableKind)
        }
    }

    func localFunction(_ id: ExprID) throws {
        guard case let .localFunDecl(name, receiverType, parameters, returnType, body, suspend, range, typeParameters, isTailrec) = arena.expr(id),
              let symbol = program.sema.bindings.identifierSymbol(for: id),
              let signature = program.sema.symbols.functionSignature(for: symbol),
              signature.contextReceiverTypes.isEmpty, signature.contextParameterTypes.isEmpty else { throw fail("Missing JVM local function declaration.", id) }
        let declaration = FunDecl(range: range, name: name, modifiers: [], typeParams: typeParameters, receiverType: receiverType, valueParams: parameters, returnType: returnType, body: body, isSuspend: suspend, isTailrec: isTailrec)
        let logical = try program.functionReference(declaration, symbol: symbol, member: false)
        let container = owner?.name ?? program.facadeName
        let number = program.nextClosure; program.nextClosure += 1
        var captures: [JVMAnonymousCapture] = []
        let visible = localCaptureEnvironment()
        var free = Set(program.sema.bindings.localFunctionCaptureSymbols(for: symbol))
        let outerSymbols = Set(visible.values.compactMap(\.symbol))
        for parameter in parameters {
            if let expression = parameter.defaultValue {
                free.formUnion(CaptureAnalyzer().collectCapturedOuterSymbols(in: expression, ast: program.ast, sema: program.sema, outerSymbols: outerSymbols, skipNestedClosures: false))
            }
        }
        free.formUnion(localReferenceCaptureSymbols(in: id))
        for (name, local) in visible.sorted(by: { context.interner.resolve($0.key) < context.interner.resolve($1.key) }) where local.symbol.map({ free.contains($0) }) ?? true {
            let storage = local.cell ?? local.value
            captures.append(JVMAnonymousCapture(field: JVMField(owner: container, name: "$capture" + String(captures.count), type: storage.type, access: 0x1012), name: name, local: local))
        }
        var receivers = contextualReceivers
        if let owner, let thisValue, !beforeDelegation {
            receivers[owner.symbol] = thisValue
            receivers[SyntheticSymbolScheme.receiverParameterSymbol(for: owner.symbol)] = thisValue
        }
        var groups: [Int: [SymbolID]] = [:], receiverValues: [Int: JVMValue] = [:]
        for (symbol, input) in receivers where !beforeDelegation || input.slot != thisValue?.slot { groups[input.slot, default: []].append(symbol); receiverValues[input.slot] = input }
        if let extensionValue { groups[extensionValue.slot, default: []] += []; receiverValues[extensionValue.slot] = extensionValue }
        for slot in groups.keys.sorted() {
            captures.append(JVMAnonymousCapture(field: JVMField(owner: container, name: "$receiver" + String(captures.count), type: receiverValues[slot]!.type, access: 0x1012), receiverSymbols: groups[slot]!.sorted { $0.rawValue < $1.rawValue }, extensionReceiver: slot == extensionValue?.slot))
        }
        for type in reifiedCaptureTypes(id, specialize: false) {
            guard case let .typeParam(parameter) = program.sema.types.kind(of: type) else { continue }
            captures.append(JVMAnonymousCapture(field: JVMField(owner: container, name: "$type" + String(parameter.symbol.rawValue), type: .reference("java/lang/Class", nullable: false), access: 0x1012), reifiedClass: parameter.symbol))
            captures.append(JVMAnonymousCapture(field: JVMField(owner: container, name: "$nullable" + String(parameter.symbol.rawValue), type: .boolean, access: 0x1012), reifiedNullable: parameter.symbol))
            captures.append(JVMAnonymousCapture(field: JVMField(owner: container, name: "$mutable" + String(parameter.symbol.rawValue), type: .int, access: 0x1012), reifiedMutableKind: parameter.symbol))
        }
        let reference = JVMFunctionReference(name: "$local" + String(number) + "$" + logical.name, parameters: captures.map { $0.field.type } + logical.parameters, result: logical.result, owner: container, ownerIsInterface: owner?.isInterface == true, isSuspend: suspend)
        guard reference.parameters.reduce(0, { $0 + $1.width }) + (suspend ? 1 : 0) <= 255 else { throw fail("JVM local function parameter slot limit exceeded.", id) }
        // Register before emitting the body so recursive calls use this exact environment.
        program.references[symbol] = reference
        program.localFunctions[symbol] = JVMLocalFunctionPlan(reference: reference, captures: captures)
        let helper = JVMFunctionBuilder(program: program, declaration: declaration, reference: reference, owner: owner)
        helper.isStaticBody = true; helper.leadingCaptureCount = captures.count
        helper.functionSymbol = symbol; helper.semanticSignature = signature
        let inputs = try reference.parameters.map { try helper.value($0) }
        helper.parameterInputs = Array(inputs.dropFirst(captures.count))
        try helper.bindLocalFunctionCaptures(captures, values: Array(inputs.prefix(captures.count)))
        program.syntheticFunctions[container, default: []].append(try helper.build())
        if parameters.contains(where: \.hasDefaultValue) {
            let defaultReference = try program.defaultReference(symbol)
            let physical = defaultReference.isSuspend ? defaultReference.suspendABI : defaultReference
            let placeholder = FunDecl(range: range, name: context.interner.intern(defaultReference.name), modifiers: [], body: .unit)
            let defaults = JVMFunctionBuilder(program: program, declaration: placeholder, reference: physical, owner: owner)
            defaults.isStaticBody = true; defaults.functionSymbol = symbol; defaults.semanticSignature = signature
            let inputs = try physical.parameters.map { try defaults.value($0) }
            try defaults.bindLocalFunctionCaptures(captures, values: Array(inputs.prefix(captures.count)))
            let offset = captures.count + (receiverType == nil ? 0 : 1)
            if receiverType != nil { defaults.extensionValue = inputs[captures.count] }
            if let receiver = defaults.extensionValue ?? defaults.thisValue { defaults.contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)] = receiver }
            let masks = (parameters.count + 31) / 32
            let maskIndex = reference.parameters.count + (suspend ? 1 : 0)
            try program.applyDefaults(defaults, parameters: parameters, inputs: Array(inputs.dropFirst(offset).prefix(parameters.count)), masks: Array(inputs.dropFirst(maskIndex).prefix(masks)))
            let target = suspend ? reference.suspendABI : reference
            let result = target.result == .unit ? nil : try defaults.value(target.result)
            var args = Array(inputs.prefix(reference.parameters.count))
            if suspend { args.append(inputs[reference.parameters.count]) }
            defaults.instructions.append(.call(target, args, result))
            defaults.instructions.append(.returnValue(result))
            var defaultsFunction = defaults.finish()
            defaultsFunction.checksParameters = false
            program.syntheticFunctions[container, default: []].append(defaultsFunction)
        }
    }

    func localFunctionCall(_ plan: JVMLocalFunctionPlan, symbol: SymbolID, args: [CallArgument], receiver: ExprID?, id: ExprID, expectedResult: JVMValueType?) throws -> JVMIntrinsicResult {
        let reference = plan.reference
        var values = try localFunctionCaptureValues(plan.captures)
        let extensionReceiver = program.extensionSymbols.contains(symbol)
        if extensionReceiver {
            guard let input = try receiver.map(requireValue) ?? implicitExtensionReceiver(id) else { throw fail("Missing JVM local extension receiver.", id) }
            values.append(try convert(input, to: reference.parameters[values.count]))
        }
        let types = Array(reference.parameters.dropFirst(values.count))
        let declarations = program.sourceParameters[symbol]
        let ordered: (values: [JVMValue], masks: [UInt32])
        if args.isEmpty, declarations?.count == 1, declarations![0].isVararg, declarations![0].hasDefaultValue {
            ordered = ([try zero(types[0])], [1])
        } else {
            ordered = try arguments(args, binding: program.sema.bindings.callBinding(for: id), parameters: types, declarations: declarations, id: id)
        }
        let tailrecPrefix = extensionReceiver ? Array(values.suffix(1)) : []
        if try emitTailrec(
            id, symbol: symbol, dispatch: nil, prefix: tailrecPrefix,
            values: ordered.values, masks: ordered.masks
        ) {
            return JVMIntrinsicResult(value: nil)
        }
        values += ordered.values
        let result = reference.result == .unit ? nil : try value(reference.result)
        if ordered.masks.contains(where: { $0 != 0 }) {
            values += try maskArguments(ordered.masks, constructor: false)
            instructions.append(.call(try program.defaultReference(symbol), values, result))
        } else { instructions.append(.call(reference, values, result)) }
        let type = try expectedResult ?? program.expressionType(id)
        return JVMIntrinsicResult(value: type == .unit ? nil : try result.map { try convert($0, to: type) })
    }

    func localFunctionReference(_ id: ExprID, symbol: SymbolID, receiver: ExprID?, plan: JVMLocalFunctionPlan) throws -> JVMValue {
        guard let function = functionType(id), function.contextReceivers.isEmpty,
              program.sema.bindings.callableReferenceBinding(for: id)?.isCallableReferenceAdapter != true else { throw fail("Unsupported JVM adapted local function reference.", id) }
        let reference = plan.reference
        var captures = try localFunctionCaptureValues(plan.captures)
        let logical = Array(reference.parameters.dropFirst(plan.captures.count))
        let inputs = try ([function.receiver].compactMap { $0 } + function.params).map(program.type)
        let result = try program.type(function.returnType)
        let bound = logical.count == inputs.count + 1 && program.extensionSymbols.contains(symbol)
        if bound {
            guard let receiver = try receiver.map(requireValue) ?? implicitExtensionReceiver(id) else { throw fail("Missing bound JVM local reference receiver.", id) }
            captures.append(try convert(receiver, to: logical[0]))
        }
        guard logical.count == inputs.count + (bound ? 1 : 0) else { throw fail("JVM local reference arity mismatch.", id) }
        let number = program.nextClosure; program.nextClosure += 1
        let container = reference.owner!, name = container + "$LocalReference" + String(number)
        let wrapper = JVMFunctionReference(name: "$localReference" + String(number), parameters: captures.map(\.type) + inputs, result: result, owner: container, ownerIsInterface: reference.ownerIsInterface, isSuspend: function.isSuspend)
        let helper = JVMFunctionBuilder(program: program, declaration: FunDecl(range: arena.exprRange(id)!, name: context.interner.intern(wrapper.name), modifiers: [], body: .unit), reference: wrapper, owner: owner)
        helper.isStaticBody = true; helper.isSuspendBody = function.isSuspend
        let values = try wrapper.parameters.map { try helper.value($0) }
        let args = try zip(values, reference.parameters).map { try helper.convert($0.0, to: $0.1) }
        let returned = reference.result == .unit ? nil : try helper.value(reference.result)
        helper.instructions.append(.call(reference, args, returned))
        helper.instructions.append(.returnValue(result == .unit ? nil : try returned.map { try helper.convert($0, to: result) }))
        program.syntheticFunctions[container, default: []].append(helper.finish())
        let arity = inputs.count + (function.isSuspend ? 1 : 0)
        program.functionArities.insert(arity)
        var generated = try program.closureClass(name, captures: captures.enumerated().map { ("capture\($0.offset)", $0.element.type) }, inputs: inputs, result: result, helper: wrapper, suspend: function.isSuspend, superclass: function.isCallableReference ? "kotlin/jvm/internal/FunctionReferenceImpl" : "java/lang/Object")
        if function.isCallableReference {
            try initializeLocalReferenceSuperclass(&generated, arity: arity, symbol: symbol, reference: reference)
        }
        program.closureClasses.append(generated)
        let object = try constructJDK(name, parameters: captures.map(\.type), arguments: captures)
        if program.sema.bindings.samUnderlyingFunctionType(for: id) != nil || program.sema.bindings.samInterfaceType(for: id) != nil {
            return try convert(object, to: .reference("kotlin/jvm/functions/Function" + String(arity), nullable: false))
        }
        return try convert(object, to: program.expressionType(id))
    }

    private func initializeLocalReferenceSuperclass(_ generated: inout JVMClass, arity: Int, symbol: SymbolID, reference: JVMFunctionReference) throws {
        var constructor = generated.functions[0]
        var slot = constructor.locals.map { $0.slot + $0.type.width }.max() ?? 1
        func temporary(_ type: JVMValueType) -> JVMValue { let input = JVMValue(slot: slot, type: type); slot += type.width; constructor.locals.append(input); return input }
        let count = temporary(.int), klass = temporary(.reference("java/lang/Class", nullable: false)), name = temporary(.string), signature = temporary(.string), flags = temporary(.int)
        let sourceName = program.sema.symbols.symbol(symbol).map { context.interner.resolve($0.name) } ?? reference.name
        var code: [JVMInstruction] = [.constant(.int(Int32(arity)), count), .classLiteral(reference.owner!, klass), .constant(.string(sourceName), name), .callableSignature(reference.owner!, reference.name, reference.descriptor, signature), .constant(.int(1), flags)]
        let types = [count.type, klass.type, name.type, signature.type, flags.type]
        let target = JVMForeignMethod(owner: generated.superclass, name: "<init>", descriptor: "(" + types.map(\.descriptor).joined() + ")V", parameters: types, result: .reference(generated.superclass, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        code.append(.foreignCall(target, receiver: constructor.locals[0], arguments: [count, klass, name, signature, flags], result: nil))
        constructor.instructions = code + constructor.instructions.dropFirst(); generated.functions[0] = constructor
    }
}
