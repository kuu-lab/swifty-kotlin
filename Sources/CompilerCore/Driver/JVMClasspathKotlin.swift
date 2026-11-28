extension JVMClasspathIndex {
    func declaringClass(for method: JVMForeignMethod) -> JVMClassInfo? {
        classes[method.owner]
    }
    func kotlinMetadata(_ info: JVMClassInfo) -> JVMKotlinClassMetadata? {
        if let cached = kotlinMetadataByClass[info.name] { return cached }
        guard metadataChecked.insert(info.name).inserted,
              let annotation = info.annotations.first(where: { $0.descriptor == "Lkotlin/Metadata;" }) else { return nil }
        guard let metadata = try? JVMKotlinClassMetadata.read(annotation) else { return nil }
        kotlinMetadataByClass[info.name] = metadata
        return metadata
    }

    func kotlinFunction(_ method: JVMForeignMethod) -> JVMKotlinFunctionInfo? {
        guard let owner = declaringClass(for: method), let metadata = kotlinMetadata(owner) else { return nil }
        let candidates = metadata.functions.filter { function in
            let parameterCount = kotlinFunctionParameterCount(function)
            let exactComposeDescriptor = method.kotlinComposeABI != nil && function.descriptor == method.descriptor
            return function.jvmName == method.name && (function.isPublic || function.isProtected)
                && (parameterCount == method.parameters.count
                    || exactComposeDescriptor
                    || isComposeMemberABI(method, function: function, parameterCount: parameterCount))
        }
        if candidates.count == 1, let function = candidates.first,
           isComposeMemberABI(method, function: function, parameterCount: kotlinFunctionParameterCount(function)) {
            return function
        }
        if let exact = candidates.first(where: { function in
            if let descriptor = function.descriptor { return descriptor == method.descriptor }
            let parameters = [function.receiver].compactMap { $0 } + function.parameters.map(\.type)
            let typeParameters = metadata.typeParameters + function.typeParameters
            let parameterDescriptors = parameters.map { kotlinErasure($0, parameters: typeParameters) }.joined()
            if function.isSuspend {
                return method.descriptor == "(" + parameterDescriptors + "Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
            }
            let result: String
            if case .named("kotlin/Unit", _, false) = function.result { result = "V" }
            else { result = kotlinErasure(function.result, parameters: typeParameters) }
            let descriptor = "(" + parameterDescriptors + ")" + result
            return method.descriptor == descriptor
        }) { return exact }
        if candidates.count == 1, candidates[0].descriptor == nil,
           owner.methods.filter({ $0.name == method.name && $0.parameters.count == method.parameters.count }).count == 1 {
            return candidates[0]
        }
        return nil
    }

    func kotlinFunctionParameterCount(_ function: JVMKotlinFunctionInfo) -> Int {
        function.parameters.count + (function.receiver == nil ? 0 : 1) + (function.isSuspend ? 1 : 0)
    }

    func isComposeMemberABI(_ method: JVMForeignMethod, function: JVMKotlinFunctionInfo, parameterCount: Int) -> Bool {
        guard !method.isStatic, !function.isSuspend,
              method.annotations.contains(where: { $0.descriptor == "Landroidx/compose/runtime/Composable;" })
        else { return false }
        let hiddenCount = method.parameters.count - parameterCount
        guard hiddenCount > 1 else { return false }
        let suffix = method.parameters.suffix(hiddenCount)
        guard suffix.first?.referenceName == JVMCompose.composer else { return false }
        let expectedChangeMasks = max(1, (parameterCount + 10) / 10)
        let expectedDefaultMasks = function.parameters.contains(where: \.hasDefault)
            ? (function.parameters.count + 30) / 31 : 0
        let expectedMasks = expectedChangeMasks + expectedDefaultMasks
        let masks = suffix.dropFirst()
        return masks.count == expectedMasks && masks.allSatisfy({ $0 == .int })
    }

    func composeCallbackParameters(_ method: JVMForeignMethod, descriptorTypes: [JVMValueType]) -> Set<Int>? {
        guard !method.isStatic, method.parameters.count == descriptorTypes.count,
              let function = kotlinFunction(method), !function.isSuspend, function.receiver == nil,
              function.parameters.count == method.parameters.count else { return nil }
        let callbacks = Set(function.parameters.indices.filter { index in
            if case .function(_, _, _, _, false, _, true) = function.parameters[index].type { return true }
            return false
        })
        guard !callbacks.isEmpty else { return nil }
        let functionPrefix = "kotlin/jvm/functions/Function"
        let matches = zip(method.parameters, descriptorTypes).enumerated().allSatisfy { index, pair in
            let (physical, logical) = pair
            guard callbacks.contains(index) else { return physical.descriptor == logical.withBoxedUnit.descriptor }
            guard let carrier = logical.referenceName, carrier.hasPrefix(functionPrefix),
                  let arity = Int(carrier.dropFirst(functionPrefix.count)) else { return false }
            return physical.referenceName == functionPrefix + String(arity + 2)
        }
        return matches ? callbacks : nil
    }

    func matchesKotlinParameterTypes(
        _ method: JVMForeignMethod,
        sourceTypes: [TypeID],
        parameterIndices: Set<Int>,
        composableParameters: Set<Int> = [],
        sema: SemaModule,
        ctx: CompilationContext
    ) -> Bool {
        guard composableParameters.isSubset(of: parameterIndices),
              let function = kotlinFunction(method), function.parameters.count == sourceTypes.count,
              parameterIndices.allSatisfy(sourceTypes.indices.contains) else { return false }
        let typeParameters = (declaringClass(for: method).flatMap(kotlinMetadata)?.typeParameters ?? []) + function.typeParameters

        func sourceTypeParameter(_ type: TypeID) -> (name: String, nullable: Bool)? {
            let parameter: TypeParamType
            switch sema.types.kind(of: type) {
            case let .typeParam(value): parameter = value
            case let .intersection(parts):
                guard parts.contains(where: { sema.types.kind(of: $0) == .any(.nonNull) }),
                      let part = parts.first(where: { if case .typeParam = sema.types.kind(of: $0) { return true }; return false }),
                      case let .typeParam(value) = sema.types.kind(of: part) else { return nil }
                parameter = value
            default: return nil
            }
            guard let symbol = sema.symbols.symbol(parameter.symbol) else { return nil }
            return (ctx.interner.resolve(symbol.name), parameter.nullability == .nullable)
        }

        func nullable(_ type: TypeID) -> Bool {
            sema.types.nullability(of: type) != .nonNull
        }

        func sourceNamedType(_ type: TypeID) -> (name: String, arguments: [TypeArg], nullable: Bool)? {
            switch sema.types.kind(of: type) {
            case let .classType(value):
                let name = Self.binaryName(value.classSymbol, sema: sema, ctx: ctx)
                return (name, value.args, value.nullability != .nonNull)
            case let .kClassType(value):
                return ("kotlin/reflect/KClass", [.invariant(value.argument)], value.nullability != .nonNull)
            case let .primitive(value, nullability):
                return ("kotlin/" + value.kotlinName, [], nullability != .nonNull)
            case let .stringStruct(nullability):
                return ("kotlin/String", [], nullability != .nonNull)
            case let .any(nullability):
                return ("kotlin/Any", [], nullability != .nonNull)
            case .unit:
                return ("kotlin/Unit", [], false)
            case .nullableUnit, .platformUnit:
                return ("kotlin/Unit", [], true)
            case let .nothing(nullability):
                return ("kotlin/Nothing", [], nullability != .nonNull)
            default: return nil
            }
        }

        func matches(_ metadataType: JVMKotlinType, _ sourceType: TypeID) -> Bool {
            switch metadataType {
            case .flexible(let lower, let upper):
                return matches(lower, sourceType) || matches(upper, sourceType)
            case let .function(inputs, result, receiver, isNullable, isSuspend, context, _):
                guard case let .functionType(source) = sema.types.kind(of: sourceType),
                      isNullable == nullable(sourceType), isSuspend == source.isSuspend,
                      inputs.count == source.params.count, context.count == source.contextReceivers.count,
                      (receiver == nil) == (source.receiver == nil) else { return false }
                let receiverMatches: Bool
                if let receiver, let sourceReceiver = source.receiver {
                    receiverMatches = matches(receiver, sourceReceiver)
                } else {
                    receiverMatches = true
                }
                return zip(inputs, source.params).allSatisfy { matches($0.0, $0.1) }
                    && zip(context, source.contextReceivers).allSatisfy { matches($0.0, $0.1) }
                    && receiverMatches && matches(result, source.returnType)
            case let .named(name, arguments, isNullable):
                guard let source = sourceNamedType(sourceType), source.name == name,
                      isNullable == source.nullable, arguments.count == source.arguments.count else { return false }
                return zip(arguments, source.arguments).allSatisfy { metadataArgument, sourceArgument in
                    guard let metadataType = metadataArgument.type else {
                        if case .star = sourceArgument { return true }
                        return false
                    }
                    switch (metadataArgument.variance, sourceArgument) {
                    case (0, .in(let type)), (1, .out(let type)), (2, .invariant(let type)):
                        return matches(metadataType, type)
                    default:
                        return false
                    }
                }
            case let .parameter(id, isNullable, _):
                guard let source = sourceTypeParameter(sourceType), isNullable == nullable(sourceType),
                      let expectedName = typeParameters.last(where: { $0.id == id })?.name,
                      source.name == expectedName else { return false }
                return true
            }
        }

        func isComposableFunction(_ type: JVMKotlinType) -> Bool {
            switch type {
            case let .function(_, _, _, _, _, _, isComposable): return isComposable
            case .flexible(let lower, _): return isComposableFunction(lower)
            default: return false
            }
        }

        return parameterIndices.allSatisfy { index in
            guard function.parameters.indices.contains(index) else { return false }
            let parameter = function.parameters[index]
            let metadataType = parameter.varargType ?? parameter.type
            guard !composableParameters.contains(index) || isComposableFunction(metadataType) else { return false }
            return matches(metadataType, sourceTypes[index])
        }
    }

    func matchesComposableCallbackTypes(
        _ method: JVMForeignMethod,
        sourceTypes: [TypeID],
        callbackParameters: Set<Int>,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> Bool {
        matchesKotlinParameterTypes(
            method, sourceTypes: sourceTypes, parameterIndices: callbackParameters,
            composableParameters: callbackParameters, sema: sema, ctx: ctx
        )
    }

    func matchesComposeMemberStub(
        _ method: JVMForeignMethod,
        sourceName: String,
        sourceTypes: [TypeID],
        composableParameters: Set<Int>,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> Bool {
        guard !method.isStatic, method.kotlinComposeABI != nil,
              let function = kotlinFunction(method), function.name == sourceName,
              function.parameters.count == sourceTypes.count else { return false }
        return matchesKotlinParameterTypes(
            method, sourceTypes: sourceTypes, parameterIndices: Set(sourceTypes.indices),
            composableParameters: composableParameters, sema: sema, ctx: ctx
        )
    }

    func isComposeMemberCall(_ method: JVMForeignMethod, descriptorTypes: [JVMValueType]) -> Bool {
        guard let function = kotlinFunction(method) else { return false }
        let parameterCount = kotlinFunctionParameterCount(function)
        guard isComposeMemberABI(method, function: function, parameterCount: parameterCount) else { return false }
        let sourceCount = function.parameters.count + (function.receiver == nil ? 0 : 1)
        guard sourceCount == descriptorTypes.count, method.parameters.count >= descriptorTypes.count else { return false }
        return zip(method.parameters.prefix(descriptorTypes.count), descriptorTypes).allSatisfy { physical, logical in
            let expected: JVMValueType = logical == .unit ? .reference("kotlin/Unit", nullable: false) : logical
            return physical.descriptor == expected.descriptor || importedValueCarrier(for: expected)?.descriptor == physical.descriptor
        }
    }

    func kotlinParameterDeclarations(_ parameters: [JVMKotlinParameterInfo], typeParameters: [Int: String]) -> [String] {
        parameters.map { parameter in
            let modifier = parameter.varargType == nil ? "" : "vararg "
            let type = kotlinSourceType(parameter.varargType ?? parameter.type, parameters: typeParameters)
            let defaultValue = parameter.hasDefault ? " = null!!" : ""
            return modifier + "`\(parameter.name)`: " + type + defaultValue
        }
    }

    func kotlinSourceType(_ type: JVMKotlinType, parameters: [Int: String] = [:]) -> String {
        switch type {
        case .named(let name, let arguments, let nullable):
            let base = name == "java/lang/Appendable" ? "kotlin.text.Appendable" : Self.dottedTypeName(name)
            let args = arguments.map { argument -> String in
                guard let type = argument.type else { return "*" }
                let variance = argument.variance == 0 ? "in " : (argument.variance == 1 ? "out " : "")
                return variance + kotlinSourceType(type, parameters: parameters)
            }
            return base + (args.isEmpty ? "" : "<" + args.joined(separator: ", ") + ">") + (nullable ? "?" : "")
        case .parameter(let id, let nullable, _):
            guard let parameter = parameters[id] else { return "kotlin.Any?" }
            return "`\(parameter)`" + (nullable ? "?" : "")
        case .flexible(let lower, _):
            return kotlinSourceType(lower, parameters: parameters)
        case .function(let inputs, let result, let receiver, let nullable, let suspend, let context, let composable):
            let inputs = inputs.map { kotlinSourceType($0, parameters: parameters) }.joined(separator: ", ")
            let receiver = receiver.map { kotlinSourceType($0, parameters: parameters) + "." } ?? ""
            let result = kotlinSourceType(result, parameters: parameters)
            let contextClause = context.isEmpty ? ""
                : "context(" + context.map { kotlinSourceType($0, parameters: parameters) }.joined(separator: ", ") + ") "
            let declaration = (composable ? "@androidx.compose.runtime.Composable " : "") + contextClause
                + (suspend ? "suspend " : "") + receiver + "(" + inputs + ") -> " + result
            return nullable ? "(" + declaration + ")?" : declaration
        }
    }

    static func kotlinMetadataClassNames(_ type: JVMKotlinType, into names: inout Set<String>) {
        switch type {
        case .named(let name, let arguments, _):
            names.insert(name)
            for argument in arguments {
                if let nested = argument.type { kotlinMetadataClassNames(nested, into: &names) }
            }
        case .parameter:
            break
        case .flexible(let lower, let upper):
            kotlinMetadataClassNames(lower, into: &names)
            kotlinMetadataClassNames(upper, into: &names)
        case .function(let inputs, let result, let receiver, _, _, let context, _):
            for input in inputs + context { kotlinMetadataClassNames(input, into: &names) }
            kotlinMetadataClassNames(result, into: &names)
            if let receiver { kotlinMetadataClassNames(receiver, into: &names) }
        }
    }

    private func kotlinErasure(_ type: JVMKotlinType, parameters: [JVMTypeParameter], boxed: Bool = false) -> String {
        switch type {
        case .named(let name, let arguments, let nullable):
            if name == "kotlin/Array" {
                let element = arguments.first?.type.map { kotlinErasure($0, parameters: parameters, boxed: true) } ?? "Ljava/lang/Object;"
                return "[" + element
            }
            if name.hasPrefix("kotlin/") {
                let short = String(name.dropFirst("kotlin/".count))
                if let primitive = Self.primitiveArrays[short] { return "[" + primitive.descriptor }
                if let wrapper = Self.wrappers[short],
                   let primitive = Self.primitiveArrays[short + "Array"] {
                    return boxed || nullable ? "Ljava/lang/\(wrapper);" : primitive.descriptor
                }
            }
            if name == "kotlin/Any" { return "Ljava/lang/Object;" }
            if name == "kotlin/String" { return "Ljava/lang/String;" }
            return "L" + (Self.builtinName(name) ?? name) + ";"
        case .parameter(let id, _, _):
            guard let bound = parameters.last(where: { $0.id == id })?.bounds.first,
                  case .named = bound else { return "Ljava/lang/Object;" }
            return kotlinErasure(bound, parameters: parameters, boxed: true)
        case .flexible(let lower, _):
            return kotlinErasure(lower, parameters: parameters, boxed: boxed)
        case .function(let inputs, _, let receiver, _, let suspend, let context, let composable):
            let arity = context.count + inputs.count + (receiver == nil ? 0 : 1) + (suspend ? 1 : 0) + (composable ? 2 : 0)
            return "Lkotlin/jvm/functions/Function\(arity);"
        }
    }
}
