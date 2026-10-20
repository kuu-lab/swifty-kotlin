extension JVMProgramBuilder {
    /// Java 8 has no nestmates. Keep private declarations private while giving
    /// generated nested classes synthetic access paths in their owning class.
    func lowerNominalAccess(_ input: JVMProgram) throws -> JVMProgram {
        var program = input, additions: [String: [JVMFunction]] = [:], bridges: [String: JVMFunctionReference] = [:]
        let all = [program.internalClassName: program.functions].merging(Dictionary(uniqueKeysWithValues: program.classes.map { ($0.name, $0.functions) }), uniquingKeysWith: { $1 })
        func privateFunction(_ owner: String, _ name: String, _ descriptor: String) -> JVMFunction? {
            all[owner]?.first { $0.reference.name == name && $0.reference.descriptor == descriptor && ($0.isPrivate || ($0.access ?? 0) & 2 != 0) }
        }
        func accessor(_ method: JVMForeignMethod) throws -> JVMFunctionReference {
            let key = method.owner + method.name + method.descriptor
            if let old = bridges[key] { return old }
            let params = (method.isStatic ? [] : [JVMValueType.reference(method.owner, nullable: false)]) + method.parameters
            guard params.reduce(0, { $0 + $1.width }) <= 255 else { throw JVMFrontendError(message: "JVM synthetic private access exceeds the parameter slot limit.") }
            var slot = 0, locals: [JVMValue] = []
            for type in params { locals.append(JVMValue(slot: slot, type: type)); slot += type.width }
            let result = method.result == .unit ? nil : JVMValue(slot: slot, type: method.result)
            let receiver = method.isStatic ? nil : locals[0], args = method.isStatic ? locals : Array(locals.dropFirst())
            if let result { locals.append(result) }
            let name = "$access" + String(bridges.count)
            let interface = program.classes.first { $0.name == method.owner }?.isInterface == true
            let ref = JVMFunctionReference(name: name, parameters: params, result: method.result, owner: method.owner, ownerIsInterface: interface, isSuspend: method.isSuspend)
            var target = method; target.isSpecial = !method.isStatic
            var f = rawFunction(method.owner, name: name, parameters: params, result: method.result, access: 0x1009, locals: locals, instructions: [.foreignCall(target, receiver: receiver, arguments: args, result: result), .returnValue(result)])
            f.isSuspend = method.isSuspend
            additions[method.owner, default: []].append(f); bridges[key] = ref
            return ref
        }
        func fieldAccessor(_ field: JVMField, setter: Bool) -> JVMFunctionReference {
            let key = field.owner + "." + field.name + (setter ? "$set" : "$get")
            if let old = bridges[key] { return old }
            let isStatic = field.access & 8 != 0
            let object = JVMValue(slot: 0, type: .reference(field.owner, nullable: false)), value = JVMValue(slot: isStatic ? 0 : 1, type: field.type)
            let name = "$access" + String(bridges.count), params = (isStatic ? [] : [object.type]) + (setter ? [field.type] : []), result: JVMValueType = setter ? .unit : field.type
            let instructions: [JVMInstruction] = setter ? [isStatic ? .putStatic(field, value) : .putField(field, object, value), .returnValue(nil)] : [isStatic ? .getStatic(field, value) : .getField(field, object, value), .returnValue(value)]
            let ref = JVMFunctionReference(name: name, parameters: params, result: result, owner: field.owner)
            additions[field.owner, default: []].append(rawFunction(field.owner, name: name, parameters: params, result: result, access: 0x1009, locals: (isStatic ? [] : [object]) + [value], instructions: instructions))
            bridges[key] = ref; return ref
        }
        func transform(_ source: JVMFunction, owner: String) throws -> JVMFunction {
            var function = source, code: [JVMInstruction] = []
            for instruction in source.instructions {
                switch instruction {
                case let .getStatic(field, value) where field.owner != owner && field.access & 2 != 0:
                    code.append(.call(fieldAccessor(field, setter: false), [], value))
                case let .putStatic(field, value) where field.owner != owner && field.access & 2 != 0:
                    code.append(.call(fieldAccessor(field, setter: true), [value], nil))
                case let .getField(field, object, value) where field.owner != owner && field.access & 2 != 0:
                    code.append(.call(fieldAccessor(field, setter: false), [object], value))
                case let .putField(field, object, value) where field.owner != owner && field.access & 2 != 0:
                    code.append(.call(fieldAccessor(field, setter: true), [object, value], nil))
                case let .foreignCall(method, receiver, arguments, result) where method.owner != owner && privateFunction(method.owner, method.name, method.descriptor) != nil:
                    if method.isConstructor {
                        let marker: JVMValueType = .reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)
                        let key = method.owner + method.name + method.descriptor
                        let params = method.parameters + [marker]
                        guard params.reduce(1, { $0 + $1.width }) <= 255 else { throw JVMFrontendError(message: "JVM private constructor access exceeds the parameter slot limit.") }
                        if bridges[key] == nil {
                            let own = JVMValue(slot: 0, type: .reference(method.owner, nullable: false))
                            var slot = 1, locals = [own]
                            for type in params { locals.append(JVMValue(slot: slot, type: type)); slot += type.width }
                            let bridge = rawFunction(method.owner, name: "<init>", parameters: params, result: .unit, access: 0x1001, locals: locals, instructions: [.foreignCall(method, receiver: own, arguments: Array(locals.dropFirst().dropLast()), result: nil), .returnValue(nil)], constructor: true)
                            additions[method.owner, default: []].append(bridge)
                            bridges[key] = bridge.reference
                        }
                        let null = JVMValue(slot: function.locals.last.map { $0.slot + $0.type.width } ?? 0, type: marker)
                        function.locals.append(null); code.append(.constant(.null, null))
                        let target = JVMForeignMethod(owner: method.owner, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: method.result, isStatic: false, isInterface: false, isAbstract: false)
                        code.append(.foreignCall(target, receiver: receiver, arguments: arguments + [null], result: result))
                    } else { code.append(.call(try accessor(method), (receiver.map { [$0] } ?? []) + arguments, result)) }
                case let .call(ref, args, result) where (ref.owner ?? owner) != owner && privateFunction(ref.owner ?? owner, ref.name, ref.descriptor) != nil:
                    var method = JVMForeignMethod(owner: ref.owner!, name: ref.name, descriptor: ref.descriptor, parameters: ref.parameters, result: ref.result, isStatic: true, isInterface: ref.ownerIsInterface, isAbstract: false)
                    method.isSuspend = ref.isSuspend
                    code.append(.call(try accessor(method), args, result))
                default: code.append(instruction)
                }
            }
            function.instructions = code; return function
        }
        program.functions = try program.functions.map { try transform($0, owner: program.internalClassName) }
        for i in program.classes.indices { program.classes[i].functions = try program.classes[i].functions.map { try transform($0, owner: program.classes[i].name) } }
        program.functions += additions[program.internalClassName] ?? []
        for i in program.classes.indices {
            for function in additions[program.classes[i].name] ?? [] where !program.classes[i].functions.contains(where: { $0.reference.name == function.reference.name && $0.reference.descriptor == function.reference.descriptor }) { program.classes[i].functions.append(function) }
        }
        if all.values.joined().contains(where: { $0.reference.parameters.contains(where: { $0.referenceName == "kotlin/jvm/internal/DefaultConstructorMarker" }) }) || classes.values.contains(where: { $0.modifiers.contains(.sealed) }) || !bridges.isEmpty || classes.values.contains(where: { $0.constructors.contains(where: { $0.1.valueParams.contains(where: \.hasDefaultValue) }) }) {
            if program.classes.contains(where: { $0.name == "kotlin/jvm/internal/DefaultConstructorMarker" }) {
                guard context.options.stdlibOnly else { throw JVMFrontendError(message: "Generated JVM constructor marker clashes with a source class.") }
            } else if context.jvmImports?.classes["kotlin/jvm/internal/DefaultConstructorMarker"] == nil {
                program.classes.append(rawClass("kotlin/jvm/internal/DefaultConstructorMarker", access: 0x31))
            }
        }
        return program
    }
}
