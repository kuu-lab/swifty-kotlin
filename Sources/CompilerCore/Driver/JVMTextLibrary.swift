import Foundation

struct JVMTextLibraryMethod {
    var method: JVMForeignMethod
    var declarations: [ValueParamDecl]
    var extensionReceiver: JVMValueType? = nil
    var adaptation: String? = nil
}

extension JVMProgramBuilder {
    func prepareTextLibrary() throws {
        func externalJvmName(for symbol: SymbolID) -> String? {
            guard let raw = sema.symbols.annotations(for: symbol)
                .first(where: { $0.annotationFQName == "kotlin.jvm.JvmName" })?.arguments.first,
                let literal = raw.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                let data = ("[" + literal + "]").data(using: .utf8),
                let names = try? JSONSerialization.jsonObject(with: data) as? [String],
                let name = names.first
            else { return nil }
            return name
        }

        func method(_ symbol: SymbolID, owner: String, name: String, declarations: [ValueParamDecl], interface: Bool = false, extensionReceiver: JVMValueType? = nil, adaptation: String? = nil, staticMember: Bool = false) throws {
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return }
            let explicitName = staticMember ? externalJvmName(for: symbol) : nil
            let resolvedName = explicitName ?? name
            let signatureParameters = try signature.parameterTypes.map(type)
            let signatureResult = resolvedName == "<init>" ? JVMValueType.reference(owner, nullable: false) : try type(signature.returnType)
            func durationPhysical(_ type: JVMValueType) -> JVMValueType {
                type.referenceName == "kotlin/time/Duration" && !type.isNullable ? .long : type
            }
            let parameters = owner == "kotlin/time/Duration" ? signatureParameters.map(durationPhysical) : signatureParameters
            let result = owner == "kotlin/time/Duration" ? durationPhysical(signatureResult) : signatureResult
            var explicitParameters = parameters
            for (index, declaration) in declarations.enumerated() where declaration.isVararg { explicitParameters[index] = parameters[index].referenceName?.hasPrefix("[") == true ? parameters[index] : .reference("[" + JVMClasspathIndex.boxed(parameters[index]).descriptor, nullable: false) }
            let params = (extensionReceiver.map { [$0] } ?? []) + explicitParameters
            let jvmName: String
            if case .unsignedArray? = extensionReceiver,
               ["kotlin/collections/ArraysKt", "kotlin/collections/unsigned/UArraysKt"].contains(owner) {
                // Kotlin's array facades hash the receiver and parameters, excluding the return type.
                let hashArguments = params.map(valueClassMangleElement).joined()
                jvmName = explicitName ?? name + "-" + JVMNameHash.suffix(hashArguments)
            } else if params.contains(where: { $0.unsignedName != nil }) {
                jvmName = resolvedName + "$unsigned$" + JVMNameHash.suffix(params.map { ($0.unsignedName ?? "_") + ($0.isNullable ? "?" : "") }.joined())
            } else {
                jvmName = resolvedName
            }
            var foreign = JVMForeignMethod(owner: owner, name: jvmName, descriptor: "(" + params.map(\.descriptor).joined() + ")" + (resolvedName == "<init>" ? "V" : result.descriptor), parameters: params, result: result, isStatic: staticMember || extensionReceiver != nil, isInterface: interface, isAbstract: false)
            foreign.isSuspend = signature.isSuspend
            textLibraryMethods[symbol] = JVMTextLibraryMethod(method: foreign, declarations: declarations, extensionReceiver: extensionReceiver, adaptation: adaptation)
        }
        func valueClassMangleElement(_ type: JVMValueType) -> String {
            guard let name = type.unsignedName else { return "_" }
            return "L" + name.replacingOccurrences(of: "/", with: ".") + (type.isNullable ? "?" : "") + ";"
        }
        func members(_ ids: [DeclID], _ properties: [DeclID], owner: String, interface: Bool) throws {
            for id in ids {
                guard case let .funDecl(f) = ast.arena.decl(id), let symbol = sema.bindings.declSymbol(for: id) else { continue }
                let name = context.interner.resolve(f.name)
                if owner == "java/util/Map", name == "set" { continue }
                let aliases = ["get": "charAt", "set": "setCharAt", "deleteAt": "deleteCharAt", "deleteRange": "delete", "setRange": "replace"]
                try method(symbol, owner: owner, name: owner == "java/util/List" && name == "removeAt" ? "remove" : owner == "java/lang/StringBuilder" ? aliases[name] ?? name : name, declarations: f.valueParams, interface: interface, adaptation: owner == "java/lang/StringBuilder" ? name : nil)
            }
            for id in properties {
                guard case let .propertyDecl(p) = ast.arena.decl(id), let symbol = sema.bindings.declSymbol(for: id), let semantic = sema.symbols.propertyType(for: symbol) else { continue }
                let name = context.interner.resolve(p.name), type = try type(semantic)
                let jvmName = owner.hasPrefix("java/util/") && ["size", "keys", "values"].contains(name) ? ["size": "size", "keys": "keySet", "values": "values"][name] ?? "get" + name.prefix(1).uppercased() + name.dropFirst() : ["java/lang/StringBuilder", "kotlin/text/MatchGroupCollection", "java/util/Collection"].contains(owner) && ["length", "size"].contains(name) ? name : "get" + name.prefix(1).uppercased() + name.dropFirst()
                let result: JVMValueType = owner == "kotlin/ranges/IntRange" && ["start", "endInclusive"].contains(name) ? .reference("java/lang/Integer", nullable: false) : type
                textLibraryProperties[symbol] = JVMForeignMethod(owner: owner, name: jvmName, descriptor: "()" + result.descriptor, parameters: [], result: result, isStatic: false, isInterface: interface, isAbstract: false)
            }
        }
        func visit(_ ids: [DeclID], path: String) throws {
            for id in ids {
                switch ast.arena.decl(id) {
                case let .funDecl(f):
                    guard let symbol = sema.bindings.declSymbol(for: id) else { continue }
                    if path.hasSuffix("-inline.kt") { inlineDeclarations[symbol] = f; continue }
                    guard let signature = sema.symbols.functionSignature(for: symbol) else { continue }
                    let source = context.interner.resolve(f.name)
                    var receiverType = try signature.receiverType.map(type)
                    var owner = path.hasSuffix("m19-sequence.kt") ? "kotlin/sequences/SequencesKt" : source == "get" ? "kotlin/text/jdk8/RegexExtensionsJDK8Kt" : "kotlin/text/StringsKt"
                    if path.contains("m20-") {
                        if path.contains("sequence-") { owner = "kotlin/sequences/SequencesKt" }
                        else if path.contains("text-") { owner = "kotlin/text/StringsKt" }
                        else if path.contains("arrays-") { owner = "kotlin/collections/ArraysKt" }
                        else { owner = "kotlin/collections/CollectionsKt" }
                        if case .unsignedArray? = receiverType, !path.contains("arrays-utility-"), !path.contains("unsigned-array-operations") {
                            receiverType = .reference("java/lang/Iterable", nullable: false)
                            owner = "kotlin/collections/CollectionsKt"
                        }
                    }
                    let arrayContentToString = path.contains("m20-arrays-utility")
                        && source == "contentToString"
                        && receiverType != nil
                        && receiverType?.unsignedName == nil
                    if arrayContentToString {
                        // The official Kotlin wrapper is private and inline-only on the JVM.
                        owner = "java/util/Arrays"
                    }
                    if path.contains("m21-") { owner = "kotlin/sequences/SequencesKt" }
                    if path.contains("m20-"), source == "toMap" { owner = "kotlin/collections/MapsKt" }
                    if path.contains("m20-factories") {
                        owner = source.lowercased().contains("map") ? "kotlin/collections/MapsKt" : source.lowercased().contains("set") ? "kotlin/collections/SetsKt" : "kotlin/collections/CollectionsKt"
                    }
                    let adaptation = path.contains("m20-factories") ? "collectionFactory" : source == "toRegex" ? "toRegex" : path.hasSuffix("m19-regex.kt") && source != "get" ? "regexExtension" : nil
                    try method(symbol, owner: owner, name: arrayContentToString ? "toString" : source, declarations: f.valueParams, extensionReceiver: receiverType, adaptation: adaptation, staticMember: true)
                case let .classDecl(c):
                    guard let symbol = sema.bindings.declSymbol(for: id) else { continue }
                    let source = try className(symbol), owner = JVMClasspathIndex.builtinName(source) ?? source
                    try members(c.memberFunctions, c.memberProperties, owner: owner, interface: false)
                    if source != "kotlin/text/RegexOption" {
                        let parent = sema.symbols.symbol(symbol)!
                        for constructor in sema.symbols.lookupAll(fqName: parent.fqName + [context.interner.intern("<init>")]) {
                            let site = sema.symbols.symbol(constructor)?.declSite
                            let params = site == c.range ? c.primaryConstructorParams : c.secondaryConstructors.first { $0.range == site }?.valueParams ?? []
                            try method(constructor, owner: owner, name: "<init>", declarations: params)
                        }
                    }
                    try visit(c.nestedClasses + c.nestedObjects, path: path)
                    if let companion = c.companionObject { try visit([companion], path: path) }
                case let .interfaceDecl(c):
                    guard let symbol = sema.bindings.declSymbol(for: id) else { continue }
                    let source = try className(symbol), owner = JVMClasspathIndex.builtinName(source) ?? source
                    try members(c.memberFunctions, c.memberProperties, owner: owner, interface: true)
                    try visit(c.nestedClasses + c.nestedObjects, path: path)
                case let .objectDecl(c):
                    guard let symbol = sema.bindings.declSymbol(for: id) else { continue }
                    try members(c.memberFunctions, c.memberProperties, owner: className(symbol), interface: false)
                default: break
                }
            }
        }
        func registerMapEntryComponent(_ id: DeclID) throws {
            guard case let .funDecl(declaration) = ast.arena.decl(id),
                  let symbol = sema.bindings.declSymbol(for: id),
                  let signature = sema.symbols.functionSignature(for: symbol)
            else { return }
            let source = context.interner.resolve(declaration.name)
            guard ["component1", "component2"].contains(source) else { return }
            let owner = "java/util/Map$Entry"
            let name = source == "component1" ? "getKey" : "getValue"
            let result = try type(signature.returnType)
            var method = JVMForeignMethod(owner: owner, name: name, descriptor: "()" + result.descriptor, parameters: [], result: result, isStatic: false, isInterface: true, isAbstract: false)
            method.isSuspend = signature.isSuspend
            textLibraryMethods[symbol] = JVMTextLibraryMethod(method: method, declarations: declaration.valueParams)
        }

