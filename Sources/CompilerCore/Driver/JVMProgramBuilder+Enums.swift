import Foundation

extension JVMProgramBuilder {
    func enumField(_ plan: JVMClassPlan, name: String) -> JVMField {
        JVMField(owner: plan.name, name: name, type: .reference(plan.name, nullable: false), access: 0x4019)
    }
    func enumValuesField(_ plan: JVMClassPlan) -> JVMField {
        JVMField(owner: plan.name, name: "$VALUES", type: .reference("[L" + plan.name + ";", nullable: false), access: 0x101A)
    }
    func enumEntriesField(_ plan: JVMClassPlan) -> JVMField {
        JVMField(owner: plan.name, name: "$ENTRIES", type: .reference("kotlin/enums/EnumEntries", nullable: false), access: 0x101A)
    }
    func decorateEnum(_ plan: JVMClassPlan, result: inout JVMClass) throws {
        result.enumEntries = plan.declaration!.enumEntries.map { context.interner.resolve($0.name) }
        result.extraFields += result.enumEntries.map { enumField(plan, name: $0) } + [enumValuesField(plan), enumEntriesField(plan)]
    }
    func enumMethods(_ plan: JVMClassPlan) throws -> [JVMFunction] {
        let type = JVMValueType.reference(plan.name, nullable: false), arrayType = enumValuesField(plan).type
        let primary = plan.constructors.first { $0.2 }
        guard let primary, let constructor = methods[primary.0] else { throw JVMFrontendError(message: "Missing JVM enum primary constructor.") }
        let b = try nominalBuilder(plan, name: "<clinit>", staticBody: true)
        let entries = plan.declaration!.enumEntries
        var values: [JVMValue] = []
        for (ordinal, entry) in entries.enumerated() {
            guard entry.annotations.isEmpty else { throw JVMFrontendError(message: "JVM enum entry annotations are unsupported.", range: entry.range) }
            let name = context.interner.resolve(entry.name)
            let child = classes.values.first { $0.enumParent == plan.symbol && $0.enumEntry?.name == entry.name }
            let allocated = try b.value(.reference(child?.name ?? plan.name, nullable: false))
            b.instructions.append(.allocate(allocated.type.referenceName!, allocated))
            var args = [try b.constant(.string(name), .string), try b.constant(.int(Int32(ordinal)), .int)]
            let entrySymbol = sema.symbols.lookupAll(fqName: sema.symbols.symbol(plan.symbol)!.fqName + [entry.name]).first { sema.symbols.symbol($0)?.kind == .field }
            let binding = entrySymbol.flatMap { sema.bindings.enumEntryConstructorBinding(for: $0) }
            let ordered = try b.arguments(entry.constructorArgs, binding: binding, parameters: constructor.parameters, declarations: sourceParameters[primary.0])
            args += ordered.values
            if ordered.masks.contains(where: { $0 != 0 }) { args += try b.maskArguments(ordered.masks, constructor: true) }
            let params = args.map(\.type)
            let ctor = JVMForeignMethod(owner: allocated.type.referenceName!, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: allocated.type, isStatic: false, isInterface: false, isAbstract: false)
            b.instructions += [.foreignCall(ctor, receiver: allocated, arguments: args, result: nil), .putStatic(enumField(plan, name: name), allocated)]
            values.append(allocated)
        }
        let array = try b.value(arrayType), count = try b.constant(.int(Int32(values.count)), .int)
        b.instructions.append(.newArray(type, count: count, result: array))
        for (i, value) in values.enumerated() { b.instructions.append(.arraySet(array, try b.constant(.int(Int32(i)), .int), value)) }
        b.instructions.append(.putStatic(enumValuesField(plan), array))
        let list = try b.constructJDK(facadeName + "$EnumEntries", parameters: [.reference("[Ljava/lang/Enum;", nullable: false)], arguments: [array])
        b.instructions += [.putStatic(enumEntriesField(plan), list), .returnValue(nil)]
        var initializer = b.finish(); initializer.access = 8

        let v = try nominalBuilder(plan, name: "values", result: arrayType, staticBody: true)
        let source = try v.value(arrayType); v.instructions.append(.getStatic(enumValuesField(plan), source))
        let clone = JVMForeignMethod(owner: arrayType.referenceName!, name: "clone", descriptor: "()Ljava/lang/Object;", parameters: [], result: .reference("java/lang/Object", nullable: true), isStatic: false, isInterface: false, isAbstract: false)
        let result = try v.value(arrayType)
        v.instructions += [.foreignCall(clone, receiver: source, arguments: [], result: result), .returnValue(result)]
        var valuesMethod = v.finish(); valuesMethod.access = 0x0009

        let n = try nominalBuilder(plan, name: "valueOf", parameters: [.string], result: type, staticBody: true)
        // Enum.valueOf needs the actual Class object; Class.forName also works
        // for library consumers using a separate application class loader.
        let cls = try n.jdkCall("java/lang/Class", "forName", [.string], .reference("java/lang/Class", nullable: false), arguments: [n.constant(.string(plan.name.replacingOccurrences(of: "/", with: ".")), .string)])!
        let value = try n.jdkCall("java/lang/Enum", "valueOf", [cls.type, .string], .reference("java/lang/Enum", nullable: false), arguments: [cls, n.locals[0]], resolved: type)!
        n.instructions.append(.returnValue(value))
        var valueOf = n.finish(); valueOf.access = 9

        let e = try nominalBuilder(plan, name: "getEntries", result: enumEntriesField(plan).type, staticBody: true)
        let all = try e.value(enumEntriesField(plan).type)
        e.instructions += [.getStatic(enumEntriesField(plan), all), .returnValue(all)]
        var getEntries = e.finish(); getEntries.access = 9
        getEntries.genericSignature = "()Lkotlin/enums/EnumEntries<L" + plan.name + ";>;"
        return [initializer, valuesMethod, valueOf, getEntries]
    }

