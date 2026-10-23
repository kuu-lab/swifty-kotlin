import Foundation

extension JVMClasspathIndex {
    static let wrappers: [String: String] = ["Int": "Integer", "Long": "Long", "Float": "Float", "Double": "Double", "Boolean": "Boolean", "Byte": "Byte", "Short": "Short", "Char": "Character"]
    static let primitiveArrays: [String: JVMValueType] = ["IntArray": .int, "LongArray": .long, "FloatArray": .float, "DoubleArray": .double, "BooleanArray": .boolean, "ByteArray": .byte, "ShortArray": .short, "CharArray": .char]
    static let collectionNames = ["Iterable": "java/lang/Iterable", "MutableIterable": "java/lang/Iterable", "Iterator": "java/util/Iterator", "MutableIterator": "java/util/Iterator", "ListIterator": "java/util/ListIterator", "MutableListIterator": "java/util/ListIterator", "Collection": "java/util/Collection", "MutableCollection": "java/util/Collection", "List": "java/util/List", "MutableList": "java/util/List", "Set": "java/util/Set", "MutableSet": "java/util/Set", "Map": "java/util/Map", "MutableMap": "java/util/Map"]
    static let exceptionNames: Set<String> = ["NoSuchElementException", "UnsupportedOperationException", "Throwable", "Exception", "RuntimeException", "IllegalArgumentException", "IllegalStateException", "IndexOutOfBoundsException", "ArrayIndexOutOfBoundsException", "ArithmeticException", "NumberFormatException", "NullPointerException", "ClassCastException", "NegativeArraySizeException"]
    static func builtinName(_ name: String) -> String? {
        if name == "java/util/MapEntry" { return "java/util/Map$Entry" }
        if ["java/util/AbstractCollection", "java/util/RandomAccess", "java/util/AbstractList", "java/util/AbstractSet", "java/util/AbstractMap", "java/util/ListIterator"].contains(name) { return name }
        if name == "kotlin/collections/AbstractSet" { return name }
        if ["kotlin/Function", "kotlin/Lazy", "kotlin/LazyThreadSafetyMode", "kotlin/reflect/KProperty", "kotlin/reflect/KMutableProperty", "kotlin/UninitializedPropertyAccessException", "kotlin/properties/ReadOnlyProperty", "kotlin/properties/ReadWriteProperty", "kotlin/properties/Delegates"].contains(name) { return name }
        if name.hasPrefix("kotlin/reflect/") || name == "java/lang/Class" { return name }
        if ["java/util/NoSuchElementException", "java/lang/StackTraceElement", "java/lang/reflect/Method", "java/lang/reflect/InvocationHandler"].contains(name) { return name }
        if name == "kotlin/Annotation" { return "java/lang/annotation/Annotation" }
        if name == "kotlin/annotation/AnnotationTarget" || name == "kotlin/annotation/AnnotationRetention" { return name }
        if name == "kotlin/Enum" { return "java/lang/Enum" }
        if name == "kotlin/enums/EnumEntries" { return "kotlin/enums/EnumEntries" }
        if ["kotlin/collections/IntIterator", "java/util/ArrayList"].contains(name) { return name }
        if ["kotlin/collections/Map$Entry", "kotlin/collections/MutableMap$MutableEntry"].contains(name) { return "java/util/Map$Entry" }
        if name == "kotlin/Result" { return "java/lang/Object" }
        if ["kotlin/coroutines/Continuation", "kotlin/coroutines/CoroutineContext", "kotlin/coroutines/EmptyCoroutineContext"].contains(name) { return name }
        if name == "kotlin/text/StringBuilder" { return "java/lang/StringBuilder" }
        if ["kotlin/text/Regex", "kotlin/text/Regex$Companion", "kotlin/text/RegexOption", "kotlin/text/MatchResult", "kotlin/text/MatchResult$Destructured", "kotlin/text/MatchGroup", "kotlin/text/MatchGroupCollection", "kotlin/ranges/IntRange", "kotlin/sequences/Sequence", "kotlin/sequences/SequenceScope"].contains(name) { return name }
        if name == "kotlin/NoSuchElementException" { return "java/util/NoSuchElementException" }
        if name == "kotlin/CharSequence" { return "java/lang/CharSequence" }
        if name == "kotlin/Number" { return "java/lang/Number" }
        if name == "kotlin/Pair" || name == "java/io/Serializable" { return name }
        if name == "kotlin/Comparator" { return "java/util/Comparator" }
        if name == "kotlin/Comparable" { return "java/lang/Comparable" }
        if name.hasPrefix("kotlin/collections/"), let mapped = collectionNames[String(name.split(separator: "/").last!)] { return mapped }
        if name.hasPrefix("kotlin/"), exceptionNames.contains(String(name.dropFirst(7))) { return "java/lang/" + name.dropFirst(7) }
        return nil
    }
    static func boxed(_ type: JVMValueType) -> JVMValueType {
        if let name = type.boxName { return .reference(name, nullable: type.isNullable) }
        return type
    }
    static func argumentType(_ arg: TypeArg, sema: SemaModule, ctx: CompilationContext) throws -> JVMValueType {
        switch arg {
        case let .invariant(t), let .out(t):
            let value = try type(t, sema: sema, ctx: ctx)
            guard value != .unit else { throw JVMFrontendError(message: "JVM M5 does not support Unit array elements.") }
            return boxed(value)
        case .in, .star: return .reference("java/lang/Object", nullable: true)
        }
    }
}

