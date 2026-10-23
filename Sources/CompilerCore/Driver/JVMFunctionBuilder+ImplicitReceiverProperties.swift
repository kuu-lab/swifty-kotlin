import Foundation

extension JVMFunctionBuilder {
    func implicitReceiverProperty(_ id: ExprID, name: InternedString) throws -> JVMValue? {
        let bindings = program.sema.bindings
        guard !scopes.contains(where: { $0[name] != nil }),
              bindings.implicitReceiverMemberNames[id] == name else { return nil }

        let selected = bindings.implicitReceiverOuterReceiver(for: id)
        guard let receiver = selected.flatMap({ contextualReceivers[$0] }) ?? extensionValue ?? thisValue else {
            throw fail("Missing implicit JVM member property receiver.", id)
        }
        let property = context.interner.resolve(name)
        switch property {
        case "length":
            guard receiver.type.isText else { return nil }
            return try textLength(receiver)
        case "code":
            guard receiver.type == .char else { return nil }
            return try convert(receiver, to: .int)
        case "size":
            guard receiver.type.referenceName?.hasPrefix("[") == true else {
                let receiverType = selected.flatMap { program.sema.symbols.propertyType(for: $0) }
                    ?? semanticSignature?.receiverType
                    ?? bindings.implicitExtensionReceiver(for: id)
                        .flatMap { program.sema.symbols.propertyType(for: $0) }
                let mapSymbol = program.sema.symbols.lookup(fqName: ["kotlin", "collections", "Map"].map(context.interner.intern))
                let collectionSymbol = program.sema.symbols.lookup(fqName: ["kotlin", "collections", "Collection"].map(context.interner.intern))
                let isMap = receiver.type.referenceName == "java/util/Map" || (receiverType.flatMap { type in
                    mapSymbol.map { target in
                        program.sema.types.isSubtype(type, program.sema.types.make(.classType(ClassType(classSymbol: target))))
                    }
                } ?? false)
                let isCollection = receiver.type.referenceName.map {
                    JVMClasspathIndex.collectionNames.values.contains($0) && $0 != "java/util/Map"
                } == true || (receiverType.flatMap { type in
                    collectionSymbol.map { target in
                        program.sema.types.isSubtype(type, program.sema.types.make(.classType(ClassType(classSymbol: target))))
                    }
                } ?? false)
                guard isMap || isCollection else { return nil }
                let owner = isMap ? "java/util/Map" : "java/util/Collection"
                return try jdkCall(owner, "size", [], .int, receiver: receiver, interface: true, resolved: program.expressionType(id))
            }
            return try textLength(receiver)
        default:
            return nil
        }
    }

    func implicitCollectionIteratorCall(_ symbol: SymbolID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard args.isEmpty,
              let method = program.collectionInterfaceMethods[symbol],
              method.name == "iterator",
              let receiver = implicitExtensionReceiver(id) else { return nil }
        return JVMIntrinsicResult(value: try jdkCall(
            method.owner,
            method.name,
            method.parameters,
            method.result,
            receiver: receiver,
            interface: method.isInterface,
            resolved: program.expressionType(id)
        ))
    }
}
