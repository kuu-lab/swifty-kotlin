private let continuationType = JVMValueType.reference("kotlin/coroutines/Continuation", nullable: false)
private let coroutineObject = JVMValueType.reference("java/lang/Object", nullable: true)

extension JVMProgramBuilder {
    func lowerCoroutines(_ input: JVMProgram) throws -> JVMProgram {
        var program = input
        var states: [JVMClass] = [], helpers: [String: [JVMFunction]] = [:]
        let interfaces = Set(program.classes.filter(\.isInterface).map(\.name))
        var valueResults: [String: JVMSuspendValueResult] = [:]
        for function in program.functions + program.classes.flatMap(\.functions) {
            if let result = function.suspendValueResult ?? function.forwardedSuspendValueResult {
                valueResults[(function.owner ?? program.internalClassName) + "." + function.reference.name + function.reference.descriptor] = result
            }
        }
        func lower(_ function: JVMFunction) throws -> JVMFunction {
            if function.inlineContinuation != nil {
                var body = function; body.inlineSuspendValueResults = valueResults; return body
            }
            guard function.isSuspend else {
                guard !function.instructions.contains(where: { $0.isSuspension }) else { throw JVMFrontendError(message: "JVM suspension requires a suspend function or an inline suspend call site.") }
                return function
            }
            let owner = function.owner ?? program.internalClassName
            if function.isInline {
                let reified = function.typeParameters.contains(where: \.isReified)
                var body = inlineSuspendBody(function, exported: reified)
                body.inlineSuspendValueResults = valueResults
                if reified { return body }
                helpers[owner, default: []].append(body)
            }
            let number = nextClosure; nextClosure += 1
            let name = owner + "$Continuation" + String(number)
            let lowered = try coroutine(function, stateName: name, helperName: "$resume" + String(number), ownerIsInterface: interfaces.contains(owner), valueResults: valueResults)
            if let state = lowered.state { states.append(state) }
            if let helper = lowered.helper { helpers[owner, default: []].append(helper) }
            return lowered.wrapper
        }
        program.functions = try program.functions.map(lower)
        for i in program.classes.indices { program.classes[i].functions = try program.classes[i].functions.map(lower) }
        program.functions += helpers[program.internalClassName] ?? []
        for i in program.classes.indices { program.classes[i].functions += helpers[program.classes[i].name] ?? [] }
        program.classes += states
        let nullableValues = Dictionary(valueResults.values.filter { $0.boxed.isNullable }.map { ($0.boxed.referenceName!, $0) }, uniquingKeysWith: { first, _ in first })
        for representation in nullableValues.values.sorted(by: { $0.boxed.descriptor < $1.boxed.descriptor }) where representation.adapterOwner != nil {
            var helper = JVMClass(name: representation.adapterOwner!, superclass: "java/lang/Object", interfaces: [], access: 0x1031, functions: nullableInlineSuspendAdapters(representation), properties: [])
            helper.emitMetadata = false; program.classes.append(helper)
        }
        for i in program.classes.indices {
            if let representation = nullableValues[program.classes[i].name] {
                program.classes[i].functions += nullableInlineSuspendAdapters(representation)
            }
        }
        if input.functions.contains(where: { $0.reference.name == "main" && $0.isSuspend && $0.reference.parameters.isEmpty }) {
            let target = program.functions.first { $0.reference.name == "main" && $0.isSuspend && $0.reference.parameters.count == 1 }!.reference
            let name = program.internalClassName + "$SuspendMain"
            program.classes.append(try closureClass(name, captures: [], inputs: [continuationType], result: coroutineObject, helper: target))
            let object = JVMValue(slot: 0, type: .reference(name, nullable: false))
            let function = JVMValue(slot: 1, type: .reference("kotlin/jvm/functions/Function1", nullable: false))
            let ctor = JVMForeignMethod(owner: name, name: "<init>", descriptor: "()V", parameters: [], result: object.type, isStatic: false, isInterface: false, isAbstract: false)
            let run = JVMForeignMethod(owner: "kotlin/coroutines/jvm/internal/RunSuspendKt", name: "runSuspend", descriptor: "(Lkotlin/jvm/functions/Function1;)V", parameters: [function.type], result: .unit, isStatic: true, isInterface: false, isAbstract: false)
            program.functions.append(rawFunction(program.internalClassName, name: "main", parameters: [], result: .unit, access: 0x1009, locals: [object, function], instructions: [.allocate(name, object), .foreignCall(ctor, receiver: object, arguments: [], result: nil), .copy(object, function), .foreignCall(run, receiver: nil, arguments: [function], result: nil), .returnValue(nil)]))
            // A suspend main has no source-level function value to register arity one.
            if !functionArities.contains(1) {
                functionArities.insert(1)
                program.classes += functionRuntime().filter { type in !program.classes.contains { $0.name == type.name } }
            }
        }
        for functions in [program.functions] + program.classes.map(\.functions) {
            var signatures: Set<String> = []
            for function in functions {
                guard signatures.insert(function.reference.name + function.reference.descriptor).inserted else { throw JVMFrontendError(message: "JVM method signature collision after coroutine lowering: " + function.reference.name + function.reference.descriptor) }
            }
        }
        return program
    }

