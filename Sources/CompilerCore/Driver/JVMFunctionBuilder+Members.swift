import Foundation

extension JVMFunctionBuilder {
    func instance(_ id: ExprID) throws -> JVMValue {
        let receiver = try unconvertedInstance(id)
        if propertyBinding(id)?.getter.isStatic == true { return receiver }
        let objectName = memberDispatchOwner(id)
        guard let objectName, !isMemberReceiver(receiver, owner: objectName) else { return receiver }
        // A smart-cast implicit receiver retains its original physical local
        // type. Narrow it to the selected member's owner before invocation.
        return try convert(receiver, to: .reference(objectName, nullable: false))
    }
    func unconvertedInstance(_ id: ExprID) throws -> JVMValue {
        if let property = propertyBinding(id), property.getter.isStatic {
            guard let receiverType = property.getter.parameters.first else {
                return try constant(.null, .reference("java/lang/Object", nullable: true))
            }
            guard let receiver = implicitExtensionReceiver(id) else { throw fail("Missing JVM extension property receiver.", id) }
            return try convert(receiver, to: receiverType)
        }
        let bindings = program.sema.bindings
        // An object-member import binds its singleton independently of the
        // active extension receiver, even when their nominal types match.
        if let symbol = bindings.callBinding(for: id)?.dispatchReceiverSymbol,
           let object = program.classes[symbol], object.isObject {
            // During singleton initialization its contextual this is already
            // available before the static singleton field is assigned.
            if let receiver = contextualReceivers[symbol],
               !beforeDelegation || receiver.slot != thisValue?.slot { return receiver }
            return try singleton(object)
        }
        if let symbol = bindings.implicitReceiverOuterReceiver(for: id) ?? bindings.callBinding(for: id)?.dispatchReceiverSymbol, let receiver = contextualReceivers[symbol], !beforeDelegation || receiver.slot != thisValue?.slot { return receiver }
        let objectName = memberDispatchOwner(id)
        // For an unqualified ordinary member, the extension receiver precedes
        // the dispatch owner even when both have the same nominal type.
        // This also selects the closest owner for a member-extension callee;
        // its explicit extension argument is supplied separately by sourceCall.
        if let extensionValue, let objectName,
           isMemberReceiver(extensionValue, owner: objectName) { return extensionValue }
        if let thisValue, let owner, !beforeDelegation {
            if objectName == owner.name { return thisValue }
            if propertyBinding(id)?.getter.owner == owner.name { return thisValue }
        }
        if let name = objectName, let lexical = program.classes.values.first(where: { $0.name == name }), let receiver = contextualReceivers[lexical.symbol], !beforeDelegation || receiver.slot != thisValue?.slot { return receiver }
        if let name = objectName, let object = program.classes.values.first(where: { $0.name == name && $0.isObject }) { return try singleton(object) }
        guard !beforeDelegation else { throw fail("JVM member access requires an initialized this.", id) }
        if let value = extensionValue ?? thisValue { return value }
        throw fail("JVM member access requires a receiver.", id)
    }
    func memberDispatchOwner(_ id: ExprID) -> String? {
        if let symbol = program.sema.bindings.callBinding(for: id)?.chosenCallee,
           let method = program.methods[symbol] ?? context.jvmImports?.methods[symbol] ?? program.textLibraryMethods[symbol]?.method {
            return method.owner
        }
        return propertyBinding(id)?.getter.owner
    }
    func isMemberReceiver(_ value: JVMValue, owner: String) -> Bool {
        var pending = value.type.referenceName.map { [$0] } ?? []
        var visited: Set<String> = []
        while let name = pending.popLast() {
            if name == owner { return true }
            guard visited.insert(name).inserted else { continue }
            if let plan = program.classes.values.first(where: { $0.name == name }) {
                pending += [plan.superclass] + plan.interfaces
            } else if let imported = context.jvmImports?.classes[name] {
                pending += [imported.superclass].compactMap { $0 } + imported.interfaces
            }
        }
        return false
    }
    func isSuper(_ id: ExprID) -> Bool {
        if case .superRef = arena.expr(id) { return true }
        return false
    }
    func mappedBuiltinMemberOwner(_ id: ExprID) throws -> String? {
        let sema = program.sema
        guard let selected = sema.bindings.callBinding(for: id)?.chosenCallee ?? sema.bindings.identifierSymbol(for: id) else { return nil }
        let declaration = sema.symbols.propertySymbol(forAccessor: selected) ?? selected
        guard let parent = sema.symbols.parentSymbol(for: declaration) else { return nil }
        return JVMClasspathIndex.builtinName(try program.className(parent))
    }