        let runtimeFacades = Dictionary(uniqueKeysWithValues: try JVMStdlibCatalog.manifest().declarations.compactMap { declaration in declaration.runtimeFacade.map { (declaration.virtualPath, $0) } })
        for file in ast.files {
            let path = context.sourceManager.path(of: file.fileID)
            if path == "<kswiftk-jvm>/kotlin-time-duration.kt" {
                for id in file.topLevelDecls {
                    guard case let .classDecl(duration) = ast.arena.decl(id),
                          context.interner.resolve(duration.name) == "Duration" else { continue }
                    let owner = "kotlin/time/Duration"
                    for member in duration.memberFunctions {
                        guard case let .funDecl(function) = ast.arena.decl(member),
                              context.interner.resolve(function.name) == "isNegative",
                              let symbol = sema.bindings.declSymbol(for: member) else { continue }
                        try method(symbol, owner: owner, name: "isNegative-impl", declarations: function.valueParams, extensionReceiver: .long, staticMember: true)
                    }
                    for member in duration.memberProperties {
                        guard case let .propertyDecl(property) = ast.arena.decl(member),
                              let symbol = sema.bindings.declSymbol(for: member) else { continue }
                        let getter = "get" + context.interner.resolve(property.name).prefix(1).uppercased() + context.interner.resolve(property.name).dropFirst() + "-impl"
                        textLibraryProperties[symbol] = JVMForeignMethod(
                            owner: owner,
                            name: getter,
                            descriptor: "(J)J",
                            parameters: [.long],
                            result: .long,
                            isStatic: true,
                            isInterface: false,
                            isAbstract: false
                        )
                    }
                }
            }
            if path == "<kswiftk-jvm>/duration.kt" {
                try visit(file.topLevelDecls.filter { id in
                    if case .classDecl = ast.arena.decl(id) { return true }
                    return false
                }, path: path)
                for id in file.topLevelDecls {
                    guard case let .classDecl(duration) = ast.arena.decl(id),
                          context.interner.resolve(duration.name) == "Duration" else { continue }
                    let owner = "kotlin/time/Duration"
                    for member in duration.memberFunctions {
                        guard case let .funDecl(function) = ast.arena.decl(member),
                              let symbol = sema.bindings.declSymbol(for: member) else { continue }
                        let name = context.interner.resolve(function.name)
                        switch name {
                        case "isNegative", "isPositive", "isInfinite", "isFinite",
                             "toDouble", "toLong", "toInt", "toString":
                            try method(symbol, owner: owner, name: name + "-impl", declarations: function.valueParams, extensionReceiver: .long, staticMember: true)
                        case "compareTo":
                            try method(symbol, owner: owner, name: "compareTo-LRDsOJo", declarations: function.valueParams, extensionReceiver: .long, staticMember: true)
                        default:
                            break
                        }
                    }
                    for member in duration.memberProperties {
                        guard case let .propertyDecl(property) = ast.arena.decl(member),
                              let symbol = sema.bindings.declSymbol(for: member),
                              let semantic = sema.symbols.propertyType(for: symbol) else { continue }
                        let name = context.interner.resolve(property.name)
                        guard name.hasPrefix("inWhole") else { continue }
                        let getter = "get" + name.prefix(1).uppercased() + name.dropFirst() + "-impl"
                        textLibraryProperties[symbol] = JVMForeignMethod(owner: owner, name: getter, descriptor: "(J)" + (try type(semantic)).descriptor, parameters: [.long], result: try type(semantic), isStatic: true, isInterface: false, isAbstract: false)
                    }
                }
            }
            if let owner = runtimeFacades[path] {
                for id in file.topLevelDecls {
                    switch ast.arena.decl(id) {
                    case let .funDecl(function):
                        guard let symbol = sema.bindings.declSymbol(for: id), let signature = sema.symbols.functionSignature(for: symbol) else { continue }
                        let source = context.interner.resolve(function.name)
                        try method(symbol, owner: owner, name: source, declarations: function.valueParams, extensionReceiver: try signature.receiverType.map(type), staticMember: true)
                        if function.isInline { inlineDeclarations[symbol] = function }
                    case let .propertyDecl(property):
                        guard let symbol = sema.bindings.declSymbol(for: id), let valueType = sema.symbols.propertyType(for: symbol) else { continue }
                        let name = context.interner.resolve(property.name)
                        if property.modifiers.contains(.const) {
                            textLibraryFields[symbol] = JVMField(owner: owner, name: name, type: try type(valueType), access: 0x19)
                        } else if let receiverSemantic = sema.symbols.extensionPropertyReceiverType(for: symbol) {
                            let receiverType = try type(receiverSemantic)
                            let resultType = try type(valueType)
                            let getter = "get" + name.prefix(1).uppercased() + name.dropFirst()
                            let parameters = [receiverType]
                            textLibraryProperties[symbol] = JVMForeignMethod(
                                owner: owner,
                                name: getter,
                                descriptor: "(" + receiverType.descriptor + ")" + resultType.descriptor,
                                parameters: parameters,
                                result: resultType,
                                isStatic: true,
                                isInterface: false,
                                isAbstract: false
                            )
                        }
                    default:
                        continue
                    }
                }
            }
            if path == "<kswiftk-jvm>/result.kt" {
                for id in file.topLevelDecls {
                    guard case let .classDecl(declaration) = ast.arena.decl(id),
                          context.interner.resolve(declaration.name) == "Result"
                    else { continue }
                    for memberID in declaration.memberFunctions {
                        guard case let .funDecl(function) = ast.arena.decl(memberID),
                              function.isInline,
                              let symbol = sema.bindings.declSymbol(for: memberID)
                        else { continue }
                        inlineDeclarations[symbol] = function
                    }
                }
            }
            if [
                "<kswiftk-jvm>/javaCollections.kt",
                "<kswiftk-jvm>/indexed-value.kt",
                "<kswiftk-jvm>/coroutine-context.kt",
            ].contains(path) {
                try visit(file.topLevelDecls, path: path)
            }
            if path == "<kswiftk-jvm>/string-constructors.kt" {
                // Top-level `String(...)` shims lower directly to the matching
                // java.lang.String <init> descriptors instead of a kotlin
                // facade method.
                for id in file.topLevelDecls {
                    guard case let .funDecl(declaration) = ast.arena.decl(id),
                          context.interner.resolve(declaration.name) == "String",
                          let symbol = sema.bindings.declSymbol(for: id)
                    else { continue }
                    try method(symbol, owner: "java/lang/String", name: "<init>", declarations: declaration.valueParams)
                }
            }
            if path == "<kswiftk-jvm>/charsets.kt" {
                // kotlin.text.Charsets members are JDK StandardCharsets static
                // fields, not a kotlin object instance.
                for id in file.topLevelDecls {
                    guard case let .objectDecl(declaration) = ast.arena.decl(id),
                          context.interner.resolve(declaration.name) == "Charsets" else { continue }
                    for member in declaration.memberProperties {
                        guard case let .propertyDecl(property) = ast.arena.decl(member),
                              let symbol = sema.bindings.declSymbol(for: member),
                              let valueType = sema.symbols.propertyType(for: symbol) else { continue }
                        textLibraryFields[symbol] = JVMField(owner: "java/nio/charset/StandardCharsets", name: context.interner.resolve(property.name), type: try type(valueType), access: 0x19)
                    }
                }
            }
            if path == "<kswiftk-jvm>/collections.kt" {
                try visit(file.topLevelDecls.filter { id in
                    if case let .interfaceDecl(declaration) = ast.arena.decl(id) { return ["Iterator", "Iterable", "Collection", "MutableIterator", "MutableIterable", "MutableCollection", "List", "MutableList", "Set", "MutableSet", "Map", "MutableMap"].contains(context.interner.resolve(declaration.name)) }
                    return false
                }, path: path)
                for id in file.topLevelDecls {
                    guard case let .funDecl(declaration) = ast.arena.decl(id),
                          ["component1", "component2"].contains(context.interner.resolve(declaration.name))
                    else { continue }
                    try registerMapEntryComponent(id)
                }
                let factories: Set<String> = ["arrayListOf", "listOf", "setOf", "mapOf", "mutableListOf", "mutableSetOf", "mutableMapOf", "emptyList", "emptySet", "emptyMap"]
                try visit(file.topLevelDecls.filter { id in if case let .funDecl(f) = ast.arena.decl(id) { return factories.contains(context.interner.resolve(f.name)) }; return false }, path: "<kswiftk-jvm>/m20-factories-runtime.kt")
            }
            if path.hasPrefix("<kswiftk-jvm>/m19-") || path.hasPrefix("<kswiftk-jvm>/m20-") || path.hasPrefix("<kswiftk-jvm>/m21-") { try visit(file.topLevelDecls, path: path) }
        }
    }
}

