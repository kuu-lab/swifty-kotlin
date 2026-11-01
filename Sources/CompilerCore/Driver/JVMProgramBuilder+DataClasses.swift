import Foundation

extension JVMProgramBuilder {
    func dataProperties(_ plan: JVMClassPlan) throws -> [JVMProperty] {
        try plan.declaration!.primaryConstructorParams.map { parameter in
            guard let property = plan.properties.first(where: { $0.2.name == context.interner.resolve(parameter.name) })?.2,
                  property.field != nil else { throw JVMFrontendError(message: "JVM data class constructor requires stored properties.") }
            return property
        }
    }
    func prepareDataMembers(_ plan: JVMClassPlan) throws {
        for symbol in sema.symbols.declaredChildren(of: plan.symbol) {
            guard let member = sema.symbols.symbol(symbol), member.kind == .function, member.flags.contains(.synthetic),
                  let signature = sema.symbols.functionSignature(for: symbol) else { continue }
            let name = context.interner.resolve(member.name)
            guard name == "copy" || name.hasPrefix("component") || ["equals", "hashCode", "toString"].contains(name) else { continue }
            let parameters = try signature.parameterTypes.map(type), result = try type(signature.returnType)
            methods[symbol] = JVMForeignMethod(owner: plan.name, name: name, descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor, parameters: parameters, result: result, isStatic: false, isInterface: false, isAbstract: false)
        }
    }

    func dataMethods(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        let props = try dataProperties(plan), type: JVMValueType = .reference(plan.name, nullable: false)
        var generated: [JVMFunction] = []
        let symbols = methods.keys.filter { methods[$0]?.owner == plan.name && sema.symbols.symbol($0)?.flags.contains(.synthetic) == true }.sorted { $0.rawValue < $1.rawValue }
        for symbol in symbols {
            let method = methods[symbol]!
            guard !existing.contains(where: { $0.reference.name == method.name && $0.reference.descriptor == method.descriptor }) else { continue }
            let b = try nominalBuilder(plan, name: method.name, parameters: method.parameters, result: method.result)
            let own = b.thisValue!
            if method.name.hasPrefix("component"), let index = Int(method.name.dropFirst(9)), props.indices.contains(index - 1) {
                let result = try b.value(props[index - 1].type)
                b.instructions += [.getField(props[index - 1].field!, own, result), .returnValue(result)]
            } else if method.name == "copy" {
                guard let ctor = plan.constructors.first(where: { $0.2 }).flatMap({ methods[$0.0] }) else { throw JVMFrontendError(message: "Missing JVM data constructor.") }
                let result = try b.value(type)
                b.instructions += [.allocate(plan.name, result), .foreignCall(ctor, receiver: result, arguments: Array(b.locals.prefix(b.reference.parameters.count + 1).dropFirst()), result: nil), .returnValue(result)]
            } else if method.name == "equals" {
                let other = b.locals[1], yes = b.label(), no = b.label(), check = try b.value(.boolean)
                b.instructions += [.referenceCompare(.equal, own, other, check), .jumpIfFalse(check, no), .constant(.boolean(true), check), .returnValue(check)]
                b.mark(no)
                let unequal = b.label()
                b.instructions += [.instanceOf(other, plan.name, check), .jumpIfFalse(check, unequal)]
                let cast = try b.convert(other, to: type)
                for property in props {
                    let a = try b.value(property.type), c = try b.value(property.type)
                    b.instructions += [.getField(property.field!, own, a), .getField(property.field!, cast, c)]
                    if property.type == .float || property.type == .double {
                        let owner = property.type == .float ? "java/lang/Float" : "java/lang/Double"
                        let compare = try b.jdkCall(owner, "compare", [property.type, property.type], .int, arguments: [a, c])!
                        b.instructions.append(.binary(.equal, compare, try b.constant(.int(0), .int), check))
                    } else { b.instructions.append(.binary(.equal, a, c, check)) }
                    b.instructions.append(.jumpIfFalse(check, unequal))
                }
                b.jump(yes); b.mark(unequal)
                b.instructions += [.constant(.boolean(false), check), .returnValue(check)]
                b.mark(yes); b.instructions += [.constant(.boolean(true), check), .returnValue(check)]
            } else if method.name == "hashCode" {
                let result = try b.constant(.int(0), .int), factor = try b.constant(.int(31), .int)
                for property in props {
                    let field = try b.value(property.type); b.instructions.append(.getField(property.field!, own, field))
                    let hash: JVMValue
                    if property.type.referenceName?.hasPrefix("[") == true {
                        let array = property.type.referenceName!, parameter = array.dropFirst().first == "L" || array.hasPrefix("[[") ? JVMValueType.reference("[Ljava/lang/Object;", nullable: true) : property.type
                        hash = try b.jdkCall("java/util/Arrays", "hashCode", [parameter], .int, arguments: [field])!
                    } else if let wrapper = JVMClasspathIndex.boxed(property.type).referenceName, property.type.referenceName == nil {
                        hash = try b.jdkCall(wrapper, property.type.unsignedName == nil ? "hashCode" : "hashCode-impl", [property.type], .int, arguments: [field])!
                    } else { hash = try b.jdkCall("java/util/Objects", "hashCode", [.reference("java/lang/Object", nullable: true)], .int, arguments: [field])! }
                    b.instructions += [.binary(.multiply, result, factor, result), .binary(.add, result, hash, result)]
                }
                b.instructions.append(.returnValue(result))
            } else if method.name == "toString" {
                let text = try b.constructJDK("java/lang/StringBuilder")
                func append(_ value: JVMValue) throws {
                    _ = try b.jdkCall("java/lang/StringBuilder", "append", [value.type.stringParameter], text.type, receiver: text, arguments: [value])
                }
                let displayName = context.options.stdlibOnly ? String(plan.name.split(separator: "/").last!.split(separator: "$", omittingEmptySubsequences: false).last!) : context.interner.resolve(plan.declaration!.name)
                try append(b.constant(.string(displayName + "("), .string))
                for (i, property) in props.enumerated() {
                    try append(b.constant(.string((i == 0 ? "" : ", ") + property.name + "="), .string))
                    let field = try b.value(property.type); b.instructions.append(.getField(property.field!, own, field))
                    if let name = property.type.referenceName, property.type.unsignedName == nil, name.hasPrefix("[") {
                        let array = name.dropFirst().first == "L" || name.hasPrefix("[[") ? JVMValueType.reference("[Ljava/lang/Object;", nullable: true) : property.type
                        try append(b.jdkCall("java/util/Arrays", "toString", [array], .string, arguments: [field])!)
                    } else { try append(field) }
                }
                try append(b.constant(.string(")"), .string))
                b.instructions.append(.returnValue(try b.jdkCall("java/lang/StringBuilder", "toString", [], .string, receiver: text)))
            } else { continue }
            var f = b.finish(); f.access = access(plan.declaration!.modifiers, final: true)
            let visibility = sema.symbols.symbol(symbol)!.visibility
            f.isPrivate = visibility == .private; f.isInternal = visibility == .internal
            f.access = (visibility == .private ? 2 : (visibility == .protected ? 4 : 1)) | 16
            f.isSynthetic = false; f.isOperator = method.name.hasPrefix("component")
            let signature = sema.symbols.functionSignature(for: symbol)!
            f.kotlinParameters = try signature.parameterTypes.map(kotlinType); f.kotlinResult = try kotlinType(signature.returnType)
            f.parameterNames = method.name == "copy" ? props.map(\.name) : method.parameters.indices.map { "p\($0)" }
            if method.name == "copy" { f.parameterDefaultFlags = Array(repeating: true, count: props.count) }
            f.genericSignature = "(" + (try signature.parameterTypes.map { try signatureType($0, parameterPosition: true) }).joined() + ")" + (try signatureType(signature.returnType))
            generated.append(f)
        }
        if let copy = generated.first(where: { $0.reference.name == "copy" }) { generated.append(try dataCopyDefault(plan, copy: copy, properties: props)) }
        return generated
    }

