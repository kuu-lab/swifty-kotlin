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
            return function.jvmName == method.name && (function.isPublic || function.isProtected)
                && (parameterCount == method.parameters.count
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
        let expectedMasks = (function.parameters.count + 31) / 32
            + (function.parameters.contains(where: \.hasDefault) ? 1 : 0)
        let masks = suffix.dropFirst()
        return masks.count == expectedMasks && masks.allSatisfy({ $0 == .int })
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
        case .function(let inputs, let result, let receiver, let nullable, let suspend, _):
            let inputs = inputs.map { kotlinSourceType($0, parameters: parameters) }.joined(separator: ", ")
            let receiver = receiver.map { kotlinSourceType($0, parameters: parameters) + "." } ?? ""
            let result = kotlinSourceType(result, parameters: parameters)
            let declaration = (suspend ? "suspend " : "") + receiver + "(" + inputs + ") -> " + result
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
        case .function(let inputs, let result, let receiver, _, _, let context):
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
        case .function(let inputs, _, let receiver, _, let suspend, _):
            let arity = inputs.count + (receiver == nil ? 0 : 1) + (suspend ? 1 : 0)
            return "Lkotlin/jvm/functions/Function\(arity);"
        }
    }
}
