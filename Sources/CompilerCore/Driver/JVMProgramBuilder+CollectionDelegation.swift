import Foundation

extension JVMProgramBuilder {
    struct CollectionMethod {
        let owner: String
        let name: String
        let parameters: [JVMValueType]
        let result: JVMValueType
        var mutating = false
        var readOnlyOnly = false
        var method: JVMForeignMethod {
            JVMForeignMethod(owner: owner, name: name, descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor, parameters: parameters, result: result, isStatic: false, isInterface: true, isAbstract: true)
        }
    }

    static func collectionMethods(_ owner: String) -> [CollectionMethod] {
        let object = JVMValueType.reference("java/lang/Object", nullable: true)
        let collection = JVMValueType.reference("java/util/Collection", nullable: false)
        let iterator = JVMValueType.reference("java/util/Iterator", nullable: false)
        func method(_ name: String, _ parameters: [JVMValueType], _ result: JVMValueType, mutating: Bool = false, readOnlyOnly: Bool = false) -> CollectionMethod {
            CollectionMethod(owner: owner, name: name, parameters: parameters, result: result, mutating: mutating, readOnlyOnly: readOnlyOnly)
        }
        if owner == "java/util/Iterator" {
            return [method("hasNext", [], .boolean), method("next", [], object), method("remove", [], .unit, mutating: true)]
        }
        if owner == "java/lang/Iterable" { return [method("iterator", [], iterator)] }
        if owner == "java/util/ListIterator" {
            return [
                method("hasPrevious", [], .boolean), method("previous", [], object),
                method("nextIndex", [], .int), method("previousIndex", [], .int),
                method("add", [object], .unit, mutating: true), method("set", [object], .unit, mutating: true),
                method("remove", [], .unit, mutating: true),
            ]
        }
        if owner == "java/util/Map" {
            let function = JVMValueType.reference("java/util/function/Function", nullable: false)
            let binary = JVMValueType.reference("java/util/function/BiFunction", nullable: false)
            let defaults = [
                method("replaceAll", [binary], .unit, mutating: true, readOnlyOnly: true),
                method("putIfAbsent", [object, object], object, mutating: true, readOnlyOnly: true),
                method("remove", [object, object], .boolean, mutating: true, readOnlyOnly: true),
                method("replace", [object, object], object, mutating: true, readOnlyOnly: true),
                method("replace", [object, object, object], .boolean, mutating: true, readOnlyOnly: true),
                method("computeIfAbsent", [object, function], object, mutating: true, readOnlyOnly: true),
                method("computeIfPresent", [object, binary], object, mutating: true, readOnlyOnly: true),
                method("compute", [object, binary], object, mutating: true, readOnlyOnly: true),
                method("merge", [object, object, binary], object, mutating: true, readOnlyOnly: true),
            ]
            return defaults + [method("size", [], .int), method("isEmpty", [], .boolean), method("containsKey", [object], .boolean), method("containsValue", [object], .boolean), method("get", [object], object), method("keySet", [], .reference("java/util/Set", nullable: false)), method("values", [], collection), method("entrySet", [], .reference("java/util/Set", nullable: false)), method("put", [object, object], object, mutating: true), method("remove", [object], object, mutating: true), method("putAll", [.reference("java/util/Map", nullable: false)], .unit, mutating: true), method("clear", [], .unit, mutating: true)]
        }
        var methods = [method("size", [], .int), method("isEmpty", [], .boolean), method("contains", [object], .boolean), method("containsAll", [collection], .boolean), method("iterator", [], iterator), method("toArray", [], .reference("[Ljava/lang/Object;", nullable: false)), method("toArray", [.reference("[Ljava/lang/Object;", nullable: false)], .reference("[Ljava/lang/Object;", nullable: false)), method("add", [object], .boolean, mutating: true), method("remove", [object], .boolean, mutating: true), method("addAll", [collection], .boolean, mutating: true), method("removeAll", [collection], .boolean, mutating: true), method("retainAll", [collection], .boolean, mutating: true), method("clear", [], .unit, mutating: true)]
        if owner == "java/util/List" {
            methods += [
                method("replaceAll", [.reference("java/util/function/UnaryOperator", nullable: false)], .unit, mutating: true, readOnlyOnly: true),
                method("sort", [.reference("java/util/Comparator", nullable: true)], .unit, mutating: true, readOnlyOnly: true),
                method("addFirst", [object], .unit, mutating: true, readOnlyOnly: true),
                method("addLast", [object], .unit, mutating: true, readOnlyOnly: true),
                method("removeFirst", [], object, mutating: true, readOnlyOnly: true),
                method("removeLast", [], object, mutating: true, readOnlyOnly: true),
            ]
            methods += [method("get", [.int], object), method("indexOf", [object], .int), method("lastIndexOf", [object], .int), method("listIterator", [], .reference("java/util/ListIterator", nullable: false)), method("listIterator", [.int], .reference("java/util/ListIterator", nullable: false)), method("subList", [.int, .int], .reference("java/util/List", nullable: false)), method("set", [.int, object], object, mutating: true), method("add", [.int, object], .unit, mutating: true), method("addAll", [.int, collection], .boolean, mutating: true), method("remove", [.int], object, mutating: true)]
        }
        return methods
    }