extension JVMFunctionBuilder {
    func kotlinMathName(for symbolID: SymbolID) -> String? {
        guard let symbol = program.sema.symbols.symbol(symbolID) else { return nil }
        let components = symbol.fqName.map(context.interner.resolve)
        guard components.count == 3, components[0] == "kotlin", components[1] == "math" else { return nil }
        return components[2]
    }

    // Kotlin's JVM stdlib keeps these implementation methods private and
    // relies on Kotlin inlining. External bytecode must call public JDK APIs.
    func kotlinMathFunctionCall(_ symbolID: SymbolID, entry: JVMTextLibraryMethod, receiver: JVMValue?, values: [JVMValue], id: ExprID) throws -> JVMValue? {
        guard let name = kotlinMathName(for: symbolID) else { return nil }
        let resultType = try program.expressionType(id)
        switch name {
        case "hypot":
            guard values.count == 2 else { return nil }
            if entry.method.result == .float {
                let arguments = try values.map { try convert($0, to: .double) }
                guard let result = try jdkCall("java/lang/Math", "hypot", [.double, .double], .double, arguments: arguments) else { return nil }
                return try convert(result, to: .float)
            }
            return try jdkCall("java/lang/Math", "hypot", entry.method.parameters, entry.method.result, arguments: values, resolved: resultType)
        case "ln1p":
            guard values.count == 1 else { return nil }
            if entry.method.result == .float {
                let argument = try convert(values[0], to: .double)
                guard let result = try jdkCall("java/lang/Math", "log1p", [.double], .double, arguments: [argument]) else { return nil }
                return try convert(result, to: .float)
            }
            return try jdkCall("java/lang/Math", "log1p", entry.method.parameters, entry.method.result, arguments: values, resolved: resultType)
        case "withSign":
            guard let receiver, let receiverType = entry.extensionReceiver,
                  receiverType == .double || receiverType == .float,
                  values.count == 1 else { return nil }
            let arguments = [try convert(receiver, to: receiverType), try convert(values[0], to: receiverType)]
            return try jdkCall("java/lang/Math", "copySign", [receiverType, receiverType], receiverType, arguments: arguments, resolved: resultType)
        default:
            return nil
        }
    }

