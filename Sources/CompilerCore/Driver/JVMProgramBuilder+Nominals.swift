import Foundation

extension JVMClasspathIndex {
    static func binaryName(_ symbol: SymbolID, sema: SemaModule, ctx: CompilationContext) -> String {
        guard let value = sema.symbols.symbol(symbol) else { return "" }
        if let parent = sema.symbols.parentSymbol(for: symbol), let enclosing = sema.symbols.symbol(parent),
           [.class, .interface, .object, .enumClass, .annotationClass].contains(enclosing.kind) {
            return binaryName(parent, sema: sema, ctx: ctx) + "$" + ctx.interner.resolve(value.name)
        }
        if value.kind == .class, value.flags.contains(.synthetic), ctx.interner.resolve(value.name).hasPrefix("__ObjectLiteral_"),
           let site = value.declSite, let file = ctx.ast?.files.first(where: { $0.fileID == site.start.file }) {
            return (file.packageFQName.map(ctx.interner.resolve) + [ctx.interner.resolve(value.name)]).joined(separator: "/")
        }
        let sourceName = value.fqName.map(ctx.interner.resolve).joined(separator: "/")
        return ctx.jvmRuntimeClassAliases[sourceName] ?? sourceName
    }
}

extension JVMProgramBuilder {
    func collectNominals(_ declarations: [DeclID], outer: SymbolID? = nil, companion: Bool = false, anonymous: Bool = false) throws {
        for id in declarations {
            guard let symbol = sema.bindings.declSymbol(for: id) else { throw JVMFrontendError(message: "Missing JVM nominal symbol.") }
            let plan: JVMClassPlan
            switch ast.arena.decl(id) {
            case let .classDecl(c):
                guard
                      c.modifiers.subtracting([.public, .internal, .private, .protected, .open, .final, .abstract, .data, .sealed, .enumModifier, .inner, .value, .annotationClass]).isEmpty else { throw JVMFrontendError(message: "Unsupported JVM M9 class declaration.", range: c.range) }
                guard !c.modifiers.contains(.enumModifier) || c.secondaryConstructors.isEmpty else { throw JVMFrontendError(message: "JVM M8 does not support enum secondary constructors.", range: c.range) }
                plan = JVMClassPlan(symbol: symbol, name: try className(symbol), declaration: c)
                classes[symbol] = plan
                try collectNominals(c.nestedClasses + c.nestedObjects, outer: symbol)
                if let companion = c.companionObject { try collectNominals([companion], outer: symbol, companion: true) }
            case let .interfaceDecl(i):
                guard
                      i.modifiers.subtracting([.public, .internal, .private, .protected, .abstract, .funModifier, .sealed]).isEmpty else { throw JVMFrontendError(message: "Unsupported JVM interface declaration.", range: i.range) }
                plan = JVMClassPlan(symbol: symbol, name: try className(symbol), interface: i)
                classes[symbol] = plan
                try collectNominals(i.nestedClasses + i.nestedObjects, outer: symbol)
                if let companion = i.companionObject { try collectNominals([companion], outer: symbol, companion: true) }
            case let .objectDecl(o):
                guard
                      o.modifiers.subtracting([.public, .internal, .private, .protected, .companion, .data]).isEmpty else { throw JVMFrontendError(message: "Unsupported JVM object declaration.", range: o.range) }
                let c = ClassDecl(range: o.range, name: o.name, modifiers: o.modifiers.subtracting(.companion), superTypeEntries: o.superTypeEntries, initBlocks: o.initBlocks, classBodyInitOrder: o.classBodyInitOrder, memberFunctions: o.memberFunctions, memberProperties: o.memberProperties)
                plan = JVMClassPlan(symbol: symbol, name: try className(symbol), declaration: c)
                plan.object = o; plan.isAnonymous = anonymous; plan.companionOwner = companion ? outer : nil
                classes[symbol] = plan
                try collectNominals(o.nestedClasses + o.nestedObjects, outer: symbol)
            case .funDecl, .propertyDecl, .typeAliasDecl: continue
            default: throw JVMFrontendError(message: "Unsupported JVM top-level declaration.")
            }
            plan.outer = outer
            if plan.isEnum {
                for entry in plan.declaration!.enumEntries where !entry.memberFunctions.isEmpty || !entry.memberProperties.isEmpty || !entry.initBlocks.isEmpty {
                    guard entry.annotations.isEmpty, entry.nestedClasses.isEmpty,
                          let member = sema.symbols.lookupAll(fqName: sema.symbols.symbol(symbol)!.fqName + [entry.name]).first(where: { sema.symbols.symbol($0)?.kind == .field }) else { throw JVMFrontendError(message: "Unsupported JVM enum entry body.", range: entry.range) }
                    let declaration = ClassDecl(range: entry.range, name: entry.name, modifiers: [.final], initBlocks: entry.initBlocks, classBodyInitOrder: entry.classBodyInitOrder, memberFunctions: entry.memberFunctions, memberProperties: entry.memberProperties)
                    let child = JVMClassPlan(symbol: member, name: plan.name + "$" + context.interner.resolve(entry.name), declaration: declaration)
                    child.enumParent = symbol; child.enumEntry = entry; child.outer = symbol
                    classes[member] = child
                }
            }
        }
    }