    func propertyBinding(_ id: ExprID) -> JVMProperty? {
        let sema = program.sema
        func sourceProperty(for candidate: SymbolID) -> JVMProperty? {
            if let property = program.properties[candidate] { return property }
            let owner = sema.symbols.propertySymbol(forAccessor: candidate)
                ?? sema.symbols.accessorOwnerProperty(for: candidate)
                ?? sema.symbols.parentSymbol(for: candidate).flatMap { parent in
                    sema.symbols.symbol(parent)?.kind == .property ? parent : nil
                }
            return owner.flatMap { program.properties[$0] }
        }
        if let symbol = sema.bindings.identifierSymbol(for: id), let property = sourceProperty(for: symbol) { return property }
        if let call = sema.bindings.callBinding(for: id) {
            if let property = sourceProperty(for: call.chosenCallee) { return property }
        }
        let selected = sema.bindings.identifierSymbol(for: id) ?? sema.bindings.callBinding(for: id)?.chosenCallee
        if let selected {
            let symbol = sema.symbols.propertySymbol(forAccessor: selected)
                ?? sema.symbols.accessorOwnerProperty(for: selected)
                ?? selected
            if let semanticSymbol = sema.symbols.symbol(symbol), semanticSymbol.kind == .property,
               let parent = sema.symbols.parentSymbol(for: symbol),
               let owner = try? program.className(parent),
               let info = context.jvmImports?.classes[owner],
               let propertyType = sema.symbols.propertyType(for: symbol),
               let type = try? program.type(propertyType) {
                let name = context.interner.resolve(semanticSymbol.name)
                let capital = String(name.prefix(1)).uppercased() + name.dropFirst()
                let names = info.flags & 0x2000 != 0 ? [name] : (name.hasPrefix("is") && name.count > 2 ? [name, "get" + capital] : ["get" + capital])
                if let imported = info.methods.first(where: {
                    names.contains($0.name) && !$0.isStatic && !$0.isConstructor && $0.parameters.isEmpty && $0.result.descriptor == type.descriptor
                }) {
                    var getter = JVMForeignMethod(
                        owner: imported.owner, name: imported.name, descriptor: imported.descriptor,
                        parameters: imported.parameters, result: type, isStatic: false,
                        isInterface: imported.isInterface, isAbstract: imported.isAbstract
                    )
                    getter.isFinal = imported.isFinal
                    return JVMProperty(name: name, type: type, getter: getter, setter: nil, field: nil, modifiers: [.public])
                }
            }
        }
        let name: InternedString?
        switch arena.expr(id) {
        case let .nameRef(n, _), let .localAssign(n, _, _), let .compoundAssign(_, n, _, _): name = n
        default: name = nil
        }
        if let name { return owner?.properties.first { $0.2.name == context.interner.resolve(name) }?.2 }
        return nil
    }
    func superMethod(_ method: JVMForeignMethod, receiver: ExprID?) throws -> JVMForeignMethod {
        var selected = method
        selected.isSpecial = true
        guard method.isInterface, let owner else { return selected }
        func inherits(_ name: String, _ target: String, visited: Set<String>) -> Bool {
            if name == target { return true }
            guard !visited.contains(name) else { return false }
            let parents = program.classes.values.first(where: { $0.name == name })?.interfaces ?? context.jvmImports?.classes[name]?.interfaces ?? []
            return parents.contains { inherits($0, target, visited: visited.union([name])) }
        }
        var qualifier: String?
        if let receiver, case let .superRef(name, _, _) = arena.expr(receiver) { qualifier = name.map(context.interner.resolve) }
        let candidates = owner.interfaces.filter { interface in
            (qualifier == nil || interface.split(separator: "/").last.map(String.init) == qualifier || interface.replacingOccurrences(of: "/", with: ".") == qualifier) && inherits(interface, method.owner, visited: [])
        }
        guard let target = candidates.first else { throw fail("JVM interface super call requires a direct superinterface.", receiver) }
        selected = JVMForeignMethod(owner: target, name: method.name, descriptor: method.descriptor, parameters: method.parameters, result: method.result, isStatic: false, isInterface: true, isAbstract: method.isAbstract, isSpecial: true)
        selected.isSuspend = method.isSuspend
        return selected
    }
    func readProperty(_ property: JVMProperty, receiver: JVMValue, special: Bool, superReceiver: ExprID? = nil) throws -> JVMValue {
        if let literal = property.field?.constantValue { return try constant(literal, property.type) }
        var getter = property.getter
        if special { getter = try superMethod(getter, receiver: superReceiver) }
        let result = try value(property.type)
        let arguments = try getter.parameters.first.map { [try convert(receiver, to: $0)] } ?? []
        instructions.append(.foreignCall(getter, receiver: getter.isStatic ? nil : receiver, arguments: arguments, result: result))
        if getter.result.referenceName == "java/lang/Class", case .named("kotlin/reflect/KClass", _, _)? = property.kotlinType {
            return try jdkCall("kotlin/jvm/JvmClassMappingKt", "getKotlinClass", [getter.result], .reference("kotlin/reflect/KClass", nullable: false), arguments: [result])!
        }
        if getter.result.referenceName == "[Ljava/lang/Class;", case let .named("kotlin/Array", arguments, _)? = property.kotlinType,
           case .named("kotlin/reflect/KClass", _, _)? = arguments.first?.type {
            let element: JVMValueType = .reference("kotlin/reflect/KClass", nullable: false)
            let array = try value(.reference("[Lkotlin/reflect/KClass;", nullable: false)), count = try value(.int)
            instructions.append(.arrayLength(result, count))
            instructions.append(.newArray(element, count: count, result: array))
            let index = try constant(.int(0), .int), loop = label(), end = label(), check = try value(.boolean)
            mark(loop); instructions += [.binary(.lessThan, index, count, check), .jumpIfFalse(check, end)]
            let klass = try value(.reference("java/lang/Class", nullable: false))
            instructions.append(.arrayGet(result, index, klass))
            let mapped = try jdkCall("kotlin/jvm/JvmClassMappingKt", "getKotlinClass", [klass.type], element, arguments: [klass])!
            instructions.append(.arraySet(array, index, mapped))
            instructions.append(.binary(.add, index, try constant(.int(1), .int), index))
            jump(loop); mark(end); return array
        }
        return result
    }
    func writeProperty(_ property: JVMProperty, receiver: JVMValue, value source: JVMValue, initializing: Bool = false, special: Bool = false, superReceiver: ExprID? = nil) throws {
        let converted = try convert(source, to: property.type)
        if initializing, property.setter == nil, receiver.slot == thisValue?.slot, property.field?.owner == owner?.name, let field = property.field {
            instructions.append(.putField(field, receiver, converted)); return
        }
        guard var setter = property.setter else { throw fail("JVM val has no setter.") }
        if special { setter = try superMethod(setter, receiver: superReceiver) }
        var arguments: [JVMValue] = []
        if setter.parameters.count == 2 {
            arguments.append(try convert(receiver, to: setter.parameters[0]))
        }
        guard let valueType = setter.parameters.last else { throw fail("JVM property setter has no value parameter.") }
        arguments.append(try convert(converted, to: valueType))
        instructions.append(.foreignCall(setter, receiver: setter.isStatic ? nil : receiver, arguments: arguments, result: nil))
    }
    func propertyCompound(_ property: JVMProperty, receiver: JVMValue, op: CompoundAssignOp, rhs: ExprID, id: ExprID, special: Bool = false, superReceiver: ExprID? = nil) throws -> JVMValue? {
        let originalReceiver = receiver, receiver = try value(receiver.type)
        instructions.append(.copy(originalReceiver, receiver))
        let left = try arena.incrementDecrementCachedValue(for: id).map(requireValue)
            ?? readProperty(property, receiver: receiver, special: special, superReceiver: superReceiver)
        if let call = try resolvedCompoundCall(op, receiver: left, rhs: rhs, id: id) {
            if !call.mutatesReceiver, let result = call.value, !terminated {
                try writeProperty(property, receiver: receiver, value: result, special: special, superReceiver: superReceiver)
            }
            return nil
        }
        let right = try compoundOperand(rhs, target: left.type)
        if terminated { return nil }
        guard try permitsCompound(left.type, right.type) else { throw fail("Unsupported JVM property compound conversion.", id) }
        let converted = right, result = try value(left.type)
        let binary: BinaryOp
        switch op {
        case .plusAssign: binary = .add
        case .minusAssign: binary = .subtract
        case .timesAssign: binary = .multiply
        case .divAssign: binary = .divide
        case .modAssign: binary = .modulo
        }
        try compoundInstruction(binary, left, converted, result)
        try writeProperty(property, receiver: receiver, value: result, special: special, superReceiver: superReceiver)
        return arena.incrementDecrementReturnsValue(id) ? result : nil
    }
}

