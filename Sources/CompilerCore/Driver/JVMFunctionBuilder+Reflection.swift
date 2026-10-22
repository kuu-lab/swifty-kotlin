import Foundation

extension JVMProgramBuilder {
    func classTokenType(_ type: TypeID) throws -> JVMValueType {
        if case let .classType(t) = sema.types.kind(of: type) {
            let name = try className(t.classSymbol)
            let builtins: [String: JVMValueType] = ["kotlin/Byte": .byte, "kotlin/Short": .short, "kotlin/Char": .char, "kotlin/UInt": .uint, "kotlin/ULong": .ulong, "kotlin/UByte": .ubyte, "kotlin/UShort": .ushort, "kotlin/Int": .int, "kotlin/Long": .long, "kotlin/Float": .float, "kotlin/Double": .double, "kotlin/Boolean": .boolean, "kotlin/String": .string, "kotlin/Any": .reference("java/lang/Object", nullable: false), "kotlin/Unit": .reference("kotlin/Unit", nullable: false)]
            if let value = builtins[name] { return value }
        }
        return try self.type(type)
    }
}

extension JVMFunctionBuilder {
    func javaClass(_ type: JVMValueType) throws -> JVMValue {
        let result = try value(.reference("java/lang/Class", nullable: false))
        let wrappers: [JVMValueType: String] = [.byte: "Byte", .short: "Short", .char: "Character", .int: "Integer", .long: "Long", .float: "Float", .double: "Double", .boolean: "Boolean", .unit: "Void"]
        if let wrapper = wrappers[type] {
            instructions.append(.getStatic(JVMField(owner: "java/lang/" + wrapper, name: "TYPE", type: result.type, access: 0x19), result)); return result
        }
        instructions.append(.classLiteral(type.unsignedName ?? type.referenceName!, result))
        return result
    }
    func reflectionReference(_ id: ExprID, receiver: ExprID?, member: InternedString) throws -> JVMValue {
        if context.interner.resolve(member) == "class" {
            guard let semantic = program.sema.bindings.classRefTargetType(for: id) else { throw fail("Missing JVM class literal type.", id) }
            let klass: JVMValue
            if program.sema.bindings.boundClassRefExprs.contains(id), let receiver {
                let object = try convert(requireValue(receiver), to: .reference("java/lang/Object", nullable: false))
                klass = try jdkCall("java/lang/Object", "getClass", [], .reference("java/lang/Class", nullable: false), receiver: object)!
            } else if let token = try runtimeReifiedToken(semantic) {
                klass = token.klass
            } else if let name = program.reifiedUse(semantic) {
                klass = try value(.reference("java/lang/Class", nullable: false))
                instructions.append(.reifiedOperation(4, name, nil, klass))
            } else {
                let token = try program.classTokenType(program.specialized(semantic))
                klass = try javaClass(program.isReifiedParameter(semantic) ? (token == .unit ? .reference("kotlin/Unit", nullable: false) : JVMClasspathIndex.boxed(token)) : token)
            }
            return try jdkCall("kotlin/jvm/internal/Reflection", "getOrCreateKotlinClass", [klass.type], .reference("kotlin/reflect/KClass", nullable: false), arguments: [klass])!
        }
        guard let symbol = program.sema.bindings.callableReferenceBinding(for: id)?.chosenCallee ?? program.sema.bindings.identifierSymbol(for: id) else { throw fail("Missing JVM callable reference binding.", id) }
        if let local = program.localFunctions[symbol] {
            return try localFunctionReference(id, symbol: symbol, receiver: receiver, plan: local)
        }
        let unbound = program.sema.bindings.isUnboundCallableRef(id)
        if let property = program.properties[symbol] {
            let bound = property.getter.isStatic || unbound ? nil : try receiver.map(requireValue) ?? instance(id)
            let arity = !property.getter.isStatic && unbound ? 1 : 0
            let name = "kotlin/jvm/internal/" + (property.setter == nil ? "PropertyReference" : "MutablePropertyReference") + String(arity) + "Impl"
            let klass = try javaClass(.reference(property.getter.owner, nullable: false))
            var args: [JVMValue] = []
            var params: [JVMValueType] = []
            if let bound { params.append(.reference("java/lang/Object", nullable: true)); args.append(try convert(bound, to: params[0])) }
            params += [klass.type, .string, .string, .int]
            let signature = try value(.string)
            instructions.append(.callableSignature(property.getter.owner, property.getter.name, property.getter.descriptor, signature))
            args += [klass, try constant(.string(property.name), .string), signature, try constant(.int(property.getter.isStatic ? 1 : 0), .int)]
            return try constructJDK(name, parameters: params, arguments: args)
        }
        if program.sema.symbols.functionSignature(for: symbol)?.reifiedTypeParameterIndices.isEmpty == false {
            return try reifiedReference(id, symbol: symbol, receiver: receiver, unbound: unbound)
        }
        if let binding = program.sema.bindings.callableReferenceBinding(for: id), let function = functionType(id),
           let signature = program.sema.symbols.functionSignature(for: symbol) {
            let unitConversion = try program.type(function.returnType) == .unit && program.type(signature.returnType) != .unit
            if binding.isCallableReferenceAdapter || function.isSuspend != signature.isSuspend || unitConversion {
                return try adaptedReference(id, symbol: symbol, receiver: receiver, unbound: unbound)
            }
        }
        // Source-backed inline declarations also retain an ordinary runtime
        // entry for references, independently of call-site body expansion.
        let sourceBacked = program.inlineDeclarations[symbol] != nil ? program.textLibraryMethods[symbol] : nil
        let method = program.methods[symbol] ?? context.jvmImports?.methods[symbol] ?? sourceBacked?.method
        let ref = program.references[symbol]
        guard method != nil || ref != nil else { throw fail("Unsupported JVM callable reference target.", id) }
        let constructor = method?.isConstructor == true
        let isExtension = program.extensionSymbols.contains(symbol) || sourceBacked?.extensionReceiver != nil
        let ownerName = ref?.owner ?? method!.owner
        let staticTarget = ref != nil || method?.isStatic == true
        let bound = !unbound && !constructor && (!staticTarget || isExtension) ? try receiver.map(requireValue) ?? instance(id) : nil
        let params = ref?.parameters ?? method!.parameters
        let suspended = ref?.isSuspend ?? method?.isSuspend ?? false
        let arity = params.count + (!staticTarget && !constructor && bound == nil ? 1 : 0) - (staticTarget && isExtension && bound != nil ? 1 : 0) + (suspended ? 1 : 0)
        guard arity <= 22 else { throw fail("JVM callable reference arity exceeds 22.", id) }
        let targetName = ref?.name ?? method!.name
        let name = constructor ? "<init>" : program.sema.symbols.symbol(symbol).map { context.interner.resolve($0.name) } ?? targetName.components(separatedBy: "$unsigned$")[0]
        let signature = try value(.string)
        instructions.append(.callableSignature(ownerName, targetName, ref?.descriptor ?? method!.descriptor, signature))
        let klass = try javaClass(.reference(ownerName, nullable: false))
        var values = [try constant(.int(Int32(arity)), .int)]
        var types: [JVMValueType] = [.int]
        if let bound { let object: JVMValueType = .reference("java/lang/Object", nullable: true); types.append(object); values.append(try convert(bound, to: object)) }
        types += [klass.type, .string, .string, .int]
        values += [klass, try constant(.string(name), .string), signature, try constant(.int(staticTarget ? 1 : 0), .int)]
        let number = program.nextClosure; program.nextClosure += 1
        let generated = program.facadeName + "$Reference" + String(number)
        program.functionArities.insert(arity)
        let receiverType: JVMValueType = .reference(generated, nullable: false)
        let own = JVMValue(slot: 0, type: receiverType)
        var locals = [own], slot = 1
        for type in types { locals.append(JVMValue(slot: slot, type: type)); slot += type.width }
        let superMethod = JVMForeignMethod(owner: "kotlin/jvm/internal/FunctionReferenceImpl", name: "<init>", descriptor: "(" + types.map(\.descriptor).joined() + ")V", parameters: types, result: .reference("kotlin/jvm/internal/FunctionReferenceImpl", nullable: false), isStatic: false, isInterface: false, isAbstract: false)
        let ctor = program.rawFunction(generated, name: "<init>", parameters: types, result: .unit, access: 1, locals: locals, instructions: [.foreignCall(superMethod, receiver: own, arguments: Array(locals.dropFirst()), result: nil), .returnValue(nil)], constructor: true)
        let b = JVMFunctionBuilder(program: program, declaration: FunDecl(range: arena.exprRange(id)!, name: context.interner.intern("invoke"), modifiers: [], body: .unit), reference: JVMFunctionReference(name: "invoke", parameters: Array(repeating: .reference("java/lang/Object", nullable: true), count: arity), result: .reference("java/lang/Object", nullable: true)))
        b.thisValue = try b.value(receiverType)
        let inputs = try b.reference.parameters.map { try b.value($0) }
        let array = try b.objectArray(suspended ? Array(inputs.dropLast()) : inputs)
        let start = b.label(), end = b.label(), handler = b.label()
        b.mark(start)
        let returned: JVMValue
        if suspended {
            returned = try b.jdkCall("kotlin/reflect/full/KCallables", "callSuspend", [.reference("kotlin/reflect/KCallable", nullable: false), array.type, .reference("kotlin/coroutines/Continuation", nullable: false)], b.reference.result, arguments: [b.thisValue!, array, inputs.last!])!
        } else {
            returned = try b.jdkCall("kotlin/reflect/KCallable", "call", [array.type], b.reference.result, receiver: b.thisValue, arguments: [array], interface: true)!
        }
        b.mark(end)
        b.instructions.append(.returnValue(returned))
        let exception = try b.value(.reference("java/lang/reflect/InvocationTargetException", nullable: false))
        b.instructions.append(.exceptionHandler(handler, exception, preserving: []))
        let cause = try b.jdkCall("java/lang/reflect/InvocationTargetException", "getCause", [], .reference("java/lang/Throwable", nullable: false), receiver: exception)!
        b.instructions.append(.throwValue(cause))
        b.handlers.append(JVMExceptionHandler(start: start, end: end, handler: handler, type: "java/lang/reflect/InvocationTargetException"))
        var invoke = b.finish(); invoke.owner = generated; invoke.access = 0x11; invoke.parameterCount = arity + 1
        var declaration = JVMClass(name: generated, superclass: "kotlin/jvm/internal/FunctionReferenceImpl", interfaces: ["kotlin/jvm/functions/Function" + String(arity)], access: 0x1031, functions: [ctor, invoke], properties: [])
        declaration.emitMetadata = false; program.closureClasses.append(declaration)
        return try constructJDK(generated, parameters: types, arguments: values)
    }
    func objectArray(_ values: [JVMValue]) throws -> JVMValue {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let result = try value(.reference("[Ljava/lang/Object;", nullable: false)), count = try constant(.int(Int32(values.count)), .int)
        instructions.append(.newArray(object, count: count, result: result))
        for (i, element) in values.enumerated() { instructions.append(.arraySet(result, try constant(.int(Int32(i)), .int), try convert(element, to: object))) }
        return result
    }
    func reflectionMember(_ receiverID: ExprID, name: String, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        let resolved = try? program.expressionType(receiverID)
        guard let sourceType = resolved ?? (program.sema.bindings.classRefTargetType(for: receiverID) == nil ? nil : .reference("kotlin/reflect/KClass", nullable: false)) else { return nil }
        let ownerName = sourceType.referenceName ?? ""
        let isClass = ownerName == "kotlin/reflect/KClass"
        let isCallable = ownerName.hasPrefix("kotlin/reflect/K") || program.sema.bindings.callableRefKind(for: receiverID) != nil || ownerName.hasPrefix("kotlin/jvm/functions/Function")
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        if name == "findAnnotations", args.isEmpty, isCallable {
            guard let semantic = program.sema.bindings.exprType(for: id), case let .classType(list) = program.sema.types.kind(of: semantic), let argument = list.args.first else { throw fail("Missing JVM repeatable annotation type.", id) }
            let annotationType: TypeID
            switch argument { case let .invariant(t), let .out(t), let .in(t): annotationType = t; case .star: throw fail("JVM findAnnotations needs a concrete annotation type.", id) }
            let klass = try javaClass(program.type(annotationType))
            let kotlinClass = try jdkCall("kotlin/jvm/internal/Reflection", "getOrCreateKotlinClass", [klass.type], .reference("kotlin/reflect/KClass", nullable: false), arguments: [klass])!
            return JVMIntrinsicResult(value: try jdkCall("kotlin/reflect/full/KAnnotatedElements", "findAnnotations", [.reference("kotlin/reflect/KAnnotatedElement", nullable: false), kotlinClass.type], .reference("java/util/List", nullable: false), arguments: [requireValue(receiverID), kotlinClass], resolved: program.expressionType(id)))
        }
        if ownerName == "java/lang/Class", name == "getAnnotationsByType", args.count == 1 {
            return JVMIntrinsicResult(value: try jdkCall(ownerName, name, [.reference("java/lang/Class", nullable: false)], .reference("[Ljava/lang/annotation/Annotation;", nullable: false), receiver: requireValue(receiverID), arguments: [requireValue(args[0].expr)], resolved: program.expressionType(id)))
        }
        if name == "findAnnotation", args.isEmpty, let target = try? program.expressionType(id), let targetName = target.referenceName, isCallable {
            let receiver = try convert(requireValue(receiverID), to: .reference("kotlin/reflect/KAnnotatedElement", nullable: false))
            let annotations = try jdkCall("kotlin/reflect/KAnnotatedElement", "getAnnotations", [], .reference("java/util/List", nullable: false), receiver: receiver, interface: true)!
            let iterator = try jdkCall("java/util/List", "iterator", [], .reference("java/util/Iterator", nullable: false), receiver: annotations, interface: true)!
            let result = try constant(.null, target), loop = label(), end = label(), next = label()
            mark(loop)
            let more = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)!
            instructions.append(.jumpIfFalse(more, end))
            let annotation = try jdkCall("java/util/Iterator", "next", [], object, receiver: iterator, interface: true)!
            let check = try value(.boolean)
            instructions += [.instanceOf(annotation, targetName, check), .jumpIfFalse(check, next)]
            let matched = try convert(annotation, to: target)
            instructions.append(.copy(matched, result))
            jump(end); mark(next); jump(loop); mark(end)
            return JVMIntrinsicResult(value: result)
        }
        if ownerName == "java/lang/Class", name == "getAnnotation", args.count == 1 {
            return JVMIntrinsicResult(value: try jdkCall(ownerName, name, [.reference("java/lang/Class", nullable: false)], .reference("java/lang/annotation/Annotation", nullable: true), receiver: requireValue(receiverID), arguments: [requireValue(args[0].expr)], resolved: program.expressionType(id)))
        }
        if isClass, name == "java", args.isEmpty {
            return JVMIntrinsicResult(value: try jdkCall("kotlin/jvm/JvmClassMappingKt", "getJavaClass", [sourceType], .reference("java/lang/Class", nullable: false), arguments: [requireValue(receiverID)]))
        }
        if name == "javaClass", args.isEmpty {
            let receiver = try convert(requireValue(receiverID), to: .reference("java/lang/Object", nullable: false))
            return JVMIntrinsicResult(value: try jdkCall("java/lang/Object", "getClass", [], .reference("java/lang/Class", nullable: false), receiver: receiver))
        }
        if ownerName == "java/lang/Class", name == "kotlin", args.isEmpty { return JVMIntrinsicResult(value: try jdkCall("kotlin/jvm/JvmClassMappingKt", "getKotlinClass", [sourceType], .reference("kotlin/reflect/KClass", nullable: false), arguments: [requireValue(receiverID)])) }
        if isClass && ["memberProperties", "memberFunctions", "createInstance"].contains(name) {
            let result: JVMValueType = name == "createInstance" ? object : .reference("java/util/Collection", nullable: false)
            return JVMIntrinsicResult(value: try jdkCall("kotlin/reflect/full/KClasses", name == "createInstance" ? name : "get" + name.prefix(1).uppercased() + name.dropFirst(), [sourceType], result, arguments: [requireValue(receiverID)], resolved: program.expressionType(id)))
        }
        guard isCallable || ownerName == "java/lang/Class" else { return nil }
        let receiver = try requireValue(receiverID)
        if name == "call", isCallable {
            var values: [JVMValue] = []
            for arg in args { guard !arg.isSpread else { throw fail("JVM reflection call spread arguments are unsupported.", id) }; values.append(try requireValue(arg.expr)) }
            let array = try objectArray(values)
            let logical = try program.expressionType(id)
            let resultType: JVMValueType = logical == .unit ? .reference("kotlin/Unit", nullable: false) : logical
            return JVMIntrinsicResult(value: try jdkCall("kotlin/reflect/KCallable", "call", [array.type], object, receiver: convert(receiver, to: .reference("kotlin/reflect/KCallable", nullable: false)), arguments: [array], interface: true, resolved: resultType))
        }
        if name == "callBy", isCallable {
            guard args.count == 1, !args[0].isSpread else { throw fail("JVM reflection callBy requires one argument map.", id) }
            let mapType: JVMValueType = .reference("java/util/Map", nullable: false)
            let arguments = try convert(requireValue(args[0].expr), to: mapType)
            let logical = try program.expressionType(id)
            let resultType: JVMValueType = logical == .unit ? .reference("kotlin/Unit", nullable: false) : logical
            return JVMIntrinsicResult(value: try jdkCall("kotlin/reflect/KCallable", "callBy", [mapType], object, receiver: convert(receiver, to: .reference("kotlin/reflect/KCallable", nullable: false)), arguments: [arguments], interface: true, resolved: resultType))
        }
        let propertyOwner = ownerName.hasPrefix("kotlin/reflect/KMutableProperty") ? ownerName : (ownerName.hasPrefix("kotlin/reflect/KProperty") ? ownerName : nil)
        if let propertyOwner, ["get", "set"].contains(name), arena.isExplicitCall(id) {
            let types = Array(repeating: object, count: args.count)
            let values = try args.map { try requireValue($0.expr) }
            return JVMIntrinsicResult(value: try jdkCall(propertyOwner, name, types, name == "set" ? .unit : object, receiver: receiver, arguments: values, interface: true, resolved: name == "set" ? .unit : program.expressionType(id)))
        }
        if name == "isInstance", args.count == 1, isClass || ownerName == "java/lang/Class" {
            return JVMIntrinsicResult(value: try jdkCall(ownerName, name, [object], .boolean, receiver: receiver, arguments: [requireValue(args[0].expr)], interface: isClass))
        }
        if !arena.isExplicitCall(id), args.isEmpty {
            let callableProperties = ["name", "parameters", "returnType", "isInline", "isOperator", "isSuspend", "isLateinit", "isConst"]
            let classProperties = ["simpleName", "qualifiedName", "members", "constructors", "nestedClasses", "objectInstance", "isFinal", "isOpen", "isAbstract", "isSealed", "isData", "isInner", "isCompanion", "isFun", "isValue"]
            var declaring: String?
            var result = try program.expressionType(id)
            if name == "annotations" { declaring = "kotlin/reflect/KAnnotatedElement"; result = .reference("java/util/List", nullable: false) }
            else if isClass, classProperties.contains(name) { declaring = ownerName }
            else if ownerName == "java/lang/Class", ["name", "simpleName", "isAnnotation"].contains(name) { declaring = ownerName }
            else if ["kotlin/reflect/KParameter", "kotlin/reflect/KType"].contains(ownerName) { declaring = ownerName }
            else if callableProperties.contains(name) { declaring = ["isInline", "isOperator", "isSuspend"].contains(name) ? "kotlin/reflect/KFunction" : (["isLateinit", "isConst"].contains(name) ? "kotlin/reflect/KProperty" : "kotlin/reflect/KCallable") }
            if let declaring {
                if name == "objectInstance" { result = object }
                if name == "classifier" { result = .reference("kotlin/reflect/KClassifier", nullable: true) }
                let methodName = name.hasPrefix("is") ? name : "get" + name.prefix(1).uppercased() + name.dropFirst()
                return JVMIntrinsicResult(value: try jdkCall(declaring, methodName, [], result, receiver: convert(receiver, to: .reference(declaring, nullable: false)), interface: declaring != "java/lang/Class", resolved: program.expressionType(id)))
            }
        }
        return nil
    }
}
