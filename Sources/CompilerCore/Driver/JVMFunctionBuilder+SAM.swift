/// Unwinds only the current value evaluation after a source return/throw.
/// The enclosing expression then propagates its already-emitted terminator.
struct JVMTerminatedExpression: Error {}

extension JVMFunctionBuilder {
    func expression(_ id: ExprID, discarded: Bool = false) throws -> JVMValue? {
        if let operand = evaluatedOperands[id] { return operand }
        let pendingConstructor = !pendingAllocations.isEmpty, start = instructions.count
        var result: JVMValue?
        do { result = try rawExpression(id, discarded: discarded) }
        catch is JVMTerminatedExpression { return nil }
        if pendingConstructor, instructions.dropFirst(start).contains(where: \.isSuspension) {
            throw fail("JVM suspension inside an uninitialized constructor argument is unsupported.", id)
        }
        if !terminated, let logicalType = program.sema.bindings.exprType(for: id),
           case .nothing(.nonNull) = program.sema.types.kind(of: logicalType) {
            // A Nothing-valued call has no normal source edge, even when its
            // Void descriptor or an inline join appears to return a value.
            let unreachable = try constructJDK("kotlin/KotlinNothingValueException", parameters: [], arguments: [])
            instructions.append(.throwValue(unreachable)); terminated = true
            return nil
        }
        if result == nil, !discarded, !terminated,
           let logicalType = program.sema.bindings.exprType(for: id),
           case .unit = program.sema.types.kind(of: logicalType) {
            // A void-producing Unit expression still has a value when its
            // surrounding expression expects an object, such as a lambda result.
            program.functionArities.insert(0)
            let unit: JVMValueType = .reference("kotlin/Unit", nullable: false)
            let boxed = try value(unit)
            instructions.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: unit, access: 0x19), boxed))
            result = boxed
        }
        let target = program.sema.bindings.samInterfaceType(for: id) ?? (program.sema.bindings.samUnderlyingFunctionType(for: id) != nil ? program.sema.bindings.exprType(for: id) : nil)
        guard !terminated, let result, let target, case .classType = program.sema.types.kind(of: target) else { return result }
        return try adaptSAM(result, target: target, at: id)
    }

    func adaptSAM(_ function: JVMValue, target: TypeID, at id: ExprID) throws -> JVMValue {
        let type = try program.type(target)
        if function.type.referenceName == type.referenceName { return function }
        guard case let .classType(t) = program.sema.types.kind(of: target),
              let methodID = TypeCheckHelpers().effectiveSamAbstractMethod(for: t.classSymbol, symbols: program.sema.symbols),
              let method = program.methods[methodID] ?? context.jvmImports?.methods[methodID],
              !method.isStatic, !method.isConstructor else { throw fail("JVM SAM conversion requires one supported abstract method.", id) }
        let name = (owner?.name ?? program.facadeName) + "$SAM" + String(program.nextClosure)
        program.nextClosure += 1
        let immediateSuspend = method.isSuspend && function.type.referenceName == "kotlin/jvm/functions/Function" + String(method.parameters.count)
        // The wrapper must implement the erased runtime interface: bundled
        // declarations like `kotlin.Comparator` erase to a mapped JDK name
        // (java/util/Comparator) rather than their source binary name.
        let interfaceName: String
        if let erased = type.referenceName { interfaceName = erased }
        else { interfaceName = try program.className(t.classSymbol) }
        program.closureClasses.append(program.samClass(name, target: interfaceName, method: method, immediateSuspend: immediateSuspend))
        let nullableResult = type.isNullable && function.type.isNullable ? try value(type) : nil
        let nullCase = label(), end = label()
        if nullableResult != nil {
            // A null function converts to a null nullable SAM, without
            // constructing an adapter or asserting that the function exists.
            let null = try constant(.null, .reference("java/lang/Object", nullable: true)), present = try value(.boolean)
            instructions.append(.referenceCompare(.notEqual, function, null, present))
            instructions.append(.jumpIfFalse(present, nullCase))
        }
        let object = try value(.reference(name, nullable: false))
        let callable = try convert(function, to: .reference("kotlin/jvm/functions/Function" + String(method.parameters.count + (method.isSuspend && !immediateSuspend ? 1 : 0)), nullable: false))
        instructions.append(.allocate(name, object))
        let ctor = JVMForeignMethod(owner: name, name: "<init>", descriptor: "(" + callable.type.descriptor + ")V", parameters: [callable.type], result: object.type, isStatic: false, isInterface: false, isAbstract: false)
        instructions.append(.foreignCall(ctor, receiver: object, arguments: [callable], result: nil))
        if let nullableResult {
            instructions.append(.copy(try convert(object, to: type), nullableResult)); jump(end)
            mark(nullCase); instructions.append(.constant(.null, nullableResult)); mark(end)
            return nullableResult
        }
        return try convert(object, to: type)
    }
}

extension JVMProgramBuilder {
    func samClass(_ name: String, target: String, method: JVMForeignMethod, immediateSuspend: Bool = false) -> JVMClass {
        let method = method.isSuspend ? method.suspendABI : method
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let selfValue = JVMValue(slot: 0, type: .reference(name, nullable: false))
        let arity = method.parameters.count - (immediateSuspend ? 1 : 0)
        let callableType: JVMValueType = .reference("kotlin/jvm/functions/Function" + String(arity), nullable: false)
        functionArities.insert(arity)
        let field = JVMField(owner: name, name: "function", type: callableType, access: 0x12)
        let callback = JVMValue(slot: 1, type: callableType)
        let ctor = rawFunction(name, name: "<init>", parameters: [callableType], result: .unit, access: 1, locals: [selfValue, callback], instructions: [.foreignCall(objectConstructor(), receiver: selfValue, arguments: [], result: nil), .putField(field, selfValue, callback), .returnValue(nil)], constructor: true)
        var locals = [selfValue], slot = 1
        for type in method.parameters { locals.append(JVMValue(slot: slot, type: type)); slot += type.width }
        let parameters = Array(locals.dropFirst())
        func value(_ type: JVMValueType) -> JVMValue { let v = JVMValue(slot: slot, type: type); slot += type.width; locals.append(v); return v }
        let function = value(callableType)
        var code: [JVMInstruction] = [.getField(field, selfValue, function)], args: [JVMValue] = []
        // A non-suspending function value completes synchronously and ignores
        // the SAM's continuation. Its erased return already follows Result ABI.
        for parameter in parameters.prefix(arity) { let boxed = value(object); code.append(.copy(parameter, boxed)); args.append(boxed) }
        let raw = value(object)
        let invoke = JVMForeignMethod(owner: callableType.referenceName!, name: "invoke", descriptor: "(" + Array(repeating: object.descriptor, count: args.count).joined() + ")" + object.descriptor, parameters: Array(repeating: object, count: args.count), result: object, isStatic: false, isInterface: true, isAbstract: true)
        code.append(.foreignCall(invoke, receiver: function, arguments: args, result: raw))
        if method.result == .unit { code.append(.returnValue(nil)) }
        else { let result = value(method.result); code += [.copy(raw, result), .returnValue(result)] }
        let implementation = rawFunction(name, name: method.name, parameters: method.parameters, result: method.result, access: 0x11, locals: locals, instructions: code)
        return rawClass(name, interfaces: [target], access: 0x1031, functions: [ctor, implementation], fields: [field])
    }
}