    func dataCopyDefault(_ plan: JVMClassPlan, copy: JVMFunction, properties: [JVMProperty]) throws -> JVMFunction {
        let type = JVMValueType.reference(plan.name, nullable: false), masks = (properties.count + 31) / 32
        let parameters = [type] + copy.reference.parameters + Array(repeating: JVMValueType.int, count: masks) + [.reference("java/lang/Object", nullable: true)]
        guard parameters.reduce(0, { $0 + $1.width }) <= 255 else { throw JVMFrontendError(message: "JVM data copy default parameter limit exceeded.") }
        let b = try nominalBuilder(plan, name: "copy$default", parameters: parameters, result: type, staticBody: true)
        let original = Array(b.locals), receiver = original[0]
        var arguments: [JVMValue] = []
        for (i, property) in properties.enumerated() {
            let result = try b.value(property.type), check = try b.value(.int), provided = b.label(), end = b.label()
            let mask = original[1 + properties.count + i / 32], bit = try b.constant(.int(Int32(bitPattern: UInt32(1) << UInt32(i % 32))), .int)
            b.instructions += [.binary(.bitwiseAnd, mask, bit, check), .binary(.equal, check, try b.constant(.int(0), .int), check), .jumpIfFalse(check, provided), .copy(original[1 + i], result)]
            b.jump(end); b.mark(provided); b.instructions.append(.getField(property.field!, receiver, result)); b.mark(end)
            arguments.append(result)
        }
        let result = try b.jdkCall(plan.name, "copy", copy.reference.parameters, type, receiver: receiver, arguments: arguments)!
        b.instructions.append(.returnValue(result))
        var f = b.finish(); f.access = 0x1009; f.checksParameters = false; return f
    }

    func sealedConstructors(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        let marker = JVMValueType.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)
        return existing.filter(\.isConstructor).map { ctor in
            let own = JVMValue(slot: 0, type: .reference(plan.name, nullable: false))
            var slot = 1, locals = [own]
            for type in ctor.reference.parameters + [marker] { locals.append(JVMValue(slot: slot, type: type)); slot += type.width }
            let method = JVMForeignMethod(owner: plan.name, name: "<init>", descriptor: ctor.reference.descriptor, parameters: ctor.reference.parameters, result: own.type, isStatic: false, isInterface: false, isAbstract: false)
            return rawFunction(plan.name, name: "<init>", parameters: ctor.reference.parameters + [marker], result: .unit, access: 0x1001, locals: locals, instructions: [.foreignCall(method, receiver: own, arguments: Array(locals.dropFirst().dropLast()), result: nil), .returnValue(nil)], constructor: true)
        }
    }
}
