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
            let parameterCount = function.parameters.count + (function.receiver == nil ? 0 : 1) + (function.isSuspend ? 1 : 0)
            return function.jvmName == method.name && (function.isPublic || function.isProtected)
                && parameterCount == method.parameters.count
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

    func canExpose(_ method: JVMForeignMethod) -> Bool {
        guard method.isConstructor || JVMProgramBuilder.isIdentifier(method.name) else { return false }
        if let function = kotlinFunction(method) {
            return kotlinReferences(function).allSatisfy { name in
                kotlinTypeAvailable(name)
            }
        }
        if let constructor = kotlinConstructor(method) {
            return constructor.parameters.flatMap { kotlinReferences($0.type) }.allSatisfy(kotlinTypeAvailable)
        }
        return method.parameters.allSatisfy(expose) && expose(method.result)
    }

    func kotlinTypeAvailable(_ name: String) -> Bool {
        name.hasPrefix("kotlin/") || classes[name] != nil || name == "java/lang/ClassLoader"
    }

    func kotlinConstructor(_ method: JVMForeignMethod) -> JVMKotlinConstructorInfo? {
        guard method.isConstructor, let owner = declaringClass(for: method), let metadata = kotlinMetadata(owner) else { return nil }
        let candidates = metadata.constructors.filter {
            ($0.isPublic || $0.isProtected) && $0.parameters.count == method.parameters.count
        }
        return candidates.first { constructor in
            if let descriptor = constructor.descriptor { return descriptor == method.descriptor }
            let parameters = constructor.parameters.map { kotlinErasure($0.type, parameters: metadata.typeParameters) }
            return "(" + parameters.joined() + ")V" == method.descriptor
        } ?? (candidates.count == 1 && candidates[0].descriptor == nil ? candidates[0] : nil)
    }

    func kotlinReferences(_ function: JVMKotlinFunctionInfo) -> [String] {
        let types = [function.result] + [function.receiver].compactMap { $0 } + function.parameters.map(\.type)
            + function.typeParameters.flatMap(\.bounds)
        return types.flatMap(kotlinReferences)
    }

    func kotlinReferences(_ type: JVMKotlinType) -> [String] {
        switch type {
        case .named(let name, let arguments, _):
            return [name] + arguments.compactMap(\.type).flatMap(kotlinReferences)
        case .parameter:
            return []
        case .flexible(let type, _):
            return kotlinReferences(type)
        case .function(let parameters, let result, let receiver, _, _, _):
            return (parameters + [result] + [receiver].compactMap { $0 }).flatMap(kotlinReferences)
        }
    }

    func kotlinFunctionDeclaration(_ function: JVMKotlinFunctionInfo, owner: JVMClassInfo, includeReceiver: Bool = true) -> String {
        let typeParameters = (kotlinMetadata(owner)?.typeParameters ?? []) + function.typeParameters
        let names = Dictionary(typeParameters.map { ($0.id, $0.name) }, uniquingKeysWith: { _, name in name })
        let type = { (type: JVMKotlinType) in self.kotlinSourceType(type, parameters: names) }
        let genericParameters = function.typeParameters.map { parameter in
            let bound = parameter.bounds.first.map { ": " + type($0) } ?? ""
            return "`\(parameter.name)`" + bound
        }
        let generics = genericParameters.isEmpty ? "" : "<" + genericParameters.joined(separator: ", ") + "> "
        var parameters = kotlinParameterDeclarations(function.parameters, typeParameters: names)
        let receiver: String
        if let extensionType = function.receiver {
            if includeReceiver { receiver = type(extensionType) + "." }
            else { receiver = ""; parameters.insert("receiver: " + type(extensionType), at: 0) }
        } else { receiver = "" }
        let operatorModifier = function.isOperator && (includeReceiver || function.receiver == nil) ? "operator " : ""
        let infixModifier = function.isInfix && (includeReceiver || function.receiver == nil) ? "infix " : ""
        return operatorModifier + infixModifier + (function.isSuspend ? "suspend " : "")
            + "fun " + generics + receiver + "`\(function.name)`(" + parameters.joined(separator: ", ") + "): " + type(function.result)
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
        case .parameter(let id, let nullable, let definitelyNotNull):
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