extension JVMProgramBuilder {
    func emitAccessors(_ plan: JVMClassPlan, _ declaration: PropertyDecl, _ property: JVMProperty) throws -> [JVMFunction] {
        let propertyID = plan.properties.first(where: { $0.1.range == declaration.range })?.0
        let propertySymbol = propertyID.flatMap { sema.bindings.declSymbol(for: $0) }
        var functions: [JVMFunction] = []
        for setter in [false, true] where !declaration.modifiers.contains(.const) {
            guard let method = setter ? property.setter : property.getter else { continue }
            let accessor = setter ? declaration.setter : declaration.getter
            var modifiers = declaration.modifiers
            if let visibility = accessor?.visibility {
                modifiers.subtract([.public, .protected, .private, .internal])
                switch visibility {
                case .public: modifiers.insert(.public)
                case .protected: modifiers.insert(.protected)
                case .private: modifiers.insert(.private)
                case .internal: modifiers.insert(.internal)
                }
            }
            let parameter = ValueParamDecl(name: accessor?.parameterName ?? context.interner.intern("value"), type: declaration.type)
            let f = FunDecl(range: declaration.range, name: context.interner.intern(method.name), modifiers: modifiers, receiverType: declaration.receiverType,
                            valueParams: setter ? [parameter] : [], body: accessor?.body ?? .unit)
            let builder = JVMFunctionBuilder(program: self, declaration: f, reference: JVMFunctionReference(name: method.name, parameters: method.parameters, result: method.result), owner: plan)
            builder.functionSymbol = propertySymbol
            builder.isStaticBody = plan.isFacade
            builder.backingProperty = property
            if method.isAbstract {
                try builder.prepareParameters(); functions.append(builder.finish(abstract: true)); continue
            }
            if (accessor?.body ?? .unit) != .unit {
                functions.append(try builder.build()); continue
            }
            try builder.prepareParameters()
            let object = builder.thisValue
            if let field = property.delegateField, let symbol = property.delegateSymbol {
                let delegate = try builder.value(field.type)
                builder.instructions.append(plan.isFacade ? .getStatic(field, delegate) : .getField(field, object!, delegate))
                let token = try builder.delegateToken(symbol, plan: plan)
                if setter {
                    try builder.writeDelegate(delegate, symbol: symbol, token: token, source: builder.locals[plan.isFacade ? 0 : 1])
                    builder.instructions.append(.returnValue(nil))
                } else {
                    let result = try builder.readDelegate(delegate, symbol: symbol, token: token, type: property.type)
                    builder.instructions.append(.returnValue(result))
                }
            } else {
                guard let field = property.field else { throw JVMFrontendError(message: "JVM concrete default accessor needs a backing field.", range: declaration.range) }
                if setter {
                    let source = builder.locals[plan.isFacade ? 0 : 1]
                    builder.instructions += [field.access & 8 != 0 ? .putStatic(field, source) : .putField(field, object!, source), .returnValue(nil)]
                } else {
                    let result = try builder.value(property.type)
                    builder.instructions.append(field.access & 8 != 0 ? .getStatic(field, result) : .getField(field, object!, result))
                    if declaration.modifiers.contains(.lateinit) { _ = try builder.checkLateinit(result, name: property.name) }
                    builder.instructions.append(.returnValue(result))
                }
            }
            functions.append(builder.finish())
        }
        var decorated = try functions.map { function in
            var f = function
            if let symbol = propertySymbol {
                f.annotations = try annotations(for: symbol, target: function.reference.result == .unit ? "set" : "get")
                applyDeprecation(try annotations(for: symbol, target: nil) + annotations(for: symbol, target: "property") + f.annotations, to: &f)
                if function.reference.result == .unit { f.parameterAnnotations = [try annotations(for: symbol, target: "setparam")] }
            }
            if plan.isFacade { f.access = (f.isPrivate ? 2 : 1) | 8 | 16; f.isSynthetic = false }
            let setter = f.reference.result == .unit
            let syntheticTarget = setter ? "set" : "get"
            if let symbol = propertySymbol,
               sema.symbols.annotations(for: symbol).contains(where: { $0.annotationFQName == "kotlin.jvm.JvmSynthetic" && $0.useSiteTarget == syntheticTarget }) {
                f.access = (f.access ?? 0) | 0x1000
            }
            f.kotlinParameters = setter ? [property.kotlinType].compactMap { $0 } : []
            f.kotlinResult = setter ? .named("kotlin/Unit", [], nullable: false) : property.kotlinType
            let receiverSignature = property.receiverGenericSignature ?? property.getter.parameters.first?.descriptor ?? ""
            f.genericSignature = setter
                ? "(" + receiverSignature + (property.genericSignature ?? property.type.descriptor) + ")V"
                : "(" + receiverSignature + ")" + (property.genericSignature ?? property.type.descriptor)
            if plan.isAnnotation { f.genericSignature = f.genericSignature?.replacingOccurrences(of: "Lkotlin/reflect/KClass", with: "Ljava/lang/Class") }
            return f
        }
        if let carrier = property.annotationsMethod, let symbol = propertySymbol {
            var f = rawFunction(plan.name, name: carrier.name, parameters: [], result: .unit, access: access(declaration.modifiers) | 0x1008, locals: [], instructions: [.returnValue(nil)])
            f.annotations = try annotations(for: symbol, target: nil) + annotations(for: symbol, target: "property")
            decorated.append(f)
        }
        return decorated
    }
    func emitConstructor(_ plan: JVMClassPlan, _ symbol: SymbolID, _ declaration: ConstructorDecl, primary: Bool) throws -> JVMFunction {
        let method = methods[symbol]!
        let hidden = plan.isEnum ? [ValueParamDecl(name: context.interner.intern("$name"), type: nil), ValueParamDecl(name: context.interner.intern("$ordinal"), type: nil)] : (plan.isInner ? [ValueParamDecl(name: context.interner.intern("$outer"), type: nil)] : [])
        let f = FunDecl(range: declaration.range, name: context.interner.intern("<init>"), modifiers: declaration.modifiers, valueParams: hidden + declaration.valueParams, body: declaration.body)
        let builder = JVMFunctionBuilder(program: self, declaration: f, reference: JVMFunctionReference(name: "<init>", parameters: (plan.isEnum ? [.string, .int] : []) + method.parameters, result: .unit), owner: plan)
        try builder.prepareParameters(); builder.beforeDelegation = true
        if plan.isInner, let outer = plan.outer { try builder.bindEnclosingInstance(classes[outer]!, value: builder.locals[1]) }
        let object = builder.thisValue!
        let target = sema.bindings.constructorDelegationTarget(for: symbol)
        let arguments = primary ? (plan.declaration?.superTypeEntries.first(where: { !$0.constructorArgs.isEmpty })?.constructorArgs ?? []) : (declaration.delegationCall?.args ?? [])
        let delegate: JVMForeignMethod
        if plan.isEnum {
            delegate = JVMForeignMethod(owner: "java/lang/Enum", name: "<init>", descriptor: "(Ljava/lang/String;I)V", parameters: [.string, .int], result: .reference("java/lang/Enum", nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        } else if let target, let method = methods[target] ?? context.jvmImports?.methods[target] ?? builtinMethod(target) { delegate = method }
        else {
            guard arguments.isEmpty, plan.superclass == "java/lang/Object" else { throw JVMFrontendError(message: "Missing JVM superclass constructor binding.", range: declaration.range) }
            delegate = JVMForeignMethod(owner: "java/lang/Object", name: "<init>", descriptor: "()V", parameters: [], result: .reference("java/lang/Object", nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        }
        guard delegate.isConstructor else { throw JVMFrontendError(message: "Invalid JVM constructor delegation.") }
        var selected = delegate
        var values: [JVMValue]
        if plan.isEnum { values = [builder.locals[1], builder.locals[2]] }
        else {
            let binding = sema.bindings.constructorDelegationCallBinding(for: symbol)
            let delegatePlan = classes.values.first { $0.name == delegate.owner }
            let prefix = try delegatePlan?.isInner == true ? [builder.enclosingInstance(delegatePlan!.outer!)] : []
            let ordered = try builder.arguments(arguments, binding: binding, parameters: Array(delegate.parameters.dropFirst(prefix.count)), declarations: target.flatMap { sourceParameters[$0] })
            values = prefix + ordered.values
            if ordered.masks.contains(where: { $0 != 0 }) {
                values += try builder.maskArguments(ordered.masks, constructor: true)
                let params = values.map(\.type)
                selected = JVMForeignMethod(owner: delegate.owner, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: delegate.result, isStatic: false, isInterface: false, isAbstract: false)
            }
        }
        if let field = try outerField(plan), delegate.owner != plan.name { builder.instructions.append(.putField(field, object, builder.locals[1])) }
        builder.instructions.append(.foreignCall(selected, receiver: object, arguments: values, result: nil))
        builder.beforeDelegation = false
        if primary || delegate.owner != plan.name {
            if primary {
                for parameter in declaration.valueParams where parameter.isProperty {
                    guard let property = plan.properties.first(where: { $0.2.name == context.interner.resolve(parameter.name) })?.2, let field = property.field else { throw JVMFrontendError(message: "Missing primary constructor backing field.") }
                    builder.instructions.append(.putField(field, object, try builder.lookup(parameter.name).value))
                }
            }
            try emitClassDelegates(plan, builder: builder, object: object)
            if primary {
                for parameter in declaration.valueParams where parameter.isProperty { builder.scopes[0].removeValue(forKey: parameter.name) }
            }
            try emitInitializers(plan, builder: builder, object: object)
        }
        try builder.statements(declaration.body)
        if !builder.terminated { builder.instructions.append(.returnValue(nil)) }
        var function = builder.finish(constructor: true)
        function.isSecondaryConstructor = !primary
        function.parameterDefaultFlags = declaration.valueParams.map(\.hasDefaultValue)
        function = try describe(function, signature: sema.symbols.functionSignature(for: symbol)!, parameters: [])
        if plan.isEnum {
            function.access = 0; function.isPrivate = true; function.parameterNames = declaration.valueParams.map { context.interner.resolve($0.name) }; function.kotlinParameterOffset = 2
            function.genericSignature = "(Ljava/lang/String;I" + String(function.genericSignature!.dropFirst())
        } else if plan.isInner {
            function.kotlinParameterOffset = 1; function.parameterNames = declaration.valueParams.map { context.interner.resolve($0.name) }
        } else if plan.modifiers.contains(.sealed), declaration.modifiers.isEmpty { function.access = 4 }
        return function
    }
    func bridges(_ plan: JVMClassPlan, functions: [JVMFunction]) throws -> [JVMFunction] {
        var parents: [JVMForeignMethod] = []
        var specializedParameters: [String: [JVMValueType]] = [:]
        func substitute(_ id: TypeID, _ mapping: [SymbolID: TypeID], resolving: Set<SymbolID> = []) -> TypeID {
            switch sema.types.kind(of: id) {
            case let .typeParam(p):
                let mapped: TypeID
                if let replacement = mapping[p.symbol] {
                    mapped = replacement
                } else if !resolving.contains(p.symbol), let bound = sema.symbols.typeParameterUpperBound(for: p.symbol) {
                    // Method parameters may be bounded by a substituted class
                    // parameter. Match bridges using that specialized erasure.
                    mapped = substitute(bound, mapping, resolving: resolving.union([p.symbol]))
                } else { return id }
                return p.nullability == .nullable ? sema.types.makeNullable(mapped) : mapped
            case let .classType(t):
                return sema.types.make(.classType(ClassType(classSymbol: t.classSymbol, args: t.args.map { $0.mapTypes { substitute($0, mapping, resolving: resolving) } }, nullability: t.nullability)))
            default: return id
            }
        }
        func parameterType(_ id: TypeID, _ mapping: [SymbolID: TypeID]) throws -> JVMValueType {
            let mapped = try type(substitute(id, mapping))
            if case let .typeParam(parameter) = sema.types.kind(of: id), mapping[parameter.symbol] == nil {
                return JVMClasspathIndex.boxed(mapped)
            }
            return mapped
        }
        var specializationVisited: Set<SymbolID> = []
        func specialize(_ symbol: SymbolID, mapping: [SymbolID: TypeID]) throws {
            guard specializationVisited.insert(symbol).inserted else { return }
            if let parent = classes[symbol] {
                for (decl, method) in parent.methods {
                    if let id = (parent.declaration?.memberFunctions ?? parent.interface!.memberFunctions).first(where: { if case let .funDecl(f) = ast.arena.decl($0) { return f.range == decl.range }; return false }),
                       let member = sema.bindings.declSymbol(for: id), let signature = sema.symbols.functionSignature(for: member) {
                        let receiver = extensionSymbols.contains(member) ? [signature.receiverType].compactMap { $0 } : []
                        specializedParameters[method.owner + method.name + method.descriptor] = try (receiver + signature.parameterTypes).map { try parameterType($0, mapping) }
                    }
                }
                for (id, _, property) in parent.properties {
                    if let member = sema.bindings.declSymbol(for: id), let source = sema.symbols.propertyType(for: member) {
                        specializedParameters[property.getter.owner + property.getter.name + property.getter.descriptor] = []
                        if let setter = property.setter { specializedParameters[setter.owner + setter.name + setter.descriptor] = [try type(substitute(source, mapping))] }
                    }
                }
            }
            if classes[symbol] == nil {
                for child in sema.symbols.children(of: symbol) {
                    if let method = methods[child] ?? collectionInterfaceMethods[child] ?? textLibraryMethods[child]?.method, let signature = sema.symbols.functionSignature(for: child) {
                        specializedParameters[method.owner + method.name + method.descriptor] = try signature.parameterTypes.map { try parameterType($0, mapping) }
                    }
                }
            }
            for parent in sema.symbols.directSupertypes(for: symbol) {
                let parameters = sema.types.nominalTypeParameterSymbols(for: parent)
                let args = sema.symbols.supertypeTypeArgs(for: symbol, supertype: parent)
                var next: [SymbolID: TypeID] = [:]
                for (parameter, arg) in zip(parameters, args) {
                    switch arg { case let .invariant(t), let .out(t), let .in(t): next[parameter] = substitute(t, mapping); case .star: break }
                }
                try specialize(parent, mapping: next)
            }
        }
        try specialize(plan.symbol, mapping: [:])
        var visited: Set<SymbolID> = []
        func visit(_ symbol: SymbolID) {
            guard visited.insert(symbol).inserted else { return }
            if let parent = classes[symbol] {
                parents += parent.methods.map { $0.1 }
                parents += parent.properties.flatMap { [$0.2.getter] + ($0.2.setter.map { [$0] } ?? []) }
            } else if let source = try? className(symbol) {
                let name = JVMClasspathIndex.builtinName(source) ?? source
                let known = Array(methods.values) + Array(collectionInterfaceMethods.values) + textLibraryMethods.values.map(\.method)
                parents += context.jvmImports?.classes[name]?.methods.filter { !$0.isStatic && !$0.isConstructor } ?? known.filter { $0.owner == name && !$0.isStatic && !$0.isConstructor }.sorted { $0.name + $0.descriptor < $1.name + $1.descriptor }
            }
            for next in sema.symbols.directSupertypes(for: symbol) { visit(next) }
        }
        for parent in sema.symbols.directSupertypes(for: plan.symbol) { visit(parent) }
        var bridges: [JVMFunction] = [], signatures = Set(functions.map { $0.reference.name + $0.reference.descriptor })
        let declaredPhysicalSignatures = Set(functions.map { function in
            let name = function.reference.name
            let physical = name.range(of: "$jvmName$").map { String(name[$0.upperBound...]) } ?? name
            return physical + function.reference.descriptor
        })
        let inheritedPhysicalAliases = Set(parents.compactMap { method -> String? in
            guard !method.isSpecial, !method.isStatic, !method.isAbstract,
                  let alias = method.name.range(of: "$jvmName$") else { return nil }
            return String(method.name[alias.upperBound...]) + method.descriptor
        })
        var implementations = functions
        func dispatchKey(_ name: String, _ parameters: [JVMValueType]) -> String { name + "(" + parameters.map(\.descriptor).joined() + ")" }
        var selected = Set(functions.filter { !$0.isConstructor }.map { dispatchKey($0.reference.name, $0.reference.parameters) })
        // A concrete inherited class method can satisfy a new interface with
        // a covariant return type. Its bridge belongs to this implementing
        // class even though the implementation itself is declared upstream.
        for inherited in parents.filter({ !$0.isInterface }) + parents.filter({ $0.isInterface }) where !inherited.isSpecial && !inherited.isConstructor && !inherited.isStatic {
            guard selected.insert(dispatchKey(inherited.name, inherited.parameters)).inserted, !inherited.isAbstract else { continue }
            implementations.append(JVMFunction(reference: JVMFunctionReference(name: inherited.name, parameters: inherited.parameters, result: inherited.result), isPrivate: false, locals: [], parameterCount: 0, instructions: [], parameterNames: inherited.parameters.indices.map { "p\($0)" }, isInternal: false))
        }
        func matchesSourceName(_ parent: JVMForeignMethod, _ function: JVMFunction) -> Bool {
            let name = function.sourceName ?? function.reference.name
            if parent.owner == "java/util/List", parent.name == "remove" {
                // Kotlin's element removal and indexed removal are distinct
                // overloads even when their specialized parameter is Int.
                return name == (parent.parameters == [.int] ? "removeAt" : "remove")
            }
            return parent.name == name
        }
        for function in implementations where !function.isConstructor && !function.isPrivate && !function.isAbstract {
            let ref = function.reference
            for parent in parents where !parent.isSpecial && matchesSourceName(parent, function) &&
                (specializedParameters[parent.owner + parent.name + parent.descriptor] ?? parent.parameters).map(\.descriptor) == ref.parameters.map(\.descriptor) && parent.descriptor != ref.descriptor {
                guard (parent.result == .unit) == (ref.result == .unit), parent.parameters.count == ref.parameters.count else { throw JVMFrontendError(message: "Unsupported JVM override bridge.") }
                let boxedResult = JVMClasspathIndex.boxed(ref.result)
                if boxedResult != ref.result, parent.result.referenceName == "java/lang/Object",
                   JVMClasspathIndex.collectionNames.values.contains(parent.owner) {
                    let descriptor = "(" + ref.parameters.map(\.descriptor).joined() + ")" + boxedResult.descriptor
                    if !declaredPhysicalSignatures.contains(parent.name + descriptor),
                       !inheritedPhysicalAliases.contains(parent.name + descriptor),
                       signatures.insert(parent.name + descriptor).inserted {
                        // Kotlin consumers call a boxed specialization of a
                        // collection element result as well as its Object bridge.
                        let b = try nominalBuilder(plan, name: parent.name, parameters: ref.parameters, result: boxedResult)
                        let result = try b.value(ref.result)
                        let call = JVMForeignMethod(owner: plan.name, name: ref.name, descriptor: ref.descriptor, parameters: ref.parameters, result: ref.result, isStatic: false, isInterface: plan.isInterface, isAbstract: false)
                        b.instructions.append(.foreignCall(call, receiver: b.thisValue!, arguments: Array(b.locals.dropFirst().prefix(ref.parameters.count)), result: result))
                        b.instructions.append(.returnValue(try b.convert(result, to: boxedResult)))
                        var boxed = b.finish(); boxed.access = 0x1041; bridges.append(boxed)
                    }
                }
                guard signatures.insert(parent.name + parent.descriptor).inserted else { continue }
                var locals = [JVMValue(slot: 0, type: .reference(plan.name, nullable: false))], slot = 1
                for type in parent.parameters { locals.append(JVMValue(slot: slot, type: type)); slot += type.width }
                let parameters = Array(locals.dropFirst())
                var instructions: [JVMInstruction] = [], arguments: [JVMValue] = []
                let collection = JVMClasspathIndex.collectionNames.values.contains(parent.owner)
                let rejected: JVMConstant?
                if collection && ["contains", "remove", "containsKey", "containsValue"].contains(parent.name) && parent.result == .boolean { rejected = .boolean(false) }
                else if collection && ["indexOf", "lastIndexOf"].contains(parent.name) && parent.result == .int { rejected = .int(-1) }
                else if parent.owner == "java/util/Map" && ["get", "remove"].contains(parent.name) && parent.result.referenceName != nil { rejected = .null }
                else { rejected = nil }
                var hasTypeBarrier = false
                var nextLabel = 1
                for (source, target) in zip(parameters, ref.parameters) {
                    if rejected != nil, source.type.referenceName == "java/lang/Object",
                       let expected = JVMClasspathIndex.boxed(target).referenceName, expected != "java/lang/Object" {
                        // Collection lookup bridges reject unrelated element/key
                        // types without entering a specialized implementation.
                        let accepted = nextLabel; nextLabel += 1
                        if target.isNullable {
                            let null = JVMValue(slot: slot, type: source.type); slot += 1; locals.append(null)
                            let nonNull = JVMValue(slot: slot, type: .boolean); slot += 1; locals.append(nonNull)
                            instructions += [.constant(.null, null), .referenceCompare(.notEqual, source, null, nonNull), .jumpIfFalse(nonNull, accepted)]
                        }
                        let check = JVMValue(slot: slot, type: .boolean); slot += 1; locals.append(check)
                        instructions += [.instanceOf(source, expected, check), .jumpIfFalse(check, 0), .label(accepted)]
                        hasTypeBarrier = true
                    }
                    let converted = JVMValue(slot: slot, type: target); slot += target.width; locals.append(converted)
                    instructions.append(.copy(source, converted)); arguments.append(converted)
                }
                let result = ref.result == .unit ? nil : JVMValue(slot: slot, type: ref.result)
                if let result { slot += result.type.width; locals.append(result) }
                let returned = parent.result == .unit ? nil : JVMValue(slot: slot, type: parent.result)
                if let returned { slot += returned.type.width; locals.append(returned) }
                var call = JVMForeignMethod(owner: plan.name, name: ref.name, descriptor: ref.descriptor, parameters: ref.parameters, result: ref.result, isStatic: false, isInterface: plan.isInterface, isAbstract: false)
                call.isSuspend = parent.isSuspend
                instructions.append(.foreignCall(call, receiver: locals[0], arguments: arguments, result: result))
                if let result, let returned { instructions.append(.copy(result, returned)) }
                instructions.append(.returnValue(returned))
                if hasTypeBarrier, let rejected {
                    let fallback = JVMValue(slot: slot, type: parent.result); locals.append(fallback)
                    instructions += [.label(0), .constant(rejected, fallback), .returnValue(fallback)]
                }
                var bridge = JVMFunction(reference: JVMFunctionReference(name: parent.name, parameters: parent.parameters, result: parent.result), isPrivate: false, locals: locals, parameterCount: parent.parameters.count + 1, instructions: instructions, parameterNames: function.parameterNames, isInternal: false)
                bridge.owner = plan.name; bridge.access = 0x1041
                bridge.isSuspend = parent.isSuspend
                bridges.append(bridge)
            }
        }
        return bridges
    }
}

extension JVMFunctionBuilder {
    func statements(_ body: FunctionBody) throws {
        switch body {
        case let .block(statements, _):
            scopes.append([:]); defer { scopes.removeLast() }
            for statement in statements where !terminated { _ = try expression(statement, discarded: true) }
        case let .expr(expr, _): _ = try expression(expr, discarded: true)
        case .unit: break
        }
    }
}