    func textMatchComponent(_ object: JVMValue, index: Int) throws -> JVMValue {
        // Destructured.componentN is private @InlineOnly in the official stdlib.
        let list = try jdkCall("kotlin/text/MatchResult$Destructured", "toList", [], .reference("java/util/List", nullable: false), receiver: object)!
        return try jdkCall("java/util/List", "get", [.int], .reference("java/lang/Object", nullable: true), receiver: list, arguments: [constant(.int(Int32(index)), .int)], interface: true, resolved: .string)!
    }
    func durationRawValue(_ value: JVMValue) throws -> JVMValue {
        guard value.type != .long, value.type.referenceName == "kotlin/time/Duration" else { return value }
        return try jdkCall("kotlin/time/Duration", "unbox-impl", [], .long, receiver: value)!
    }

    func textLibraryProperty(_ id: ExprID, receiver: ExprID? = nil) throws -> JVMValue? {
        let bindings = program.sema.bindings
        let call = bindings.callBinding(for: id)?.chosenCallee
        let accessorProperty = call.flatMap { accessor -> SymbolID? in
            if let property = program.sema.symbols.propertySymbol(forAccessor: accessor)
                ?? program.sema.symbols.accessorOwnerProperty(for: accessor) { return property }
            guard let parent = program.sema.symbols.parentSymbol(for: accessor),
                  program.sema.symbols.symbol(parent)?.kind == .property else { return nil }
            return parent
        }
        let symbol = bindings.identifierSymbol(for: id) ?? accessorProperty ?? call
        guard let symbol else { return nil }
        if let fqName = program.sema.symbols.symbol(symbol)?.fqName,
           fqName.count == 5,
           fqName.starts(with: KnownCompilerNames(interner: context.interner).kotlinTimeDurationFQName),
           context.interner.resolve(fqName[3]) == "Companion",
           ["nanoseconds", "microseconds", "milliseconds", "seconds", "minutes", "hours", "days"].contains(context.interner.resolve(fqName[4])) {
            guard let source = try receiver.map(requireValue) ?? implicitExtensionReceiver(id),
                  [.int, .long, .double].contains(source.type) else {
                throw fail("Duration unit properties require an Int, Long, or Double receiver.", id)
            }
            let unitType = JVMValueType.reference("kotlin/time/DurationUnit", nullable: false)
            let unit = try value(unitType)
            instructions.append(.getStatic(JVMField(owner: "kotlin/time/DurationUnit", name: context.interner.resolve(fqName[4]).uppercased(), type: unitType, access: 0x4019), unit))
            return try jdkCall("kotlin/time/DurationKt", "toDuration", [source.type, unitType], .long, arguments: [source, unit], resolved: program.expressionType(id))
        }
        if let field = program.textLibraryFields[symbol] {
            let loaded = try value(field.type)
            instructions.append(.getStatic(field, loaded))
            return try convert(loaded, to: program.expressionType(id))
        }
        if program.textLibraryProperties[symbol] == nil,
           let property = program.sema.symbols.symbol(symbol),
           let site = property.declSite, context.sourceManager.path(of: site.start.file).hasPrefix("<kswiftk-jvm>/text"),
           ["length", "lastIndex"].contains(context.interner.resolve(property.name)) {
            let object = try receiver.map(requireValue) ?? instance(id)
            let size = try textLength(object)
            if context.interner.resolve(property.name) == "length" { return size }
            let result = try value(.int); instructions.append(.binary(.subtract, size, try constant(.int(1), .int), result)); return result
        }
        guard let method = program.textLibraryProperties[symbol] else { return nil }
        if method.isStatic {
            let extensionReceiver: JVMValue?
            if let receiver { extensionReceiver = try requireValue(receiver) }
            else { extensionReceiver = implicitExtensionReceiver(id) }
            guard let extensionReceiver, method.parameters.count == 1 else {
                throw fail("Missing JVM extension property receiver.", id)
            }
            if kotlinMathName(for: symbol) == "ulp" {
                return try jdkCall("java/lang/Math", "ulp", method.parameters, method.result, arguments: [extensionReceiver], resolved: program.expressionType(id))
            }
            let receiverArgument = method.owner == "kotlin/time/Duration" && method.isStatic ? try durationRawValue(extensionReceiver) : extensionReceiver
            return try jdkCall(method.owner, method.name, method.parameters, method.result, arguments: [receiverArgument], resolved: program.expressionType(id))
        }
        let object = try receiver.map(requireValue) ?? instance(id)
        return try jdkCall(method.owner, method.name, [], method.result, receiver: object, interface: method.isInterface, resolved: program.expressionType(id))
    }