    func collectionPropertyGetter(_ plan: JVMClassPlan, name: String) -> String? {
        func subtype(_ nominal: String) -> Bool {
            sema.symbols.lookup(fqName: ["kotlin", "collections", nominal].map(context.interner.intern)).map {
                sema.types.isNominalSubtypeSymbol(plan.symbol, of: $0)
            } == true
        }
        // AbstractSet owns a Kotlin getSize accessor plus its JDK size bridge.
        if name == "size", !subtype("AbstractSet"), subtype("Collection") || (!context.options.stdlibOnly && subtype("Map")) { return "size" }
        if !context.options.stdlibOnly, subtype("Map") { return ["keys": "keySet", "values": "values", "entries": "entrySet"][name] }
        return nil
    }

    func prepareCollectionInterfaces() throws {
        guard !context.options.stdlibOnly else { return }
        for symbol in sema.symbols.allSymbols() {
            guard let parent = sema.symbols.parentSymbol(for: symbol.id), let source = try? className(parent), source.hasPrefix("kotlin/collections/"), let owner = JVMClasspathIndex.collectionNames[String(source.split(separator: "/").last!)] else { continue }
            let name = context.interner.resolve(symbol.name)
            let contract = Self.collectionMethods(owner)
            if symbol.kind == .function, let signature = sema.symbols.functionSignature(for: symbol.id) {
                let actual = name == "removeAt" ? "remove" : name == "set" && owner == "java/util/Map" ? "put" : name
                if let target = contract.first(where: { $0.name == actual && $0.parameters.count == signature.parameterTypes.count && (name != "removeAt" || $0.parameters == [.int]) && (name != "remove" || $0.parameters != [.int]) }) {
                    collectionInterfaceMethods[symbol.id] = target.method
                }
            } else if symbol.kind == .property {
                let actual = name == "keys" ? "keySet" : name == "entries" ? "entrySet" : name
                if let target = contract.first(where: { $0.name == actual && $0.parameters.isEmpty }) {
                    properties[symbol.id] = JVMProperty(name: name, type: target.result, getter: target.method, setter: nil, field: nil, modifiers: [.abstract])
                    collectionInterfaceMethods[SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol.id)] = target.method
                }
            }
        }
    }

    func prepareCollectionDelegationMarkers() throws {
        for plan in classes.values where !plan.delegateFields.isEmpty {
            var visited: Set<SymbolID> = []
            func visit(_ symbol: SymbolID) throws {
                guard visited.insert(symbol).inserted else { return }
                let source = try className(symbol)
                if source.hasPrefix("kotlin/collections/"), JVMClasspathIndex.builtinName(source) != nil {
                    let name = String(source.split(separator: "/").last!)
                    let marker = name.hasPrefix("Mutable") ? "K" + name : "KMappedMarker"
                    let binary = "kotlin/jvm/internal/markers/" + marker
                    if !plan.interfaces.contains(binary) { plan.interfaces.append(binary) }
                }
                for parent in sema.symbols.directSupertypes(for: symbol) { try visit(parent) }
            }
            for interface in sema.symbols.delegatedInterfaces(forClass: plan.symbol) { try visit(interface) }
            var names: Set<String> = []
            plan.interfaces = plan.interfaces.filter { names.insert($0).inserted }
        }
    }

    func collectionPropertyAliases(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        guard !context.options.stdlibOnly, !plan.delegateFields.isEmpty else { return [] }
        let aliases = ["size": "getSize", "keySet": "getKeys", "values": "getValues", "entrySet": "getEntries"]
        var signatures = Set(existing.map { $0.reference.name + $0.reference.descriptor })
        var functions: [JVMFunction] = []
        for property in plan.properties.map({ $0.2 }) + plan.delegatedProperties.map({ $0.0 }) {
            let target = property.getter
            guard let name = aliases[target.name], signatures.insert(name + target.descriptor).inserted else { continue }
            let b = try nominalBuilder(plan, name: name, result: target.result)
            let result = try b.value(target.result)
            b.instructions.append(.foreignCall(target, receiver: b.thisValue!, arguments: [], result: result))
            b.instructions.append(.returnValue(result))
            // Java consumers retain Kotlin's ordinary property getter ABI;
            // the JDK entry remains the accessor recorded in Kotlin metadata.
            var function = b.finish(); function.access = 1; function.isMetadataHidden = true
            function.genericSignature = "()" + (property.genericSignature ?? property.type.descriptor).replacingOccurrences(of: "+", with: "")
            functions.append(function)
        }
        return functions
    }

    func collectionDelegationMethods(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        var signatures = Set(existing.map { $0.reference.name + $0.reference.descriptor })
        var functions: [JVMFunction] = []
        for (symbol, _, field) in plan.delegateFields {
            guard let semantic = sema.symbols.propertyType(for: symbol), case let .classType(type) = sema.types.kind(of: semantic), let source = try? className(type.classSymbol), source.hasPrefix("kotlin/collections/"), let owner = JVMClasspathIndex.builtinName(source) else { continue }
            let mutable = String(source.split(separator: "/").last!).hasPrefix("Mutable")
            for contract in Self.collectionMethods(owner) {
                if mutable && contract.readOnlyOnly { continue }
                let target = contract.method
                guard signatures.insert(target.name + target.descriptor).inserted else { continue }
                let b = try nominalBuilder(plan, name: target.name, parameters: target.parameters, result: target.result)
                if contract.mutating && !mutable {
                    let message = try b.constant(.string("Operation is not supported for read-only collection"), .string)
                    let error = try b.constructJDK("java/lang/UnsupportedOperationException", parameters: [.string], arguments: [message])
                    b.instructions.append(.throwValue(error))
                } else if target.name == "toArray" {
                    let parameters = [JVMValueType.reference("java/util/Collection", nullable: false)] + target.parameters
                    let helper = JVMForeignMethod(owner: "kotlin/jvm/internal/CollectionToArray", name: "toArray", descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + target.result.descriptor, parameters: parameters, result: target.result, isStatic: true, isInterface: false, isAbstract: false)
                    let result = try b.value(target.result)
                    b.instructions.append(.foreignCall(helper, receiver: nil, arguments: [b.thisValue!] + Array(b.locals.dropFirst().prefix(target.parameters.count)), result: result))
                    b.instructions.append(.returnValue(result))
                } else {
                    let delegate = try b.value(field.type); b.instructions.append(.getField(field, b.thisValue!, delegate))
                    let result = target.result == .unit ? nil : try b.value(target.result)
                    b.instructions.append(.foreignCall(target, receiver: delegate, arguments: Array(b.locals.dropFirst().prefix(target.parameters.count)), result: result))
                    b.instructions.append(.returnValue(result))
                }
                var function = b.finish(); function.access = 1; function.isMetadataHidden = true
                if target.name == "toArray", !target.parameters.isEmpty {
                    function.parameterNames = ["array"]
                    function.genericSignature = "<T:Ljava/lang/Object;>([TT;)[TT;"
                }
                if contract.mutating && !mutable { function.checksParameters = false }
                functions.append(function)
            }
        }
        return functions
    }
}