    func singletonField(_ plan: JVMClassPlan) -> JVMField {
        JVMField(owner: plan.companionOwner.flatMap { classes[$0]?.name } ?? plan.name,
                 name: plan.companionOwner == nil ? "INSTANCE" : context.interner.resolve(sema.symbols.symbol(plan.symbol)!.name),
                 type: .reference(plan.name, nullable: false), access: 0x19)
    }

    func interfaceCompanionStorage(_ plan: JVMClassPlan) -> JVMField? {
        guard let owner = plan.companionOwner, classes[owner]?.isInterface == true else { return nil }
        return JVMField(owner: plan.name, name: "$$INSTANCE", type: .reference(plan.name, nullable: false), access: 0x1018)
    }

    func nominalBuilder(_ plan: JVMClassPlan, name: String, parameters: [JVMValueType] = [], result: JVMValueType = .unit, staticBody: Bool = false) throws -> JVMFunctionBuilder {
        let declaration = FunDecl(range: (plan.declaration?.range ?? plan.interface!.range), name: context.interner.intern(name), modifiers: [], valueParams: parameters.indices.map { ValueParamDecl(name: context.interner.intern("p\($0)"), type: nil) }, body: .unit)
        let builder = JVMFunctionBuilder(program: self, declaration: declaration, reference: JVMFunctionReference(name: name, parameters: parameters, result: result), owner: plan)
        builder.isStaticBody = staticBody
        try builder.prepareParameters()
        return builder
    }

    func emitInitializers(_ plan: JVMClassPlan, builder: JVMFunctionBuilder, object: JVMValue) throws {
        let c = plan.declaration!
        for member in c.classBodyInitOrder where !builder.terminated {
            switch member {
            case let .property(index):
                let id = c.memberProperties[index]
                guard let (_, declaration, property) = plan.properties.first(where: { $0.0 == id }) else { throw JVMFrontendError(message: "Missing JVM property initializer.") }
                if declaration.modifiers.contains(.const) { continue }
                if let delegate = declaration.delegateExpression, let field = property.delegateField, let symbol = property.delegateSymbol {
                    let initial = try builder.requireValue(delegate)
                    let token = try builder.delegateToken(symbol, plan: plan)
                    let stored = try builder.provideDelegate(initial, symbol: symbol, token: token)
                    let converted = try builder.convert(stored, to: field.type)
                    builder.instructions.append(plan.isFacade ? .putStatic(field, converted) : .putField(field, object, converted))
                } else if let initializer = declaration.initializer {
                    guard let field = property.field else { throw JVMFrontendError(message: "JVM initializer needs a backing field.") }
                    let initial = try builder.convert(builder.requireValue(initializer), to: field.type)
                    builder.instructions.append(plan.isFacade ? .putStatic(field, initial) : .putField(field, object, initial))
                }
            case let .initBlock(index): try builder.statements(c.initBlocks[index])
            }
        }
    }

