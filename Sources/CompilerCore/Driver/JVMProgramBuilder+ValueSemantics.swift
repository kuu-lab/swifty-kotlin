import Foundation

extension JVMProgramBuilder {
    func valueSemantics(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        guard let property = plan.properties.first(where: { $0.2.name == context.interner.resolve(plan.declaration!.primaryConstructorParams[0].name) })?.2, let field = property.field else { throw JVMFrontendError(message: "Missing JVM value-class storage.") }
        var functions: [JVMFunction] = []
        let ownType: JVMValueType = .reference(plan.name, nullable: false), any: JVMValueType = .reference("java/lang/Object", nullable: true)
        for name in ["equals", "hashCode", "toString"] where !existing.contains(where: { $0.reference.name == name && !$0.isSynthetic }) {
            let b = try nominalBuilder(plan, name: name, parameters: name == "equals" ? [any] : [], result: name == "equals" ? .boolean : (name == "hashCode" ? .int : .string))
            let own = b.thisValue!, stored = try b.value(field.type)
            b.instructions.append(.getField(field, own, stored))
            if name == "equals" {
                let check = try b.value(.boolean), no = b.label(), other = b.locals[1]
                b.instructions += [.instanceOf(other, plan.name, check), .jumpIfFalse(check, no)]
                let cast = try b.convert(other, to: ownType), right = try b.value(field.type)
                b.instructions.append(.getField(field, cast, right))
                if field.type == .float || field.type == .double {
                    let comparison = try b.jdkCall(field.type == .float ? "java/lang/Float" : "java/lang/Double", "compare", [field.type, field.type], .int, arguments: [stored, right])!
                    b.instructions.append(.binary(.equal, comparison, try b.constant(.int(0), .int), check))
                } else { b.instructions.append(.binary(.equal, stored, right, check)) }
                b.instructions.append(.returnValue(check)); b.mark(no)
                b.instructions += [.constant(.boolean(false), check), .returnValue(check)]
            } else if name == "hashCode" {
                let hash: JVMValue
                if let name = field.type.referenceName, name.hasPrefix("[") {
                    let parameter = name.dropFirst().first == "L" || name.hasPrefix("[[") ? JVMValueType.reference("[Ljava/lang/Object;", nullable: true) : field.type
                    hash = try b.jdkCall("java/util/Arrays", "hashCode", [parameter], .int, arguments: [stored])!
                } else if field.type.referenceName == nil {
                    hash = try b.jdkCall(JVMClasspathIndex.boxed(field.type).referenceName!, field.type.unsignedName == nil ? "hashCode" : "hashCode-impl", [field.type], .int, arguments: [stored])!
                } else { hash = try b.jdkCall("java/util/Objects", "hashCode", [any], .int, arguments: [stored])! }
                b.instructions.append(.returnValue(hash))
            } else {
                let text = try b.constructJDK("java/lang/StringBuilder")
                let displayName = context.options.stdlibOnly ? String(plan.name.split(separator: "/").last!.split(separator: "$", omittingEmptySubsequences: false).last!) : context.interner.resolve(plan.declaration!.name)
                let prefix = displayName + "(" + field.name + "="
                _ = try b.jdkCall("java/lang/StringBuilder", "append", [.string], text.type, receiver: text, arguments: [b.constant(.string(prefix), .string)])
                if let name = field.type.referenceName, field.type.unsignedName == nil, name.hasPrefix("[") {
                    let parameter = name.dropFirst().first == "L" || name.hasPrefix("[[") ? JVMValueType.reference("[Ljava/lang/Object;", nullable: true) : field.type
                    let rendered = try b.jdkCall("java/util/Arrays", "toString", [parameter], .string, arguments: [stored])!
                    _ = try b.jdkCall("java/lang/StringBuilder", "append", [.string], text.type, receiver: text, arguments: [rendered])
                } else {
                    _ = try b.jdkCall("java/lang/StringBuilder", "append", [field.type.stringParameter], text.type, receiver: text, arguments: [stored])
                }
                _ = try b.jdkCall("java/lang/StringBuilder", "append", [.string], text.type, receiver: text, arguments: [b.constant(.string(")"), .string)])
                b.instructions.append(.returnValue(try b.jdkCall("java/lang/StringBuilder", "toString", [], .string, receiver: text)))
            }
            var f = b.finish(); f.access = 0x11; f.isSynthetic = false
            f.kotlinParameters = name == "equals" ? [.named("kotlin/Any", [], nullable: true)] : []
            f.kotlinResult = .named("kotlin/" + (name == "equals" ? "Boolean" : (name == "hashCode" ? "Int" : "String")), [], nullable: false)
            f.parameterNames = name == "equals" ? ["other"] : []
            f.isOperator = name == "equals"; functions.append(f)
        }
        return functions
    }
}
