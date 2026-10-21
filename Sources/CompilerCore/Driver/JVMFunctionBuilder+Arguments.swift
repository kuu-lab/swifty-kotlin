import Foundation

extension JVMFunctionBuilder {
    func zero(_ type: JVMValueType) throws -> JVMValue {
        let literal: JVMConstant
        switch type {
        case .long, .ulong: literal = .long(0)
        case .float: literal = .float(0)
        case .double: literal = .double(0)
        case .boolean: literal = .boolean(false)
        case .reference, .string, .unsignedArray: literal = .null
        default: literal = .int(0)
        }
        return try constant(literal, type)
    }

    /// Evaluate explicit arguments in source order, then arrange parameter slots.
    /// Missing values are placeholders; the callee's default bridge evaluates
    /// defaults in declaration order after all explicit expressions have run.
    func arguments(_ args: [CallArgument], binding: CallBinding?, parameters: [JVMValueType], declarations: [ValueParamDecl]?, id: ExprID? = nil) throws -> (values: [JVMValue], masks: [UInt32]) {
        if declarations?.count == 1, declarations![0].isVararg, let id {
            let element = try arrayComponent(parameters[0])
            let op = JVMTextOperation(name: "sourceVararg", receiver: "", receiverType: element, parameters: [JVMTextParameter(name: context.interner.resolve(declarations![0].name), source: "T", type: element, fallback: nil, variadic: true)], sourceResult: "", result: .unit, owner: "", method: nil, instance: false)
            return (try textArguments(op, args: args, binding: binding, source: zero(element), id: id), [0])
        }
        var supplied: [Int: JVMValue] = [:]
        for (i, arg) in args.enumerated() {
            guard !arg.isSpread else { throw fail("JVM vararg spreading is unsupported.", id) }
            let index = binding?.parameterMapping[i] ?? arg.label.flatMap { label in declarations?.firstIndex { $0.name == label } } ?? i
            guard parameters.indices.contains(index), supplied[index] == nil else { throw fail("Invalid JVM argument mapping.", id) }
            let evaluated = try expression(arg.expr)
            if terminated { throw JVMTerminatedExpression() }
            let sourceValue: JVMValue
            if let evaluated { sourceValue = evaluated }
            else if try program.expressionType(arg.expr) == .unit {
                // Unit-producing calls are values when passed to an object parameter.
                let unit: JVMValueType = .reference("kotlin/Unit", nullable: false)
                sourceValue = try value(unit)
                instructions.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: unit, access: 0x19), sourceValue))
            } else { throw fail("JVM argument does not produce a value.", arg.expr) }
            var source = sourceValue
            if let symbol = binding?.chosenCallee, let signature = program.sema.symbols.functionSignature(for: symbol), signature.parameterTypes.indices.contains(index),
               source.type.referenceName?.hasPrefix("kotlin/jvm/functions/Function") == true,
               case let .classType(target) = program.sema.types.kind(of: signature.parameterTypes[index]),
               program.sema.symbols.symbol(target.classSymbol)?.flags.contains(.funInterface) == true,
               TypeCheckHelpers().effectiveSamAbstractMethod(for: target.classSymbol, symbols: program.sema.symbols) != nil {
                source = try adaptSAM(source, target: signature.parameterTypes[index], at: arg.expr)
            }
            supplied[index] = try convert(source, to: parameters[index])
        }
        var values: [JVMValue] = [], masks = Array(repeating: UInt32(0), count: (parameters.count + 31) / 32)
        for (i, type) in parameters.enumerated() {
            if let value = supplied[i] { values.append(value) }
            else {
                guard declarations?.indices.contains(i) == true, declarations![i].hasDefaultValue else { throw fail("Missing JVM argument without a default.", id) }
                masks[i / 32] |= UInt32(1) << UInt32(i % 32)
                values.append(try zero(type))
            }
        }
        return (values, masks)
    }

    func maskArguments(_ masks: [UInt32], constructor: Bool) throws -> [JVMValue] {
        try masks.map { try constant(.int(Int32(bitPattern: $0)), .int) } + [constant(.null, .reference(constructor ? "kotlin/jvm/internal/DefaultConstructorMarker" : "java/lang/Object", nullable: true))]
    }

    func sourceCall(_ args: [CallArgument], receiver: ExprID? = nil, receiverValue: JVMValue? = nil, id: ExprID, expectedResult: JVMValueType? = nil) throws -> JVMIntrinsicResult? {
        let binding = program.sema.bindings.callBinding(for: id)
        guard let symbol = binding?.chosenCallee ?? program.sema.bindings.identifierSymbol(for: id) else { return nil }
        if let local = program.localFunctions[symbol] {
            return try localFunctionCall(local, symbol: symbol, args: args, receiver: receiver, id: id, expectedResult: expectedResult)
        }
        let reference = program.references[symbol]
        let method = program.methods[symbol] ?? context.jvmImports?.methods[symbol]
        guard reference != nil || method != nil else { return nil }
        let constructor = method?.isConstructor == true
        let plan = method.flatMap { m in program.classes.values.first { $0.name == m.owner } }
        if constructor, plan?.isEnum == true { throw fail("JVM enum constructors can only initialize enum entries.", id) }
        let extensionCall = program.extensionSymbols.contains(symbol) || context.jvmImports?.extensionSymbols.contains(symbol) == true
        var dispatch: JVMValue?, prefix: [JVMValue] = []
        if constructor, let plan, plan.isInner {
            prefix = [try receiverValue ?? receiver.map(requireValue) ?? enclosingInstance(plan.outer!)]
        } else if let method, !method.isStatic && !constructor {
            dispatch = try (receiver != nil || receiverValue != nil) && !extensionCall ? receiverValue ?? requireValue(receiver!) : instance(id)
        }
        if extensionCall {
            let implicit = implicitExtensionReceiver(id)
            guard let value = try receiverValue ?? receiver.map(requireValue) ?? implicit else { throw fail("Missing JVM extension receiver.", id) }
            prefix.append(value)
        }
        let allTypes = reference?.parameters ?? method!.parameters
        let types = Array(allTypes.dropFirst(prefix.count))
        let defaultSymbol = program.defaultOwner(binding?.defaultArgumentOwner ?? symbol)
        let defaultParameters = program.sourceParameters[defaultSymbol] ?? program.sourceParameters[symbol]
        // Value constructors are static source operations: evaluate their
        // arguments before allocating the internal box, including suspension.
        let deferredValueBox = constructor && plan?.isValue == true
        let object = constructor ? try value(method!.result) : nil
        if let object, !deferredValueBox { instructions.append(.allocate(method!.owner, object)); pendingAllocations.append(object) }
        defer { if object != nil && !deferredValueBox { pendingAllocations.removeLast() } }
        let ordered = try arguments(args, binding: binding, parameters: types, declarations: defaultParameters, id: id)
        var values = try zip(prefix, allTypes).map { try convert($0.0, to: $0.1) } + ordered.values
        let usesDefaults = ordered.masks.contains { $0 != 0 }
        if try emitTailrec(id, symbol: symbol, dispatch: dispatch, prefix: prefix, values: ordered.values, masks: ordered.masks) {
            return JVMIntrinsicResult(value: nil)
        }
        let resultType = try expectedResult ?? program.expressionType(id)
        let physicalResult = reference?.result ?? method!.result
        // A safe Unit call has logical type Unit?, but its ordinary entry
        // still returns void. The safe-call join materializes Unit afterward.
        let result = constructor || physicalResult == .unit || resultType == .unit ? nil : try value(resultType)
        if deferredValueBox, let object { instructions.append(.allocate(method!.owner, object)) }
        if usesDefaults {
            if constructor {
                values += try maskArguments(ordered.masks, constructor: true)
                let params = allTypes + Array(repeating: JVMValueType.int, count: ordered.masks.count) + [.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)]
                let call = JVMForeignMethod(owner: method!.owner, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: method!.result, isStatic: false, isInterface: false, isAbstract: false)
                instructions.append(.foreignCall(call, receiver: object, arguments: values, result: nil))
            } else {
                let target = try program.defaultReference(defaultSymbol)
                values = (dispatch.map { [$0] } ?? []) + values + (try maskArguments(ordered.masks, constructor: false))
                // An inherited default can belong to a generic interface even
                // when the concrete implementation takes primitive arguments.
                guard values.count == target.parameters.count else { throw fail("Invalid JVM default argument count.", id) }
                values = try zip(values, target.parameters).map { try convert($0.0, to: $0.1) }
                instructions.append(.call(target, values, result))
            }
        } else if var method {
            if let receiver, isSuper(receiver) { method = try superMethod(method, receiver: receiver) }
            instructions.append(.foreignCall(method, receiver: object ?? dispatch, arguments: values, result: result))
        } else if let reference { instructions.append(.call(reference, values, result)) }
        return JVMIntrinsicResult(value: object ?? result)
    }
}
