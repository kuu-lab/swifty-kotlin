import Foundation

extension JVMProgramBuilder {
    func prepareDelegateInterfaces() throws {
        for symbol in sema.symbols.allSymbols() where symbol.kind == .function {
            guard let parent = sema.symbols.parentSymbol(for: symbol.id), let name = try? className(parent), ["kotlin/properties/ReadOnlyProperty", "kotlin/properties/ReadWriteProperty", "kotlin/Lazy"].contains(name), let sig = sema.symbols.functionSignature(for: symbol.id) else { continue }
            let params = try sig.parameterTypes.map(type), result = try type(sig.returnType)
            methods[symbol.id] = JVMForeignMethod(owner: name, name: context.interner.resolve(symbol.name), descriptor: "(" + params.map(\.descriptor).joined() + ")" + result.descriptor, parameters: params, result: result, isStatic: false, isInterface: true, isAbstract: true)
        }
    }

    func prepareLazyProperty() throws {
        for symbol in sema.symbols.allSymbols() where symbol.kind == .property {
            guard let parent = sema.symbols.parentSymbol(for: symbol.id), (try? className(parent)) == "kotlin/Lazy", context.interner.resolve(symbol.name) == "value", let semantic = sema.symbols.propertyType(for: symbol.id) else { continue }
            let result = try type(semantic)
            let getter = JVMForeignMethod(owner: "kotlin/Lazy", name: "getValue", descriptor: "()" + result.descriptor, parameters: [], result: result, isStatic: false, isInterface: true, isAbstract: true)
            properties[symbol.id] = JVMProperty(name: "value", type: result, getter: getter, setter: nil, field: nil, modifiers: [.abstract])
            methods[SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol.id)] = getter
        }
    }

    func needsDelegateToken(_ symbol: SymbolID) -> Bool {
        !isLazyDelegate(symbol) || sema.symbols.delegateProvideDelegateSymbol(for: symbol) != nil
    }

    func isLazyDelegate(_ symbol: SymbolID) -> Bool {
        guard let accessor = sema.symbols.delegateGetValueSymbol(for: symbol), let s = sema.symbols.symbol(accessor) else { return false }
        return s.fqName.map(context.interner.resolve).starts(with: ["kotlin"]) && context.interner.resolve(s.name) == "getValue" && sema.symbols.functionSignature(for: accessor)?.receiverType.flatMap({ try? type($0).referenceName }) == "kotlin/Lazy"
    }

    func prepareClassDelegates() throws {
        for plan in classes.values.sorted(by: { $0.name < $1.name }) {
            let entries = plan.declaration?.superTypeEntries ?? []
            let interfaces = sema.symbols.delegatedInterfaces(forClass: plan.symbol).sorted { left, right in
                let a = sema.symbols.classDelegationExpr(forClass: plan.symbol, interface: left)
                let b = sema.symbols.classDelegationExpr(forClass: plan.symbol, interface: right)
                return (entries.firstIndex { $0.delegateExpression == a } ?? Int.max) < (entries.firstIndex { $0.delegateExpression == b } ?? Int.max)
            }
            for interface in interfaces {
                guard let expr = sema.symbols.classDelegationExpr(forClass: plan.symbol, interface: interface), let symbol = sema.symbols.classDelegationField(forClass: plan.symbol, interface: interface), let semantic = sema.symbols.propertyType(for: symbol) else { throw JVMFrontendError(message: "Missing JVM class delegation binding.") }
                let field = JVMField(owner: plan.name, name: "$delegate$" + String(plan.delegateFields.count), type: try type(semantic), access: plan.isObject ? 0x1002 : 0x1012)
                plan.delegateFields.append((symbol, expr, field))
            }
        }
        // Interface declarations are all registered before forwarding symbols.
        for plan in classes.values.sorted(by: { $0.name < $1.name }) {
            for symbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: plan.symbol) {
                guard let info = sema.symbols.classDelegationForwardingMethodInfo(for: symbol) else { throw JVMFrontendError(message: "Missing JVM delegated interface method binding.") }
                let target = methods[info.interfaceMethodSymbol] ?? collectionInterfaceMethods[info.interfaceMethodSymbol] ?? context.jvmImports?.methods[info.interfaceMethodSymbol]
                if target == nil, let member = sema.symbols.symbol(info.interfaceMethodSymbol), member.flags.contains(.synthetic),
                   let parent = sema.symbols.parentSymbol(for: member.id), (try? className(parent))?.hasPrefix("kotlin/collections/") == true {
                    // Native bootstrap lookup shims (for example random) are
                    // extensions rather than members of the JVM interface.
                    continue
                }
                guard let target, let field = plan.delegateFields.first(where: { $0.0 == info.fieldSymbol })?.2, let sig = sema.symbols.functionSignature(for: symbol) else { throw JVMFrontendError(message: "Unsupported JVM delegated interface method.") }
                if target.owner == "java/util/Map", context.interner.resolve(sema.symbols.symbol(info.interfaceMethodSymbol)!.name) == "set" {
                    // Kotlin's indexed assignment shares Map.put's physical
                    // entry point and discards its return value at the call site.
                    methods[symbol] = target
                    continue
                }
                let isExtension = extensionSymbols.contains(info.interfaceMethodSymbol)
                if isExtension { extensionSymbols.insert(symbol) }
                let params = try ((isExtension ? [sig.receiverType].compactMap { $0 } : []) + sig.parameterTypes).map(type), result = try type(sig.returnType)
                var method = JVMForeignMethod(owner: plan.name, name: target.name, descriptor: "(" + params.map(\.descriptor).joined() + ")" + result.descriptor, parameters: params, result: result, isStatic: false, isInterface: false, isAbstract: false)
                method.isSuspend = target.isSuspend
                methods[symbol] = method
                sourceParameters[symbol] = sourceParameters[info.interfaceMethodSymbol]
                sourceDeclarations[symbol] = sourceDeclarations[info.interfaceMethodSymbol]
                plan.delegatedMethods.append((symbol, method, target, field))
            }
            for symbol in sema.symbols.classDelegationForwardingPropertySymbols(forClass: plan.symbol) {
                guard let info = sema.symbols.classDelegationForwardingPropertyInfo(for: symbol), let target = properties[info.interfacePropertySymbol], let field = plan.delegateFields.first(where: { $0.0 == info.fieldSymbol })?.2, let semantic = sema.symbols.propertyType(for: symbol) else { throw JVMFrontendError(message: "Unsupported JVM delegated interface property.") }
                let value = try type(semantic)
                func method(_ original: JVMForeignMethod, setter: Bool) -> JVMForeignMethod {
                    JVMForeignMethod(owner: plan.name, name: original.name, descriptor: setter ? "(" + value.descriptor + ")V" : "()" + value.descriptor, parameters: setter ? [value] : [], result: setter ? .unit : value, isStatic: false, isInterface: false, isAbstract: false)
                }
                var property = JVMProperty(name: target.name, type: value, getter: method(target.getter, setter: false), setter: target.setter.map { method($0, setter: true) }, field: nil, modifiers: [.override])
                property.kotlinType = try kotlinType(semantic); property.genericSignature = try signatureType(semantic)
                properties[symbol] = property; plan.delegatedProperties.append((property, target, field))
            }
        }
    }

    func emitClassDelegates(_ plan: JVMClassPlan, builder: JVMFunctionBuilder, object: JVMValue) throws {
        for (_, expression, field) in plan.delegateFields {
            let input = try builder.convert(builder.requireValue(expression), to: field.type)
            builder.instructions.append(.putField(field, object, input))
        }
    }

    func delegationMethods(_ plan: JVMClassPlan) throws -> [JVMFunction] {
        func forwarding(_ method: JVMForeignMethod, _ target: JVMForeignMethod, _ field: JVMField) throws -> JVMFunction {
            let b = try nominalBuilder(plan, name: method.name, parameters: method.parameters, result: method.result)
            let delegate = try b.value(field.type); b.instructions.append(.getField(field, b.thisValue!, delegate))
            var args: [JVMValue] = []
            for (input, type) in zip(Array(b.locals.dropFirst().prefix(method.parameters.count)), target.parameters) { args.append(try b.convert(input, to: type)) }
            let result = target.result == .unit ? nil : try b.value(target.result)
            b.instructions.append(.foreignCall(target, receiver: delegate, arguments: args, result: result))
            b.instructions.append(.returnValue(method.result == .unit ? nil : try result.map { try b.convert($0, to: method.result) }))
            var f = b.finish(); f.access = 1; f.isSuspend = target.isSuspend
            return f
        }
        var functions: [JVMFunction] = []
        for (symbol, method, target, field) in plan.delegatedMethods {
            let sig = sema.symbols.functionSignature(for: symbol)!
            var f = try describe(forwarding(method, target, field), signature: sig, parameters: sourceDeclarations[symbol]?.typeParams ?? [])
            if let original = sema.symbols.functionSignature(for: symbol) { f.parameterNames = original.valueParameterSymbols.enumerated().map { sema.symbols.symbol($0.element).map { context.interner.resolve($0.name) } ?? "p\($0.offset)" } }
            if JVMClasspathIndex.collectionNames.values.contains(target.owner) {
                if let signature = f.genericSignature, let end = signature.lastIndex(of: ")") {
                    // JVM collection returns use invariant Java type arguments;
                    // declaration-site Kotlin covariance stays in metadata.
                    f.genericSignature = String(signature[...end]) + signature[signature.index(after: end)...].replacingOccurrences(of: "+", with: "")
                }
                if ["containsAll", "removeAll", "retainAll"].contains(target.name) {
                    f.genericSignature = "(Ljava/util/Collection<*>;)Z"
                }
            }
            let original = sema.symbols.classDelegationForwardingMethodInfo(for: symbol)?.interfaceMethodSymbol ?? symbol
            f.isOperator = sema.symbols.symbol(original)?.flags.contains(.operatorFunction) == true
            f.sourceName = sema.symbols.symbol(symbol).map { context.interner.resolve($0.name) }
            functions.append(f)
        }
        for (property, target, field) in plan.delegatedProperties {
            var getter = try forwarding(property.getter, target.getter, field)
            getter.kotlinResult = property.kotlinType; getter.genericSignature = "()" + (property.genericSignature ?? property.type.descriptor).replacingOccurrences(of: "+", with: "")
            functions.append(getter)
            if let setter = property.setter, let targetSetter = target.setter {
                var f = try forwarding(setter, targetSetter, field)
                f.kotlinParameters = [property.kotlinType].compactMap { $0 }; f.genericSignature = "(" + (property.genericSignature ?? property.type.descriptor) + ")V"
                functions.append(f)
            }
        }
        return functions
    }

    func propertyTokenInitializer(_ plan: JVMClassPlan) throws -> JVMFunction {
        let b = try nominalBuilder(plan, name: "<clinit>", staticBody: true)
        for (symbol, field) in plan.propertyTokens.sorted(by: { $0.value.name < $1.value.name }) {
            let property = properties[symbol]!
            let token = try b.propertyToken(name: property.name, owner: plan.name, signature: property.getter.name + property.getter.descriptor, topLevel: plan.isFacade, mutable: property.setter != nil)
            b.instructions.append(.putStatic(field, try b.convert(token, to: field.type)))
        }
        b.instructions.append(.returnValue(nil)); var f = b.finish(); f.access = 8; return f
    }
}
