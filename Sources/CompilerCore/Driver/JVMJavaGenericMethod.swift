extension JVMClasspathIndex {
    /// Recover Java source types for simple parameterized signatures. The
    /// classfile descriptor remains the source of truth for invocation.
    func javaGenericTypes(_ method: JVMForeignMethod) -> (parameters: [String], result: String, typeParameters: [String], referencedClasses: Set<String>)? {
        guard let owner = classes[method.owner], owner.isKotlinFileFacade == nil,
              let signature = method.genericSignature,
              method.genericResultParameter == nil, !method.isConstructor
        else { return nil }

        let canUseGenericMembers = !method.owner.hasPrefix("java/") && !method.owner.hasPrefix("javax/")
        var remaining = signature[...]
        var methodTypeParameters: [String] = []
        if remaining.first == "<", canUseGenericMembers {
            remaining.removeFirst()
            while let colon = remaining.firstIndex(of: ":"), remaining.first != ">" {
                let name = String(remaining[..<colon])
                guard JVMProgramBuilder.isIdentifier(name), !methodTypeParameters.contains(name),
                      methodTypeParameters.count < 16 else { return nil }
                remaining = remaining[remaining.index(after: colon)...]
                let objectBound = "Ljava/lang/Object;"
                guard remaining.hasPrefix(objectBound) else { return nil }
                remaining = remaining.dropFirst(objectBound.count)
                methodTypeParameters.append(name)
            }
            guard remaining.first == ">", !methodTypeParameters.isEmpty else { return nil }
            remaining.removeFirst()
        }
        guard remaining.first == "(" else { return nil }
        remaining.removeFirst()
        var hasGenericType = false
        var referencedClasses: Set<String> = []

        func parseType(_ carrier: JVMValueType? = nil, depth: Int = 0) -> String? {
            guard depth < 16, let first = remaining.first else { return nil }
            remaining.removeFirst()
            if first == "T" {
                guard let end = remaining.firstIndex(of: ";") else { return nil }
                let name = String(remaining[..<end])
                guard canUseGenericMembers, methodTypeParameters.contains(name)
                    || owner.classTypeParameterNames.contains(name) && !method.isStatic else { return nil }
                remaining = remaining[remaining.index(after: end)...]
                hasGenericType = true
                return "`\(name)`"
            }
            if first != "L" {
                guard let carrier, first == carrier.descriptor.first else { return nil }
                let suffix = carrier.descriptor.dropFirst()
                guard remaining.hasPrefix(suffix) else { return nil }
                remaining = remaining.dropFirst(suffix.count)
                return kotlinType(carrier)
            }
            let name = String(remaining.prefix { $0 != "<" && $0 != ";" })
            guard !name.isEmpty, carrier == nil || carrier?.referenceName == name else { return nil }
            remaining = remaining.dropFirst(name.count)
            let type = JVMValueType.reference(name, nullable: false)
            guard exposeSuspendType(type) else { return nil }
            referencedClasses.insert(name)
            var source = kotlinType(type)
            if remaining.first == "<" {
                let mappedCollections = ["java/util/List", "java/util/Set", "java/util/Map"]
                guard depth == 0 && mappedCollections.contains(name) || canUseGenericMembers && !source.contains("<")
                else { return nil }
                source = String(source.prefix { $0 != "<" })
                remaining.removeFirst()
                var arguments: [String] = []
                while let marker = remaining.first, marker != ">" {
                    if marker == "*" {
                        remaining.removeFirst()
                        arguments.append("*")
                        continue
                    }
                    if marker == "+" || marker == "-" { remaining.removeFirst() }
                    guard let argument = parseType(depth: depth + 1) else { return nil }
                    let variance = marker == "+" ? "out " : marker == "-" ? "in " : ""
                    arguments.append(variance + argument)
                }
                guard remaining.first == ">", !arguments.isEmpty else { return nil }
                remaining.removeFirst()
                source += "<" + arguments.joined(separator: ", ") + ">"
                hasGenericType = true
            }
            guard remaining.first == ";" else { return nil }
            remaining.removeFirst()
            return source
        }

        var parameters: [String] = []
        for carrier in method.parameters {
            guard let parameter = parseType(carrier) else { return nil }
            parameters.append(parameter)
        }
        guard remaining.first == ")" else { return nil }
        remaining.removeFirst()
        guard let result = parseType(method.result), hasGenericType,
              remaining.isEmpty || remaining.first == "^" else { return nil }
        return (parameters, result, methodTypeParameters, referencedClasses)
    }
}