    func emitObjectConstructor(_ plan: JVMClassPlan) throws -> JVMFunction {
        let b = try nominalBuilder(plan, name: "<init>")
        b.beforeDelegation = true
        let args = plan.object!.superTypeConstructorArgs
        let selected = try objectSuper(plan)
        var method = selected.method
        let ordered = try b.arguments(args, binding: selected.binding, parameters: method.parameters, declarations: selected.binding.flatMap { sourceParameters[$0.chosenCallee] })
        var values = ordered.values
        if ordered.masks.contains(where: { $0 != 0 }) {
            values += try b.maskArguments(ordered.masks, constructor: true)
            let types = values.map(\.type)
            method = JVMForeignMethod(owner: method.owner, name: "<init>", descriptor: "(" + types.map(\.descriptor).joined() + ")V", parameters: types, result: method.result, isStatic: false, isInterface: false, isAbstract: false)
        }
        b.instructions += [.foreignCall(method, receiver: b.thisValue, arguments: values, result: nil), .returnValue(nil)]
        var function = b.finish(constructor: true); function.isPrivate = true; function.access = plan.companionOwner == nil || interfaceCompanionStorage(plan) != nil ? 2 : 0; return function
    }

    func objectInitializer(_ plan: JVMClassPlan) throws -> JVMFunction {
        let b = try nominalBuilder(plan, name: "<clinit>", staticBody: true)
        let field = interfaceCompanionStorage(plan) ?? singletonField(plan), object = try b.value(field.type)
        let ctor = JVMForeignMethod(owner: plan.name, name: "<init>", descriptor: "()V", parameters: [], result: field.type, isStatic: false, isInterface: false, isAbstract: false)
        b.instructions += [.allocate(plan.name, object), .foreignCall(ctor, receiver: object, arguments: [], result: nil), .putStatic(field, object)]
        b.thisValue = object; b.initializingObject = true
        b.contextualReceivers[plan.symbol] = object
        b.contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: plan.symbol)] = object
        try emitClassDelegates(plan, builder: b, object: object)
        try emitInitializers(plan, builder: b, object: object)
        if !b.terminated { b.instructions.append(.returnValue(nil)) }
        var f = b.finish(); f.access = 8; return f
    }

    func prepareNominalMembers(_ plan: JVMClassPlan) throws {
        if plan.modifiers.contains(.data) {
            if plan.isObject, plan.companionOwner != nil || plan.methods.contains(where: { $0.1.name == "hashCode" && $0.1.descriptor == "()I" || $0.1.name == "equals" && $0.1.descriptor == "(Ljava/lang/Object;)Z" }) {
                throw JVMFrontendError(message: "A data object cannot be a companion or provide custom equals/hashCode.", range: plan.object?.range)
            }
            try prepareDataMembers(plan)
        }
    }

    func nominalMethods(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        var functions: [JVMFunction] = []
        if !plan.propertyTokens.isEmpty { functions.append(try propertyTokenInitializer(plan)) }
        if plan.modifiers.contains(.data) { functions += try plan.isObject ? dataObjectMethods(plan, existing: existing) : dataMethods(plan, existing: existing) }
        if plan.isObject && (plan.companionOwner == nil || interfaceCompanionStorage(plan) != nil) { functions.append(try objectInitializer(plan)) }
        if plan.isEnum { functions += try enumMethods(plan) }
        if let companion = classes.values.first(where: { $0.companionOwner == plan.symbol }) {
            if let storage = interfaceCompanionStorage(companion) {
                let b = try nominalBuilder(plan, name: "<clinit>", staticBody: true)
                let object = try b.value(storage.type)
                b.instructions += [.getStatic(storage, object), .putStatic(singletonField(companion), object), .returnValue(nil)]
                var function = b.finish(); function.access = 8; functions.append(function)
            } else {
                functions.append(try objectInitializer(companion))
            }
        }
        if plan.modifiers.contains(.sealed) { functions += try sealedConstructors(plan, existing: existing) }
        let initializers = functions.filter { $0.reference.name == "<clinit>" }
        if initializers.count > 1 {
            var locals: [JVMValue] = [], code: [JVMInstruction] = [], handlers: [JVMExceptionHandler] = [], slot = 0, labelOffset = 0
            for function in initializers {
                let offset = slot
                locals += function.locals.map { JVMValue(slot: $0.slot + offset, type: $0.type) }
                slot = locals.last.map { $0.slot + $0.type.width } ?? slot
                for instruction in function.instructions {
                    if case .returnValue(nil) = instruction { continue }
                    let mapped = instruction.mappingValues { JVMValue(slot: $0.slot + offset, type: $0.type) }
                    switch mapped {
                    case let .label(n): code.append(.label(n + labelOffset))
                    case let .regionBoundary(n): code.append(.regionBoundary(n + labelOffset))
                    case let .jump(n): code.append(.jump(n + labelOffset))
                    case let .jumpIfFalse(v, n): code.append(.jumpIfFalse(v, n + labelOffset))
                    case let .defaultArgument(v, bit, n): code.append(.defaultArgument(v, bit, n + labelOffset))
                    case let .exceptionHandler(n, v, preserved): code.append(.exceptionHandler(n + labelOffset, v, preserving: preserved))
                    default: code.append(mapped)
                    }
                }
                handlers += function.handlers.map { JVMExceptionHandler(start: $0.start + labelOffset, end: $0.end + labelOffset, handler: $0.handler + labelOffset, type: $0.type) }
                labelOffset += (function.instructions.compactMap(\.labelNumber).max() ?? -1) + 1
            }
            code.append(.returnValue(nil))
            var merged = rawFunction(plan.name, name: "<clinit>", parameters: [], result: .unit, access: 8, locals: locals, instructions: code)
            merged.handlers = handlers
            functions.removeAll { $0.reference.name == "<clinit>" }; functions.append(merged)
        }
        return functions
    }

    func decorateNominal(_ plan: JVMClassPlan, result: inout JVMClass) throws {
        result.extraFields += plan.delegateFields.map { $0.2 } + Array(plan.propertyTokens.values).sorted { $0.name < $1.name } + plan.properties.compactMap { $0.2.delegateField }
        if let companionOwner = plan.companionOwner {
            result.properties = result.properties.map { property in
                guard let field = property.field, field.constantValue != nil else { return property }
                var property = property
                if classes[companionOwner]?.isInterface == true {
                    // Kotlin duplicates interface companion constants in both owners.
                    var duplicate = JVMField(owner: plan.name, name: field.name, type: field.type, access: field.access)
                    duplicate.annotations = field.annotations
                    duplicate.constantValue = field.constantValue
                    duplicate.isDeprecated = field.isDeprecated
                    property.field = duplicate
                } else {
                    property.field = nil
                }
                return property
            }
        }
        result.isObject = plan.isObject; result.isCompanion = plan.companionOwner != nil
        result.isData = plan.modifiers.contains(.data); result.isEnum = plan.isEnum
        result.isSealed = plan.modifiers.contains(.sealed)
        result.isInner = plan.isInner
        if let field = try outerField(plan) { result.extraFields.append(field) }
        if plan.isAnonymous { result.emitMetadata = false; result.extraFields += plan.captures.map(\.field) }
        result.outerName = plan.outer.flatMap { classes[$0]?.name }
        result.innerName = result.outerName == nil ? nil : String(plan.name.split(separator: "$").last!)
        result.nestedNames = classes.values.filter { $0.outer == plan.symbol && $0.enumParent == nil }.map { String($0.name.split(separator: "$").last!) }.sorted()
        result.companionName = classes.values.first(where: { $0.companionOwner == plan.symbol }).map { context.interner.resolve(sema.symbols.symbol($0.symbol)!.name) }
        result.sealedSubclasses = try (sema.symbols.sealedSubclasses(for: plan.symbol) ?? []).map(className).sorted()
        if plan.isObject && plan.companionOwner == nil { result.extraFields.append(singletonField(plan)) }
        if let storage = interfaceCompanionStorage(plan) { result.extraFields.append(storage) }
        if let companion = classes.values.first(where: { $0.companionOwner == plan.symbol }) {
            result.extraFields.append(singletonField(companion))
            result.extraFields += companion.properties.compactMap {
                guard let field = $0.2.field, field.constantValue != nil,
                      !plan.isInterface || field.access & 2 == 0 else { return nil }
                return field
            }
        }
        if plan.isEnum { try decorateEnum(plan, result: &result) }
        if plan.enumParent != nil { result.emitMetadata = false }
    }
}