    /// The exported wrapper allocates an independent invocation frame. Its
    /// ContinuationImpl subclass resumes the same static worker directly.
    private func coroutine(_ source: JVMFunction, stateName name: String, helperName: String, ownerIsInterface: Bool, valueResults: [String: JVMSuspendValueResult]) throws -> (wrapper: JVMFunction, helper: JVMFunction?, state: JVMClass?) {
        var wrapper = source
        wrapper.reference = source.reference.suspendABI
        let owner = source.owner ?? facadeName
        let instance = source.access.map { $0 & 8 == 0 } ?? false
        guard wrapper.reference.parameters.reduce(instance ? 1 : 0, { $0 + $1.width }) <= 255 else { throw JVMFrontendError(message: "JVM suspend method parameter slot limit exceeded.") }
        if let signature = source.genericSignature, let end = signature.lastIndex(of: ")") {
            let logical = String(signature[signature.index(after: end)...])
            let boxed: [String: String] = ["V": "Lkotlin/Unit;", "B": "Ljava/lang/Byte;", "S": "Ljava/lang/Short;", "C": "Ljava/lang/Character;", "I": "Ljava/lang/Integer;", "J": "Ljava/lang/Long;", "F": "Ljava/lang/Float;", "D": "Ljava/lang/Double;", "Z": "Ljava/lang/Boolean;"]
            let unsignedNames = ["UInt", "ULong", "UByte", "UShort"].flatMap { ["kotlin/" + $0, "kotlin/" + $0 + "Array"] }
            let unsigned: String?
            if case let .named(name, _, _) = source.kotlinResult, unsignedNames.contains(name) { unsigned = "L" + name + ";" } else { unsigned = nil }
            wrapper.genericSignature = String(signature[..<end]) + "Lkotlin/coroutines/Continuation<-" + (unsigned ?? boxed[logical] ?? logical) + ">;)Ljava/lang/Object;"
        }
        if source.isAbstract { return (wrapper, nil, nil) }
        let parameters = Array(source.locals.prefix(source.parameterCount))
        var slot = parameters.reduce(0) { max($0, $1.slot + $1.type.width) }
        let completion = JVMValue(slot: slot, type: continuationType); slot += 1
        let state = JVMValue(slot: slot, type: .reference(name, nullable: false)); slot += 1
        let initial = JVMValue(slot: slot, type: coroutineObject); slot += 1
        let returned = JVMValue(slot: slot, type: coroutineObject)
        let fields = source.locals.map { JVMField(owner: name, name: "v" + String($0.slot), type: $0.type, access: 0) }
        let stateLabel = JVMField(owner: name, name: "label", type: .int, access: 0)
        let constructor = JVMForeignMethod(owner: name, name: "<init>", descriptor: "(Lkotlin/coroutines/Continuation;)V", parameters: [continuationType], result: state.type, isStatic: false, isInterface: false, isAbstract: false)
        let helperRef = JVMFunctionReference(name: helperName, parameters: [state.type, coroutineObject], result: coroutineObject, owner: owner, ownerIsInterface: ownerIsInterface)
        wrapper.locals = parameters + [completion, state, initial, returned]
        wrapper.parameterCount = parameters.count + 1
        wrapper.handlers = []
        wrapper.instructions = [.allocate(name, state), .foreignCall(constructor, receiver: state, arguments: [completion], result: nil)]
        for (parameter, field) in zip(parameters, fields) { wrapper.instructions.append(.putField(field, state, parameter)) }
        wrapper.instructions += [.constant(.null, initial), .call(helperRef, [state, initial], returned), .returnValue(returned)]

        let frame = JVMValue(slot: 0, type: state.type), result = JVMValue(slot: 1, type: coroutineObject)
        let mapped = source.locals.map { JVMValue(slot: $0.slot + 2, type: $0.type) }
        let values = Dictionary(uniqueKeysWithValues: zip(source.locals.map(\.slot), mapped))
        var locals = [frame, result] + mapped
        var nextSlot = (mapped.last.map { $0.slot + $0.type.width } ?? 2)
        func value(_ type: JVMValueType) -> JVMValue { let v = JVMValue(slot: nextSlot, type: type); nextSlot += type.width; locals.append(v); return v }
        var nextLabel = source.instructions.compactMap(\.labelNumber).max().map { $0 + 1 } ?? 0
        func label() -> Int { defer { nextLabel += 1 }; return nextLabel }
        let entry = label(), invalid = label()
        let points = source.instructions.filter(\.isSuspension).map { _ in label() }
        let index = value(.int), expected = value(.int), check = value(.boolean), raw = value(coroutineObject), marker = value(coroutineObject)
        var code: [JVMInstruction] = []
        for (local, field) in zip(mapped, fields) { code.append(.getField(field, frame, local)) }
        code.append(.getField(stateLabel, frame, index))
        for (n, target) in ([entry] + points).enumerated() {
            let next = label()
            code += [.constant(.int(Int32(n)), expected), .binary(.equal, index, expected, check), .jumpIfFalse(check, next), .jump(target), .label(next)]
        }
        code += [.jump(invalid), .label(entry)]
        let throwFailure = JVMForeignMethod(owner: "kotlin/ResultKt", name: "throwOnFailure", descriptor: "(Ljava/lang/Object;)V", parameters: [coroutineObject], result: .unit, isStatic: true, isInterface: false, isAbstract: false)
        code.append(.foreignCall(throwFailure, receiver: nil, arguments: [result], result: nil))
        var point = 0, allocations: Set<Int> = []
        for instruction in source.instructions {
            let instruction = instruction.mappingValues { values[$0.slot]! }
            if case let .allocate(_, object) = instruction { allocations.insert(object.slot) }
            if case let .foreignCall(method, object, _, _) = instruction, method.isConstructor, let object { allocations.remove(object.slot) }
            if case let .abandonAllocations(objects) = instruction { for object in objects { allocations.remove(object.slot) } }
            if instruction.isSuspension {
                guard allocations.isEmpty else { throw JVMFrontendError(message: "JVM suspension inside an uninitialized constructor argument is unsupported.") }
                for (local, field) in zip(mapped, fields) { code.append(.putField(field, frame, local)) }
                code += [.constant(.int(Int32(point + 1)), expected), .putField(stateLabel, frame, expected)]
                let destination: JVMValue?
                let representation: JVMSuspendValueResult?
                switch instruction {
                case let .call(ref, _, _): representation = valueResults[(ref.owner ?? owner) + "." + ref.name + ref.descriptor] ?? valueResults[(ref.owner ?? owner) + "." + ref.name + ref.suspendABI.descriptor]
                case let .foreignCall(method, _, _, _): representation = valueResults[method.owner + "." + method.name + method.descriptor]
                default: representation = nil
                }
                switch instruction {
                case let .call(ref, arguments, output): code.append(.call(ref.suspendABI, Array(arguments.dropLast(ref.suspendDefaultMasks == 0 ? 0 : ref.suspendDefaultMasks + 1)) + [frame] + (ref.suspendDefaultMasks == 0 ? [] : Array(arguments.suffix(ref.suspendDefaultMasks + 1))), raw)); destination = output
                case let .foreignCall(method, receiver, arguments, output): code.append(.foreignCall(method.suspendABI, receiver: receiver, arguments: arguments + [frame], result: raw)); destination = output
                default: preconditionFailure("Expected suspension call")
                }
                let getMarker = JVMForeignMethod(owner: "kotlin/coroutines/intrinsics/IntrinsicsKt", name: "getCOROUTINE_SUSPENDED", descriptor: "()Ljava/lang/Object;", parameters: [], result: coroutineObject, isStatic: true, isInterface: false, isAbstract: false)
                let suspended = label()
                code += [.foreignCall(getMarker, receiver: nil, arguments: [], result: marker), .referenceCompare(.notEqual, raw, marker, check), .jumpIfFalse(check, suspended)]
                // Both synchronous completion and resume enter the same result check.
                if let representation {
                    let done = label(), nonnull = label()
                    if representation.boxed.isNullable {
                        let null = value(coroutineObject)
                        code += [.constant(.null, null), .referenceCompare(.notEqual, raw, null, check), .jumpIfFalse(check, done), .label(nonnull)]
                    }
                    let underlying = value(representation.underlying)
                    let box = JVMForeignMethod(owner: representation.boxed.referenceName!, name: "box-impl", descriptor: "(" + representation.underlying.descriptor + ")" + representation.boxed.descriptor, parameters: [representation.underlying], result: representation.boxed, isStatic: true, isInterface: false, isAbstract: false)
                    code += [.copy(raw, underlying), .foreignCall(box, receiver: nil, arguments: [underlying], result: raw), .label(done)]
                }
                code += [.copy(raw, result), .jump(points[point]), .label(suspended), .returnValue(raw), .label(points[point]), .foreignCall(throwFailure, receiver: nil, arguments: [result], result: nil)]
                if let destination { code.append(.copy(result, destination)) }
                point += 1
            } else if case let .returnValue(value) = instruction {
                code += [.constant(.int(-1), expected), .putField(stateLabel, frame, expected)]
                if let value { code.append(.copy(value, raw)) }
                else { code.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: .reference("kotlin/Unit", nullable: false), access: 0x19), raw)) }
                code.append(.returnValue(raw))
            } else { code.append(instruction) }
        }
        let failure = value(.reference("java/lang/IllegalStateException", nullable: false)), message = value(.string)
        let errorCtor = JVMForeignMethod(owner: "java/lang/IllegalStateException", name: "<init>", descriptor: "(Ljava/lang/String;)V", parameters: [.string], result: failure.type, isStatic: false, isInterface: false, isAbstract: false)
        code += [.label(invalid), .constant(.string("Coroutine has already completed"), message), .allocate(errorCtor.owner, failure), .foreignCall(errorCtor, receiver: failure, arguments: [message], result: nil), .throwValue(failure)]
        var worker = rawFunction(owner, name: helperName, parameters: helperRef.parameters, result: coroutineObject, access: ownerIsInterface ? 0x1009 : 0x1008, locals: locals, instructions: code)
        worker.handlers = source.handlers

        let own = JVMValue(slot: 0, type: state.type), parent = JVMValue(slot: 1, type: continuationType)
        let superCtor = JVMForeignMethod(owner: "kotlin/coroutines/jvm/internal/ContinuationImpl", name: "<init>", descriptor: "(Lkotlin/coroutines/Continuation;)V", parameters: [continuationType], result: .reference("kotlin/coroutines/jvm/internal/ContinuationImpl", nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        let ctor = rawFunction(name, name: "<init>", parameters: [continuationType], result: .unit, access: 0, locals: [own, parent], instructions: [.foreignCall(superCtor, receiver: own, arguments: [parent], result: nil), .returnValue(nil)], constructor: true)
        let incoming = JVMValue(slot: 1, type: coroutineObject), output = JVMValue(slot: 2, type: coroutineObject)
        let resume = rawFunction(name, name: "invokeSuspend", parameters: [coroutineObject], result: coroutineObject, access: 0x14, locals: [own, incoming, output], instructions: [.call(helperRef, [own, incoming], output), .returnValue(output)])
        var stateClass = JVMClass(name: name, superclass: superCtor.owner, interfaces: [], access: 0x1030, functions: [ctor, resume], properties: [])
        stateClass.extraFields = fields + [stateLabel]; stateClass.emitMetadata = false
        return (wrapper, worker, stateClass)
    }
}

