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
    func arguments(_ args: [CallArgument], binding: CallBinding?, parameters: [JVMValueType], declarations: [ValueParamDecl]?, id: ExprID? = nil, composableParameters: Set<Int> = [], importedDefaults: [Bool]? = nil) throws -> (values: [JVMValue], masks: [UInt32]) {
        let signature = binding.flatMap { program.sema.symbols.functionSignature(for: $0.chosenCallee) }
        let importedFunction = binding.flatMap { context.jvmImports?.methods[$0.chosenCallee]?.kotlinFunction }
        let varargIndex = declarations?.firstIndex(where: \.isVararg)
            ?? signature?.valueParameterIsVararg.firstIndex(of: true)
        let varargElement = try varargIndex.map { try specializedVarargElement(at: $0, erased: parameters[$0], binding: binding) }
        var supplied: [Int: JVMValue] = [:]
        var varargValues: [(JVMValue, Bool)] = []
        var positionalCursor = 0
        for (i, arg) in args.enumerated() {
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
            let evaluated: JVMValue?
            if composableParameters.contains(index) {
                evaluated = try composeContent(arg.expr)
            } else if let composer = activeComposer, let importedFunction, importedFunction.hasInlineContextCallback,
                      importedFunction.parameters.indices.contains(index),
                      !importedFunction.parameters[index].isCrossinline, !importedFunction.parameters[index].isNoinline,
                      case .lambdaLiteral = arena.expr(arg.expr) {
                // Inline callbacks are invoked synchronously in the caller's composition.
                evaluated = try closure(arg.expr, capturedComposer: composer)
            } else {
                evaluated = try expression(arg.expr)
            }
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
                let sourceDefault = declarations?.indices.contains(i) == true && declarations![i].hasDefaultValue
                let importedDefault = importedDefaults?.indices.contains(i) == true && importedDefaults![i]
                guard sourceDefault || importedDefault else { throw fail("Missing JVM argument without a default.", id) }
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
        if let binding, let metro = try importedMetroCall(binding, id: id) { return metro }
        if let binding, let action = try importedGlanceActivityAction(binding, args: args, id: id) { return action }
        if let binding, let builder = try importedOneTimeWorkRequestBuilder(binding, id: id) { return builder }
        if let local = program.localFunctions[symbol] {
            return try localFunctionCall(local, symbol: symbol, args: args, receiver: receiver, id: id, expectedResult: expectedResult)
        }
        let reference = program.references[symbol]
        let method = program.methods[symbol] ?? context.jvmImports?.methods[symbol]
        guard reference != nil || method != nil else { return nil }
        if let method, let contract = context.jvmImports?.importedComposeCalls[symbol] {
            return try importedComposeCall(method, contract: contract, args: args, binding: binding,
                                           receiver: receiver, receiverValue: receiverValue, expectedResult: expectedResult, id: id)
        }
        if let method, let signature = method.kotlinFunction, let abi = method.kotlinComposeABI {
            return try metadataComposeCall(method, signature: signature, abi: abi, args: args, binding: binding,
                                           receiver: receiver, receiverValue: receiverValue, expectedResult: expectedResult, id: id)
        }
        let constructor = method?.isConstructor == true
        let plan = method.flatMap { m in program.classes.values.first { $0.name == m.owner } }
        if constructor, plan?.isEnum == true { throw fail("JVM enum constructors can only initialize enum entries.", id) }
        let extensionCall = program.extensionSymbols.contains(symbol) || context.jvmImports?.extensionSymbols.contains(symbol) == true
        var dispatch: JVMValue?, prefix: [JVMValue] = []
        if constructor, let plan, plan.isLocalNominal, !plan.captures.isEmpty {
            prefix = try localFunctionCaptureValues(plan.captures)
            if plan.isInner, let outer = plan.outer { prefix.append(try receiverValue ?? receiver.map(requireValue) ?? enclosingInstance(outer)) }
        } else if constructor, let plan, plan.isInner {
            prefix = [try receiverValue ?? receiver.map(requireValue) ?? enclosingInstance(plan.outer!)]
        } else if let method, !method.isStatic && !constructor {
            dispatch = try (receiver != nil || receiverValue != nil) && !extensionCall ? receiverValue ?? requireValue(receiver!) : instance(id)
        }
        if let method, context.jvmImports?.composeContentSymbols.contains(symbol) == true {
            guard let dispatch, args.count == 1 else { throw fail("Invalid JVM ComposeView.setContent call.", id) }
            let content = try composeContent(args[0].expr)
            instructions.append(.foreignCall(method, receiver: dispatch, arguments: [content], result: nil))
            return JVMIntrinsicResult(value: nil)
        }
        if let method {
            prefix += try importedContextArguments(binding, method: method, id: id)
            if method.kotlinFunction?.valueOperatorParameterDescriptors != nil {
                prefix.append(try receiverValue ?? receiver.map(requireValue) ?? instance(id))
            }
        }
        if extensionCall {
            let implicit = implicitExtensionReceiver(id)
            guard let value = try receiverValue ?? receiver.map(requireValue) ?? implicit else { throw fail("Missing JVM extension receiver.", id) }
            prefix.append(value)
        }
        let allTypes = reference?.parameters ?? method!.parameters
        let isComposable = program.jvmComposableFunctions.contains(symbol)
        let types = Array(allTypes.dropFirst(prefix.count).dropLast(isComposable ? JVMCompose.suffix.count : 0))
        let defaultSymbol = program.defaultOwner(binding?.defaultArgumentOwner ?? symbol)
        let defaultParameters = program.sourceParameters[defaultSymbol] ?? program.sourceParameters[symbol]
        let importedDefault = context.jvmImports?.importedDefaultMethods[symbol]
        let importedConstructor = context.jvmImports?.importedValueParameterConstructors[symbol]
        let importedConstructorDefault = context.jvmImports?.importedConstructorDefaults[symbol]
        let importedDefaults = importedDefault != nil || importedConstructor?.defaults != nil || importedConstructorDefault != nil
            ? program.sema.symbols.functionSignature(for: symbol)?.valueParameterHasDefaultValues : nil
        let object = constructor ? try value(method!.result) : nil
        // Constructor arguments can suspend, so allocate only after every
        // argument has completed. An uninitialized reference cannot cross a
        // continuation boundary on the JVM.
        let ordered = try arguments(args, binding: binding, parameters: types, declarations: defaultParameters, id: id,
                                    composableParameters: context.jvmImports?.importedComposableParameters[symbol] ?? [],
                                    importedDefaults: importedDefaults)
        var values = try zip(prefix, allTypes).map { try convert($0.0, to: $0.1) } + ordered.values
        let usesDefaults = ordered.masks.contains { $0 != 0 }
        if try emitTailrec(id, symbol: symbol, dispatch: dispatch, prefix: prefix, values: ordered.values, masks: ordered.masks) {
            return JVMIntrinsicResult(value: nil)
        }
        let resultType = try expectedResult ?? program.expressionType(id)
        let physicalResult = reference?.result ?? method!.result
        // A safe Unit call has logical type Unit?, but its ordinary entry
        // still returns void. The safe-call join materializes Unit afterward.
        let result = constructor || physicalResult == .unit || resultType == .unit
            ? nil : try value(foreignResultType(physicalResult, resolved: resultType))
        if let object { instructions.append(.allocate(method!.owner, object)) }
        if let importedConstructor {
            let target = usesDefaults ? importedConstructor.defaults : importedConstructor.bridge
            guard let target else { throw fail("Missing JVM value-parameter constructor bridge.", id) }
            values += usesDefaults ? try maskArguments(ordered.masks, constructor: true)
                : [try constant(.null, .reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true))]
            instructions.append(.foreignCall(target, receiver: object, arguments: values, result: nil))
        } else if usesDefaults {
            if let importedDefault {
                values += try maskArguments(ordered.masks, constructor: false)
                instructions.append(.foreignCall(importedDefault, receiver: nil, arguments: values, result: result))
            } else if constructor {
                values += try maskArguments(ordered.masks, constructor: true)
                let params = allTypes + Array(repeating: JVMValueType.int, count: ordered.masks.count) + [.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)]
                let call = importedConstructorDefault ?? JVMForeignMethod(owner: method!.owner, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: method!.result, isStatic: false, isInterface: false, isAbstract: false)
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
        return JVMIntrinsicResult(value: try object ?? result.map { try convert($0, to: resultType) })
    }
}