extension JVMProgramBuilder {
    func varargComponentType(_ id: TypeID) throws -> JVMValueType {
        let component = try type(id)
        // Generic varargs use Array<T>, even when a final primitive bound
        // gives individual T values a primitive descriptor.
        if case .typeParam = sema.types.kind(of: id) { return JVMClasspathIndex.boxed(component) }
        return component
    }

    func kotlinType(_ id: TypeID) throws -> JVMKotlinType {
        if sema.types.nullability(of: id) == .platformType {
            return .flexible(try kotlinType(sema.types.withNullability(.nonNull, for: id)), try kotlinType(sema.types.withNullability(.nullable, for: id)))
        }
        func named(_ name: String, _ nullable: Bool = false) -> JVMKotlinType { .named(name, [], nullable: nullable) }
        switch sema.types.kind(of: id) {
        case let .functionType(f):
            _ = try type(id)
            return .function(try f.params.map(kotlinType), try kotlinType(f.returnType), receiver: try f.receiver.map(kotlinType), nullable: f.nullability != .nonNull, isSuspend: f.isSuspend)
        case .unit: return named("kotlin/Unit")
        case .nullableUnit: return named("kotlin/Unit", true)
        case let .nothing(nullability): return named("kotlin/Nothing", nullability == .nullable)
        case let .primitive(p, n): return named("kotlin/" + p.kotlinName, n != .nonNull)
        case let .stringStruct(n): return named("kotlin/String", n != .nonNull)
        case let .any(n): return named("kotlin/Any", n != .nonNull)
        case let .kClassType(t): return .named("kotlin/reflect/KClass", [JVMKotlinTypeArgument(type: try kotlinType(t.argument), variance: 2)], nullable: t.nullability != .nonNull)
        case let .typeParam(t): return .parameter(Int(t.symbol.rawValue), nullable: t.nullability == .nullable)
        case let .classType(t):
            let name = try className(t.classSymbol)
            return .named(name, try t.args.map(kotlinArgument), nullable: t.nullability != .nonNull)
        default: throw JVMFrontendError(message: "Unsupported JVM generic metadata type.")
        }
    }
    func kotlinArgument(_ arg: TypeArg) throws -> JVMKotlinTypeArgument {
        switch arg {
        case let .invariant(t): return JVMKotlinTypeArgument(type: try kotlinType(t), variance: 2)
        case let .in(t): return JVMKotlinTypeArgument(type: try kotlinType(t), variance: 0)
        case let .out(t): return JVMKotlinTypeArgument(type: try kotlinType(t), variance: 1)
        case .star: return JVMKotlinTypeArgument(type: nil, variance: 3)
        }
    }
    func signatureType(_ id: TypeID, boxed: Bool = false, parameterPosition: Bool = false) throws -> String {
        switch sema.types.kind(of: id) {
        case let .functionType(f):
            let name = try type(id).referenceName!
            let params = ([f.receiver].compactMap { $0 } + f.params)
            func argument(_ t: TypeID) throws -> String { if case .unit = sema.types.kind(of: t) { return "Lkotlin/Unit;" }; return try signatureType(t, boxed: true) }
            return "L" + name + "<" + (try params.map { (parameterPosition ? "-" : "") + (try argument($0)) }).joined() + (f.isSuspend ? "-Lkotlin/coroutines/Continuation<-" + (try argument(f.returnType)) + ">;Ljava/lang/Object;" : (parameterPosition ? "+" : "") + (try argument(f.returnType))) + ">;"
        case let .kClassType(t): return "Lkotlin/reflect/KClass<" + (try signatureType(t.argument, boxed: true)) + ">;"
        case let .typeParam(t): return "T" + context.interner.resolve(sema.symbols.symbol(t.symbol)!.name) + ";"
        case let .classType(t):
            let source = try className(t.classSymbol)
            if source == "kotlin/Result" { return "Ljava/lang/Object;" }
            if source == "kotlin/Array" {
                guard let arg = t.args.first else { throw JVMFrontendError(message: "JVM Array requires its element type.") }
                switch arg {
                case let .invariant(id), let .out(id): return "[" + (try signatureType(id, boxed: true))
                default: return "[Ljava/lang/Object;"
                }
            }
            let erased = try type(id)
            if erased.referenceName?.hasPrefix("[") == true { return erased.descriptor }
            let variances = sema.types.nominalTypeParameterVariances(for: t.classSymbol)
            func argument(_ id: TypeID) throws -> String {
                if source == "kotlin/coroutines/Continuation", case .unit = sema.types.kind(of: id) { return "Lkotlin/Unit;" }
                return try signatureType(id, boxed: true, parameterPosition: parameterPosition)
            }
            let args = try t.args.enumerated().map { i, arg -> String in
                switch arg {
                case let .invariant(t):
                    let variance = parameterPosition && variances.indices.contains(i) ? variances[i] : .invariant
                    return (variance == .out ? "+" : (variance == .in ? "-" : "")) + (try argument(t))
                case let .in(t): return "-" + (try argument(t))
                case let .out(t): return "+" + (try argument(t))
                case .star: return "*"
                }
            }.joined()
            return "L" + erased.referenceName! + (args.isEmpty ? "" : "<" + args + ">") + ";"
        default:
            let t = try type(id)
            if boxed && t == .unit { throw JVMFrontendError(message: "JVM M5 does not support Unit type arguments.") }
            return (boxed ? JVMClasspathIndex.boxed(t) : t).descriptor
        }
    }
    func typeParameters(_ symbols: [SymbolID], declarations: [TypeParamDecl]) throws -> [JVMTypeParameter] {
        guard symbols.count == declarations.count, declarations.allSatisfy({ $0.annotations.isEmpty }) else { throw JVMFrontendError(message: "Unsupported JVM type parameter annotations.") }
        return try zip(symbols, declarations).map { symbol, decl in
            let name = context.interner.resolve(decl.name)
            guard Self.isIdentifier(name) else { throw JVMFrontendError(message: "JVM type parameter needs an ASCII name.") }
            let bounds = sema.symbols.typeParameterUpperBounds(for: symbol)
            guard bounds.count <= 1 else { throw JVMFrontendError(message: "JVM M5 supports one upper bound per type parameter.") }
            let bound = try bounds.first.map { try signatureType($0, boxed: true) } ?? "Ljava/lang/Object;"
            let isInterface = bounds.first.map { id in if case let .classType(t) = sema.types.kind(of: id) { return sema.symbols.symbol(t.classSymbol)?.kind == .interface }; return false } ?? false
            return JVMTypeParameter(id: Int(symbol.rawValue), name: name, variance: decl.variance == .out ? 1 : (decl.variance == .in ? 0 : 2), bounds: try bounds.map(kotlinType), signature: name + (isInterface ? "::" : ":") + bound, isReified: decl.isReified)
        }
    }
    func describe(_ function: JVMFunction, signature: FunctionSignature, parameters: [TypeParamDecl]) throws -> JVMFunction {
        var f = function
        if f.reference.name.contains("$unsigned$") { f.sourceName = String(f.reference.name.components(separatedBy: "$unsigned$")[0]) }
        f.typeParameters = try typeParameters(Array(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)), declarations: parameters)
        f.kotlinParameters = try signature.parameterTypes.map(kotlinType)
        let sourceDeclaration = sourceDeclarations.first {
            if let ref = references[$0.key] { return ref.name == function.reference.name && ref.owner == function.owner && ref.descriptor == function.reference.descriptor }
            if let method = methods[$0.key] { return method.name == function.reference.name && method.owner == function.owner && method.descriptor == function.reference.descriptor }
            return false
        }
        let declaration = sourceDeclaration?.value
        if let symbol = sourceDeclaration?.key {
            if let effect = sema.symbols.contractConditionEffect(for: symbol), effect.returnsValue == nil,
               signature.parameterTypes.indices.contains(effect.conditionParameterIndex),
               signature.parameterTypes[effect.conditionParameterIndex] == sema.types.booleanType {
                f.normalReturnConditionParameter = effect.conditionParameterIndex
            } else if let effect = sema.symbols.contractNonNullEffect(for: symbol), effect.appliesOnAnyReturn,
                      let index = signature.valueParameterSymbols.firstIndex(of: effect.parameterSymbol),
                      signature.parameterTypes.indices.contains(index), signature.parameterTypes[index] == sema.types.booleanType {
                // Source-backed preconditions share this Boolean condition rail
                // with Sema's post-call smart-cast analysis.
                f.normalReturnConditionParameter = index
            }
        }
        if let declaration {
            f.sourceName = context.interner.resolve(declaration.name)
            f.parameterVarargTypes = try declaration.valueParams.enumerated().map { i, p in p.isVararg ? try kotlinType(signature.parameterTypes[i]) : nil }
            for (i, p) in declaration.valueParams.enumerated() where p.isVararg {
                let element = try varargComponentType(signature.parameterTypes[i])
                if element.referenceName == nil, let primitive = JVMClasspathIndex.primitiveArrays.first(where: { $0.value == element }) {
                    f.kotlinParameters[i] = .named("kotlin/" + primitive.key, [], nullable: false)
                } else { f.kotlinParameters[i] = .named("kotlin/Array", [JVMKotlinTypeArgument(type: f.parameterVarargTypes[i]!, variance: 1)], nullable: false) }
            }
        }
        f.kotlinResult = try kotlinType(signature.returnType)
        if !f.isConstructor && f.reference.parameters.count == signature.parameterTypes.count + 1 { f.kotlinReceiver = try signature.receiverType.map(kotlinType) }
        f.genericSignature = (f.typeParameters.isEmpty ? "" : "<" + f.typeParameters.map(\.signature).joined() + ">") + "(" + (try ((f.kotlinReceiver == nil ? [] : [signature.receiverType].compactMap { $0 }) + signature.parameterTypes).map { try signatureType($0, parameterPosition: true) }).joined() + ")" + (f.isConstructor ? "V" : try signatureType(signature.returnType))
        if let declaration, declaration.valueParams.contains(where: \.isVararg) {
            let prefix = f.typeParameters.isEmpty ? "" : "<" + f.typeParameters.map(\.signature).joined() + ">"
            f.genericSignature = prefix + "(" + (try f.kotlinReceiver == nil ? "" : signatureType(signature.receiverType!, parameterPosition: true)) + (try signature.parameterTypes.enumerated().map { i, parameter in (declaration.valueParams[i].isVararg ? "[" : "") + (try signatureType(parameter, parameterPosition: true)) }).joined() + ")" + (try signatureType(signature.returnType))
            f.access = (f.access ?? 9) | 0x80
        }
        return f
    }
}