extension JVMInstruction {
    var isSuspension: Bool {
        switch self { case let .call(ref, _, _): ref.isSuspend; case let .foreignCall(method, _, _, _): method.isSuspend; default: false }
    }
    var labelNumber: Int? {
        switch self {
        case let .label(n), let .regionBoundary(n), let .jump(n), let .jumpIfFalse(_, n), let .defaultArgument(_, _, n), let .exceptionHandler(n, _, _): n
        default: nil
        }
    }
    func mappingValues(_ f: (JVMValue) -> JVMValue) -> JVMInstruction {
        switch self {
        case let .constant(c, v): .constant(c, f(v))
        case let .classLiteral(name, v): .classLiteral(name, f(v))
        case let .reifiedOperation(op, name, input, result): .reifiedOperation(op, name, input.map(f), f(result))
        case let .callableSignature(owner, name, descriptor, v): .callableSignature(owner, name, descriptor, f(v))
        case let .copy(a, b): .copy(f(a), f(b))
        case let .binary(op, a, b, c): .binary(op, f(a), f(b), f(c))
        case let .referenceCompare(op, a, b, c): .referenceCompare(op, f(a), f(b), f(c))
        case let .unary(op, a, b): .unary(op, f(a), f(b))
        case let .call(ref, args, result): .call(ref, args.map(f), result.map(f))
        case let .invokeDynamic(name, descriptor, captures, samDescriptor, implementation, instantiatedDescriptor, result):
            .invokeDynamic(name: name, descriptor: descriptor, captures: captures.map(f), samDescriptor: samDescriptor, implementation: implementation, instantiatedDescriptor: instantiatedDescriptor, result: f(result))
        case let .allocate(name, v): .allocate(name, f(v))
        case let .abandonAllocations(v): .abandonAllocations(v.map(f))
        case let .foreignCall(method, receiver, args, result): .foreignCall(method, receiver: receiver.map(f), arguments: args.map(f), result: result.map(f))
        case let .getStatic(field, v): .getStatic(field, f(v))
        case let .putStatic(field, v): .putStatic(field, f(v))
        case let .getField(field, a, b): .getField(field, f(a), f(b))
        case let .putField(field, a, b): .putField(field, f(a), f(b))
        case let .newArray(type, count, result): .newArray(type, count: f(count), result: f(result))
        case let .arrayLength(a, b): .arrayLength(f(a), f(b))
        case let .arrayGet(a, b, c): .arrayGet(f(a), f(b), f(c))
        case let .arraySet(a, b, c): .arraySet(f(a), f(b), f(c))
        case let .instanceOf(a, type, b): .instanceOf(f(a), type, f(b))
        case let .throwValue(v): .throwValue(f(v))
        case let .monitor(v, enter): .monitor(f(v), enter: enter)
        case let .exceptionHandler(n, v, preserved): .exceptionHandler(n, f(v), preserving: preserved.map(f))
        case let .print(v, newline): .print(v.map(f), newline: newline)
        case let .jumpIfFalse(v, n): .jumpIfFalse(f(v), n)
        case let .defaultArgument(v, bit, n): .defaultArgument(f(v), bit, n)
        case let .returnValue(v): .returnValue(v.map(f))
        case .label, .jump, .regionBoundary, .inlineFinallyMarker: self
        }
    }
}

// Inline ABI adapters splice a body after argument conversion labels.
extension JVMInstruction {
    func offsettingLabels(by offset: Int) -> JVMInstruction {
        switch self {
        case let .label(n): .label(n + offset)
        case let .jump(n): .jump(n + offset)
        case let .jumpIfFalse(v, n): .jumpIfFalse(v, n + offset)
        case let .regionBoundary(n): .regionBoundary(n + offset)
        case let .defaultArgument(v, bit, n): .defaultArgument(v, bit, n + offset)
        case let .exceptionHandler(n, v, preserved): .exceptionHandler(n + offset, v, preserving: preserved)
        default: self
        }
    }
}