    func textLibraryCall(_ args: [CallArgument], receiver: ExprID? = nil, receiverValue: JVMValue? = nil, id: ExprID, expectedResult: JVMValueType? = nil) throws -> JVMIntrinsicResult? {
        guard let binding = program.sema.bindings.callBinding(for: id),
              program.inlineDeclarations[binding.chosenCallee] == nil,
              let entry = program.textLibraryMethods[binding.chosenCallee] else { return nil }
        let method = entry.method
        if method.owner == "java/lang/Comparable", method.name == "compareTo", let receiver,
           case .memberCall = arena.expr(id), case let .nameRef(name, _) = arena.expr(receiver),
           let local = scopes.reversed().compactMap({ $0[name] }).first,
           let origin = local.numericBoxingOrigin {
            let saved = evaluatedOperands
            evaluatedOperands[receiver] = origin
            defer { evaluatedOperands = saved }
            return try scalarMember(receiver, name: "compareTo", args: args, id: id)
        }
        if method.owner == "java/lang/Comparable", method.name == "compareTo", let receiver,
           (evaluatedOperands[receiver]?.type ?? (try? program.expressionType(receiver)))?.numericCarrier != nil {
            return try scalarMember(receiver, name: "compareTo", args: args, id: id)
        }
        // The intrinsic path preserves the collection factories' concrete types and singleton identity.
        if entry.adaptation == "collectionFactory", ["kotlin/collections/CollectionsKt", "kotlin/collections/SetsKt", "kotlin/collections/MapsKt"].contains(method.owner),
           ["listOf", "mutableListOf", "setOf", "mutableSetOf", "emptyList", "emptySet", "mutableMapOf", "mapOf", "emptyMap"].contains(method.name),
           args.allSatisfy({ !$0.isSpread && $0.label == nil }) { return nil }
        let kotlinBuilderOperations: Set<String> = ["get", "set", "subSequence", "substring", "deleteAt", "deleteRange", "setRange", "clear", "appendLine", "appendRange", "insertRange"]
        if method.owner == "java/lang/StringBuilder", args.contains(where: { $0.label != nil }),
           !kotlinBuilderOperations.contains(entry.adaptation ?? "") {
            throw fail("Named arguments are prohibited for Java StringBuilder constructors and methods.", id)
        }
        let explicit = try method.isConstructor || method.isStatic && entry.extensionReceiver == nil ? nil : receiverValue ?? receiver.map(requireValue)
        let implicit = implicitExtensionReceiver(id)
        let object = try method.isConstructor || method.isStatic && entry.extensionReceiver == nil ? nil : explicit ?? (entry.extensionReceiver != nil ? implicit : instance(id))
        let parameters = Array(method.parameters.dropFirst(entry.extensionReceiver == nil ? 0 : 1))
        let ordered: (values: [JVMValue], masks: [UInt32], contextValues: [Int: JVMValue])
        if entry.declarations.count == 1, entry.declarations[0].isVararg {
            let any = try arrayComponent(parameters[0])
            let op = JVMTextOperation(name: method.name, receiver: "", receiverType: any, parameters: [JVMTextParameter(name: context.interner.resolve(entry.declarations[0].name), type: any, fallback: nil, variadic: true)], sourceResult: "", result: method.result, owner: method.owner, method: nil, instance: false)
            ordered = (try textArguments(op, args: args, binding: binding, source: zero(any), id: id), [0], [:])
        } else { ordered = try arguments(args, binding: binding, parameters: parameters, declarations: entry.declarations, id: id) }
        let values = ordered.values
        if let result = try kotlinMathFunctionCall(binding.chosenCallee, entry: entry, receiver: object, values: values, id: id) {
            return JVMIntrinsicResult(value: result)
        }
        if entry.adaptation == "collectionFactory", entry.declarations.first?.isVararg == true, ["mapOf", "listOf", "setOf"].contains(method.name), args.count == 1, !args[0].isSpread, args[0].label == nil {
            let element = try arrayComponent(parameters[0])
            let single = try indexedRead(values[0], index: constant(.int(0), .int), type: element)
            return JVMIntrinsicResult(value: try jdkCall(method.owner, method.name, [element], method.result, arguments: [single], resolved: program.expressionType(id)))
        }
        if method.owner == "kotlin/text/MatchResult$Destructured", method.name.hasPrefix("component"), let component = Int(method.name.dropFirst(9)) {
            return JVMIntrinsicResult(value: try textMatchComponent(object!, index: component - 1))
        }
        if method.isConstructor {
            return JVMIntrinsicResult(value: try constructJDK(method.owner, parameters: method.parameters, arguments: values))
        }
        if entry.adaptation == "toRegex" {
            return JVMIntrinsicResult(value: try constructJDK("kotlin/text/Regex", parameters: [.string] + parameters, arguments: [object!] + values))
        }
        if entry.adaptation == "regexExtension" {
            var actual = Array(values.dropFirst()), params = Array(parameters.dropFirst())
            if ordered.masks.contains(where: { $0 != 0 }) {
                // Text extension wrappers default only their final limit to zero.
                actual[actual.count - 1] = try constant(.int(0), .int)
            }
            actual.insert(object!, at: 0); params.insert(.reference("java/lang/CharSequence", nullable: false), at: 0)
            let name = method.name == "contains" ? "containsMatchIn" : method.name
            return JVMIntrinsicResult(value: try jdkCall("kotlin/text/Regex", name, params, method.result, receiver: values[0], arguments: actual, resolved: program.expressionType(id)))
        }
        if method.owner == "java/lang/StringBuilder", let name = entry.adaptation {
            if name == "clear" {
                _ = try jdkCall(method.owner, "setLength", [.int], .unit, receiver: object, arguments: [constant(.int(0), .int)])
                return JVMIntrinsicResult(value: object)
            }
            if name == "appendLine" {
                if !values.isEmpty { _ = try jdkCall(method.owner, "append", parameters, method.result, receiver: object, arguments: values) }
                return JVMIntrinsicResult(value: try jdkCall(method.owner, "append", [.char], method.result, receiver: object, arguments: [constant(.int(10), .char)]))
            }
            if name == "appendRange" || name == "insertRange" {
                var actual = values
                let array = parameters.contains { $0.referenceName == "[C" }
                if array {
                    let count = try value(.int)
                    instructions.append(.binary(.subtract, values[values.count - 1], values[values.count - 2], count)); actual[actual.count - 1] = count
                }
                return JVMIntrinsicResult(value: try jdkCall(method.owner, name == "appendRange" ? "append" : "insert", parameters, method.result, receiver: object, arguments: actual))
            }
        }
        var actual = (entry.extensionReceiver == nil ? [] : [object!]) + values, params = method.parameters
        if method.owner == "kotlin/time/Duration", method.isStatic, entry.extensionReceiver == .long {
            actual = try actual.indices.map { index in
                index < params.count && params[index] == .long && actual[index].type.referenceName == "kotlin/time/Duration" ? try durationRawValue(actual[index]) : actual[index]
            }
        }
        let usesDefaults = ordered.masks.contains { $0 != 0 }
        if usesDefaults {
            if !method.isStatic { actual.insert(object!, at: 0); params.insert(.reference(method.owner, nullable: false), at: 0) }
            actual += try maskArguments(ordered.masks, constructor: false)
            params += Array(repeating: JVMValueType.int, count: ordered.masks.count) + [.reference("java/lang/Object", nullable: true)]
        }
        let superReceiver = receiver.flatMap { id -> ExprID? in
            if case .superRef = arena.expr(id) { return id }
            return nil
        }
        if method.isSuspend || superReceiver != nil {
            guard !usesDefaults else { throw fail("Unsupported JVM library defaults for a suspend or super call.", id) }
            let target = try superReceiver.map { try superMethod(method, receiver: $0) } ?? method
            var converted: [JVMValue] = []
            for (argument, parameter) in zip(actual, params) { converted.append(try convert(argument, to: parameter)) }
            let resultType = try expectedResult ?? program.expressionType(id)
            let result = resultType == .unit ? nil : try value(resultType)
            instructions.append(.foreignCall(target, receiver: method.isStatic ? nil : object, arguments: converted, result: result))
            return JVMIntrinsicResult(value: result)
        }
        return JVMIntrinsicResult(value: try jdkCall(method.owner, method.name + (usesDefaults ? "$default" : ""), params, method.result, receiver: method.isStatic || usesDefaults ? nil : object, arguments: actual, interface: method.isInterface && !usesDefaults, resolved: expectedResult ?? program.expressionType(id)))
    }
}
