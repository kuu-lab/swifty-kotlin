/// Small ABI-compatible function interfaces keep JVM output self-contained.
/// Their binary names and erased invoke signatures match kotlin-stdlib.
extension JVMProgramBuilder {
    func rawFunction(_ owner: String, name: String, parameters: [JVMValueType], result: JVMValueType, access: UInt16, locals: [JVMValue], instructions: [JVMInstruction], constructor: Bool = false) -> JVMFunction {
        var function = JVMFunction(reference: JVMFunctionReference(name: name, parameters: parameters, result: result), isPrivate: access & 2 != 0, locals: locals, parameterCount: parameters.count + (access & 8 == 0 ? 1 : 0), instructions: instructions, parameterNames: parameters.indices.map { "p\($0)" }, isInternal: false)
        function.owner = owner; function.access = access; function.isConstructor = constructor; function.isAbstract = access & 0x0400 != 0; function.isSynthetic = true
        return function
    }
    func rawClass(_ name: String, superclass: String = "java/lang/Object", interfaces: [String] = [], access: UInt16 = 0x1030, functions: [JVMFunction] = [], fields: [JVMField] = []) -> JVMClass {
        var type = JVMClass(name: name, superclass: superclass, interfaces: interfaces, access: access, functions: functions, properties: [])
        type.extraFields = fields; type.emitMetadata = false; return type
    }
    func objectConstructor() -> JVMForeignMethod {
        JVMForeignMethod(owner: "java/lang/Object", name: "<init>", descriptor: "()V", parameters: [], result: .reference("java/lang/Object", nullable: false), isStatic: false, isInterface: false, isAbstract: false)
    }
    func closureClass(_ name: String, captures: [(String, JVMValueType)], inputs: [JVMValueType], result: JVMValueType, helper: JVMFunctionReference, suspend: Bool = false, superclass: String = "java/lang/Object") throws -> JVMClass {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let receiver = JVMValue(slot: 0, type: .reference(name, nullable: false))
        var constructorLocals = [receiver], slot = 1
        var constructorCode: [JVMInstruction] = [.foreignCall(objectConstructor(), receiver: receiver, arguments: [], result: nil)]
        let fields = captures.map { JVMField(owner: name, name: $0.0, type: $0.1, access: 0x0012) }
        for field in fields {
            let parameter = JVMValue(slot: slot, type: field.type); slot += field.type.width; constructorLocals.append(parameter)
            constructorCode.append(.putField(field, receiver, parameter))
        }
        constructorCode.append(.returnValue(nil))
        let constructor = rawFunction(name, name: "<init>", parameters: captures.map { $0.1 }, result: .unit, access: 1, locals: constructorLocals, instructions: constructorCode, constructor: true)
        let inputs = inputs + (suspend ? [JVMValueType.reference("kotlin/coroutines/Continuation", nullable: false)] : [])
        var locals = [receiver], code: [JVMInstruction] = [], args: [JVMValue] = []
        for i in inputs.indices { locals.append(JVMValue(slot: i + 1, type: object)) }
        slot = inputs.count + 1
        func value(_ type: JVMValueType) -> JVMValue { let v = JVMValue(slot: slot, type: type); slot += type.width; locals.append(v); return v }
        for field in fields { let v = value(field.type); code.append(.getField(field, receiver, v)); args.append(v) }
        for (i, type) in inputs.enumerated() { let v = value(type); code.append(.copy(locals[i + 1], v)); args.append(v) }
        let returned: JVMValue
        if suspend {
            returned = value(object)
            code.append(.call(helper.suspendABI, args, returned))
        } else if result == .unit {
            code.append(.call(helper, args, nil)); returned = value(.reference("kotlin/Unit", nullable: false))
            code.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: returned.type, access: 0x19), returned))
        } else {
            let raw = value(result); code.append(.call(helper, args, raw)); returned = value(object); code.append(.copy(raw, returned))
        }
        code.append(.returnValue(returned))
        let invoke = rawFunction(name, name: "invoke", parameters: Array(repeating: object, count: inputs.count), result: object, access: 0x11, locals: locals, instructions: code)
        return rawClass(name, superclass: superclass, interfaces: ["kotlin/jvm/functions/Function" + String(inputs.count)] + (suspend ? ["kotlin/coroutines/jvm/internal/SuspendFunction"] : []), access: 0x1031, functions: [constructor, invoke], fields: fields)
    }
    func functionRuntime() -> [JVMClass] {
        guard !functionArities.isEmpty, !context.options.stdlibOnly else { return [] }
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        var marker = rawClass("kotlin/Function", access: 0x0601)
        marker.genericSignature = "<R:Ljava/lang/Object;>Ljava/lang/Object;"
        var result = context.jvmImports?.classes[marker.name] == nil ? [marker] : []
        for arity in functionArities.sorted() {
            let name = "kotlin/jvm/functions/Function" + String(arity)
            if context.jvmImports?.classes[name] != nil { continue }
            let names = (0..<arity).map { "P\($0 + 1)" }
            var invoke = rawFunction(name, name: "invoke", parameters: Array(repeating: object, count: arity), result: object, access: 0x0401, locals: [], instructions: [])
            invoke.genericSignature = "(" + names.map { "T" + $0 + ";" }.joined() + ")TR;"
            var type = rawClass(name, interfaces: ["kotlin/Function"], access: 0x0601, functions: [invoke])
            type.genericSignature = "<" + (names + ["R"]).map { $0 + ":Ljava/lang/Object;" }.joined() + ">Ljava/lang/Object;Lkotlin/Function<TR;>;"
            result.append(type)
        }
        if context.jvmImports?.classes["kotlin/Unit"] != nil { return result }
        let name = "kotlin/Unit", unit: JVMValueType = .reference("kotlin/Unit", nullable: false)
        let receiver = JVMValue(slot: 0, type: unit), text = JVMValue(slot: 1, type: .string)
        let constructor = rawFunction(name, name: "<init>", parameters: [], result: .unit, access: 2, locals: [receiver], instructions: [.foreignCall(objectConstructor(), receiver: receiver, arguments: [], result: nil), .returnValue(nil)], constructor: true)
        let own = JVMForeignMethod(owner: name, name: "<init>", descriptor: "()V", parameters: [], result: unit, isStatic: false, isInterface: false, isAbstract: false)
        let field = JVMField(owner: name, name: "INSTANCE", type: unit, access: 0x19)
        let initializer = rawFunction(name, name: "<clinit>", parameters: [], result: .unit, access: 8, locals: [receiver], instructions: [.allocate(name, receiver), .foreignCall(own, receiver: receiver, arguments: [], result: nil), .putStatic(field, receiver), .returnValue(nil)])
        let description = rawFunction(name, name: "toString", parameters: [], result: .string, access: 0x11, locals: [receiver, text], instructions: [.constant(.string("kotlin.Unit"), text), .returnValue(text)])
        var unitClass = rawClass(name, access: 0x31, functions: [constructor, initializer, description], fields: [field])
        unitClass.isObject = true; unitClass.emitMetadata = true
        result.append(unitClass)
        return result
    }
}
