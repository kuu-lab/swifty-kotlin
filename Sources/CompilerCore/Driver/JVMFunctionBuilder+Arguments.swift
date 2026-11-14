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

    /// The runtime array component a vararg call must allocate. The erased
    /// descriptor of a generic callee takes Object[], but the invocation
    /// passes the specialized array — String[] for T=String — which the
    /// implementing class's erased-override bridge checkcasts back down.
    func specializedVarargElement(at index: Int, erased: JVMValueType, binding: CallBinding?) throws -> JVMValueType {
        guard let binding,
              let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee),
              signature.valueParameterIsVararg.indices.contains(index), signature.valueParameterIsVararg[index],
              signature.parameterTypes.indices.contains(index)
        else { return try arrayComponent(erased) }
        let declared = signature.parameterTypes[index]
        let typeVarBySymbol = program.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (symbol, argument) in zip(signature.typeParameterSymbols, binding.substitutedTypeArguments) {
            guard let variable = typeVarBySymbol[symbol] else { continue }
            substitution[variable] = argument
        }
        let substituted = program.sema.types.substituteTypeParameters(in: declared, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
        guard substituted != declared else { return try arrayComponent(erased) }
        return try JVMClasspathIndex.argumentType(.invariant(substituted), sema: program.sema, ctx: program.context)
    }

    /// Evaluate explicit arguments in source order, then arrange parameter slots.
    /// Missing values are placeholders; the callee's default bridge evaluates
    /// defaults in declaration order after all explicit expressions have run.
    func arguments(
        _ args: [CallArgument],
        binding: CallBinding?,
        parameters: [JVMValueType],
        declarations: [ValueParamDecl]?,
        contextParameterTypes: [JVMValueType] = [],
        id: ExprID? = nil,
        composableParameter: Int? = nil
    ) throws -> (values: [JVMValue], masks: [UInt32], contextValues: [Int: JVMValue]) {
        let signature = binding.flatMap { program.sema.symbols.functionSignature(for: $0.chosenCallee) }
        let varargIndex = declarations?.firstIndex(where: \.isVararg)
            ?? signature?.valueParameterIsVararg.firstIndex(of: true)
        let varargElement = try varargIndex.map { try specializedVarargElement(at: $0, erased: parameters[$0], binding: binding) }
        var supplied: [Int: JVMValue] = [:]
        var suppliedContext: [Int: JVMValue] = [:]
        var varargValues: [(JVMValue, Bool)] = []
        var positionalCursor = 0
        for (i, arg) in args.enumerated() {
            if let contextIndex = binding?.contextParameterArgumentMapping[i] {
                guard contextParameterTypes.indices.contains(contextIndex), suppliedContext[contextIndex] == nil else {
                    throw fail("Invalid JVM context argument mapping.", id)
                }
                let evaluated = try expression(arg.expr)
                if terminated { throw JVMTerminatedExpression() }
                let source: JVMValue
                if let evaluated { source = evaluated }
                else if try program.expressionType(arg.expr) == .unit {
                    let unit: JVMValueType = .reference("kotlin/Unit", nullable: false)
                    source = try value(unit)
                    instructions.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: unit, access: 0x19), source))
                } else { throw fail("JVM context argument does not produce a value.", arg.expr) }
                suppliedContext[contextIndex] = try convert(source, to: contextParameterTypes[contextIndex])
                continue
            }
            let index: Int
            if let mapped = binding?.parameterMapping[i] {
                index = mapped
            } else if let named = arg.label.flatMap({ label in declarations?.firstIndex { $0.name == label } }) {
                index = named
            } else if let varargIndex, positionalCursor >= varargIndex {
                index = varargIndex
            } else {
                index = positionalCursor
                positionalCursor += 1
            }
            guard parameters.indices.contains(index), index == varargIndex || supplied[index] == nil else { throw fail("Invalid JVM argument mapping.", id) }
            if index != varargIndex { positionalCursor = max(positionalCursor, index + 1) }
            let evaluated = try index == composableParameter ? composeContent(arg.expr) : expression(arg.expr)
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
               TypeCheckHelpers().effectiveSamAbstractMethod(for: target.classSymbol, symbols: program.sema.symbols, types: program.sema.types) != nil {
                source = try adaptSAM(source, target: signature.parameterTypes[index], at: arg.expr)
            }
            if index == varargIndex {
                guard let element = varargElement else { throw fail("Missing JVM vararg component type.", id) }
                let spread = arg.isSpread || arg.label != nil && source.type.referenceName?.hasPrefix("[") == true
                if spread && element.referenceName != nil {
                    let array = JVMValueType.reference("[" + element.descriptor, nullable: false)
                    let erased = JVMValueType.reference("[Ljava/lang/Object;", nullable: false)
                    source = try jdkCall("java/util/Arrays", "copyOf", [erased, .int], erased, arguments: [source, textLength(source)], resolved: array)!
                }
                varargValues.append((source, spread))
                continue
            }
            guard !arg.isSpread else { throw fail("JVM vararg spreading is unsupported.", id) }
            supplied[index] = try convert(source, to: parameters[index])
        }
        var values: [JVMValue] = [], masks = Array(repeating: UInt32(0), count: (parameters.count + 31) / 32)
        for (i, type) in parameters.enumerated() {
            if i == varargIndex {
                values.append(try textVararg(varargValues, element: varargElement!))
            } else if let value = supplied[i] { values.append(value) }
            else {
                let hasDefault = declarations.flatMap { $0.indices.contains(i) ? $0[i].hasDefaultValue : nil }
                    ?? (signature.map { $0.valueParameterHasDefaultValues.indices.contains(i) && $0.valueParameterHasDefaultValues[i] } ?? false)
                guard hasDefault else { throw fail("Missing JVM argument without a default.", id) }
                masks[i / 32] |= UInt32(1) << UInt32(i % 32)
                values.append(try zero(type))
            }
        }
        return (values, masks, suppliedContext)
    }

    func maskArguments(_ masks: [UInt32], constructor: Bool) throws -> [JVMValue] {
        try masks.map { try constant(.int(Int32(bitPattern: $0)), .int) } + [constant(.null, .reference(constructor ? "kotlin/jvm/internal/DefaultConstructorMarker" : "java/lang/Object", nullable: true))]
    }

    func sourceCall(_ args: [CallArgument], receiver: ExprID? = nil, receiverValue: JVMValue? = nil, id: ExprID, expectedResult: JVMValueType? = nil) throws -> JVMIntrinsicResult? {
        let binding = program.sema.bindings.callBinding(for: id)
        guard let symbol = binding?.chosenCallee ?? program.sema.bindings.identifierSymbol(for: id) else { return nil }
        if let binding, let metro = try importedMetroCall(binding, id: id) { return metro }
        if let local = program.localFunctions[symbol] {
            return try localFunctionCall(local, symbol: symbol, args: args, receiver: receiver, id: id, expectedResult: expectedResult)
        }
        let reference = program.references[symbol]
        let method = program.methods[symbol] ?? context.jvmImports?.method(for: symbol)
        guard reference != nil || method != nil else { return nil }
        if let method, let contract = context.jvmImports?.importedComposeCalls[symbol] {
            return try importedComposeCall(method, contract: contract, args: args, binding: binding,
                                           receiver: receiver, receiverValue: receiverValue, expectedResult: expectedResult, id: id)
        }
        let constructor = method?.isConstructor == true
        let plan = method.flatMap { m in program.classes.values.first { $0.name == m.owner } }
        if constructor, plan?.isEnum == true { throw fail("JVM enum constructors can only initialize enum entries.", id) }
        let extensionCall = program.extensionSymbols.contains(symbol) || context.jvmImports?.isExtension(symbol) == true
        var dispatch: JVMValue?, prefix: [JVMValue] = []
        if constructor, let plan, plan.isLocalNominal, !plan.captures.isEmpty {
            prefix = try localFunctionCaptureValues(plan.captures)
            if plan.isInner, let outer = plan.outer { prefix.append(try receiverValue ?? receiver.map(requireValue) ?? enclosingInstance(outer)) }
        } else if constructor, let plan, plan.isInner {
            prefix = [try receiverValue ?? receiver.map(requireValue) ?? enclosingInstance(plan.outer!)]
        } else if let method, !method.isStatic && !constructor {
            dispatch = try (receiver != nil || receiverValue != nil) && !extensionCall ? receiverValue ?? requireValue(receiver!) : instance(id)
        } else if let method, method.isStatic, !constructor, !extensionCall,
                  receiverValue == nil, let receiver {
            // A @JvmStatic member invoked through an instance expression owes
            // the receiver's side effects an evaluation even though nothing is
            // passed as the dispatch receiver. A bare class qualifier (`C` in
            // `C.twice(x)`) denotes a type, not a value, so it is not evaluated.
            let isTypeQualifier = program.sema.bindings.identifierSymbol(for: receiver)
                .flatMap { program.sema.symbols.symbol($0)?.kind }
                .map { [.class, .interface, .enumClass, .annotationClass].contains($0) } ?? false
            if !isTypeQualifier { _ = try requireValue(receiver) }
        }
        if let method, context.jvmImports?.composeContentSymbols.contains(symbol) == true {
            guard let dispatch, args.count == 1 else { throw fail("Invalid JVM ComposeView.setContent call.", id) }
            let content = try composeContent(args[0].expr)
            instructions.append(.foreignCall(method, receiver: dispatch, arguments: [content], result: nil))
            return JVMIntrinsicResult(value: nil)
        }
        if extensionCall {
            let implicit = implicitExtensionReceiver(id)
            guard let value = try receiverValue ?? receiver.map(requireValue) ?? implicit else { throw fail("Missing JVM extension receiver.", id) }
            prefix.append(value)
        }
        let allTypes = reference?.parameters ?? method!.parameters
        let isComposable = program.jvmComposableFunctions.contains(symbol)
        let types = Array(allTypes.dropFirst(prefix.count).dropLast(isComposable ? JVMCompose.suffix.count : 0))
        let signature = binding.flatMap { program.sema.symbols.functionSignature(for: $0.chosenCallee) }
        let contextParameterTypes = try (signature?.contextParameterTypes ?? []).map(program.type)
        guard types.count >= contextParameterTypes.count else { throw fail("JVM context parameter signature mismatch.", id) }
        let valueTypes = Array(types.dropFirst(contextParameterTypes.count))
        let defaultSymbol = program.defaultOwner(binding?.defaultArgumentOwner ?? symbol)
        let defaultParameters = program.sourceParameters[defaultSymbol] ?? program.sourceParameters[symbol]
        let object = constructor ? try value(method!.result) : nil
        let ordered = try arguments(
            args,
            binding: binding,
            parameters: valueTypes,
            declarations: defaultParameters,
            contextParameterTypes: contextParameterTypes,
            id: id
        )
        for contextIndex in contextParameterTypes.indices {
            let contextValue: JVMValue
            if let explicit = ordered.contextValues[contextIndex] {
                contextValue = explicit
            } else if let binding,
                      binding.contextParameterReceiverSymbols.indices.contains(contextIndex),
                      let receiverSymbol = binding.contextParameterReceiverSymbols[contextIndex],
                      let receiver = contextualReceivers[receiverSymbol] {
                contextValue = try convert(receiver, to: contextParameterTypes[contextIndex])
            } else {
                throw fail("Missing JVM context parameter value.", id)
            }
            prefix.append(contextValue)
        }
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
        if let object { instructions.append(.allocate(method!.owner, object)) }
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
        } else if let reference {
            if isComposable { try composableCall(reference, symbol: symbol, arguments: values, result: result, at: id) }
            else { instructions.append(.call(reference, values, result)) }
        }
        return JVMIntrinsicResult(value: object ?? result)
    }
}