    func emitEnumEntryConstructor(_ plan: JVMClassPlan) throws -> JVMFunction {
        let parent = classes[plan.enumParent!]!, primary = parent.constructors.first { $0.2 }!
        let params: [JVMValueType] = [.string, .int] + methods[primary.0]!.parameters
        let b = try nominalBuilder(plan, name: "<init>", parameters: params)
        let ctor = JVMForeignMethod(owner: parent.name, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: .reference(parent.name, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        b.instructions.append(.foreignCall(ctor, receiver: b.thisValue, arguments: Array(b.locals.dropFirst()), result: nil))
        b.scopes = [[:]]
        try emitInitializers(plan, builder: b, object: b.thisValue!)
        if !b.terminated { b.instructions.append(.returnValue(nil)) }
        var f = b.finish(constructor: true); f.access = 0; return f
    }

    func emitEnumEntryDefaultConstructor(_ plan: JVMClassPlan) throws -> JVMFunction? {
        let parent = classes[plan.enumParent!]!, primary = parent.constructors.first { $0.2 }!
        guard primary.1.valueParams.contains(where: \.hasDefaultValue) else { return nil }
        let params: [JVMValueType] = [.string, .int] + methods[primary.0]!.parameters + Array(repeating: .int, count: (primary.1.valueParams.count + 31) / 32) + [.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)]
        let b = try nominalBuilder(plan, name: "<init>", parameters: params)
        let arguments = Array(b.locals.dropFirst())
        let ctor = JVMForeignMethod(owner: parent.name, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: .reference(parent.name, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        b.instructions.append(.foreignCall(ctor, receiver: b.thisValue, arguments: arguments, result: nil))
        b.scopes = [[:]]
        try emitInitializers(plan, builder: b, object: b.thisValue!)
        if !b.terminated { b.instructions.append(.returnValue(nil)) }
        var f = b.finish(constructor: true); f.access = 0x1000; return f
    }

    func enumRuntime() -> [JVMClass] {
        guard classes.values.contains(where: \.isEnum) else { return [] }
        let marker = rawClass("kotlin/jvm/internal/markers/KMappedMarker", access: 0x0601)
        var entries = rawClass("kotlin/enums/EnumEntries", interfaces: ["java/util/List", marker.name], access: 0x0601)
        entries.genericSignature = "<E:Ljava/lang/Enum<TE;>;>Ljava/lang/Object;Ljava/util/List<TE;>;Lkotlin/jvm/internal/markers/KMappedMarker;"
        let name = facadeName + "$EnumEntries", array: JVMValueType = .reference("[Ljava/lang/Enum;", nullable: false)
        let own = JVMValue(slot: 0, type: .reference(name, nullable: false)), input = JVMValue(slot: 1, type: array)
        let field = JVMField(owner: name, name: "values", type: array, access: 0x12)
        let parent = JVMForeignMethod(owner: "java/util/AbstractList", name: "<init>", descriptor: "()V", parameters: [], result: .reference("java/util/AbstractList", nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        let ctor = rawFunction(name, name: "<init>", parameters: [array], result: .unit, access: 1, locals: [own, input], instructions: [.foreignCall(parent, receiver: own, arguments: [], result: nil), .putField(field, own, input), .returnValue(nil)], constructor: true)
        let size = JVMValue(slot: 2, type: .int)
        let sizeMethod = rawFunction(name, name: "size", parameters: [], result: .int, access: 0x11, locals: [own, input, size], instructions: [.getField(field, own, input), .arrayLength(input, size), .returnValue(size)])
        let index = JVMValue(slot: 1, type: .int), data = JVMValue(slot: 2, type: array), result = JVMValue(slot: 3, type: .reference("java/lang/Object", nullable: true))
        let get = rawFunction(name, name: "get", parameters: [.int], result: result.type, access: 0x11, locals: [own, index, data, result], instructions: [.getField(field, own, data), .arrayGet(data, index, result), .returnValue(result)])
        let type = JVMClass(name: name, superclass: parent.owner, interfaces: [entries.name], access: 0x1031, functions: [ctor, sizeMethod, get], properties: [])
        var implementation = type; implementation.emitMetadata = false; implementation.extraFields = [field]
        return [marker, entries].filter { candidate in
            !classes.values.contains(where: { $0.name == candidate.name }) && context.jvmImports?.classes[candidate.name] == nil
        } + [implementation]
    }
}
