extension JVMClasspathIndex {
    func javaGenericSupertype(_ name: String, of child: JVMClassInfo) -> (source: String, referencedClasses: Set<String>)? {
        guard child.isKotlinFileFacade == nil, classes[name]?.isKotlinFileFacade == nil,
              let signature = child.genericSupertypeSignatures[name], let base = kotlinSupertypeName(name)
        else { return nil }
        let type = JVMValueType.reference(name, nullable: false)
        var accessor = JVMForeignMethod(owner: child.name, name: "", descriptor: "()" + type.descriptor,
                                        parameters: [], result: type, isStatic: false, isInterface: false, isAbstract: false)
        accessor.genericSignature = "()" + signature
        guard let types = javaGenericTypes(accessor), let arguments = types.result.firstIndex(of: "<") else { return nil }
        return (base + types.result[arguments...], types.referencedClasses)
    }

    func javaTypeParameterBounds(_ info: JVMClassInfo) -> (bounds: [String], referencedClasses: Set<String>) {
        var bounds: [String] = []
        var references: Set<String> = []
        for name in info.classTypeParameterNames {
            for bound in info.javaClassTypeParameterBounds[name] ?? [] where bound.first == "L" {
                let binary = String(bound.dropFirst().prefix { $0 != "<" && $0 != ";" })
                let carrier: JVMValueType = .reference(binary, nullable: false)
                guard exposeSuspendType(carrier) else { continue }
                // A simple bound has the same erasure and source type.
                // Parameterized bounds need a projection such as Enum<*>.
                let source = kotlinType(carrier)
                guard !source.contains("<") else { continue }
                bounds.append("`\(name)`: " + source)
                references.insert(binary)
            }
        }
        return (bounds, references)
    }

    /// Recover Java source types for simple parameterized signatures. The
    /// classfile descriptor remains the source of truth for invocation.
    func javaGenericTypes(_ method: JVMForeignMethod) -> (parameters: [String], result: String, typeParameters: [String], bounds: [(name: String, type: String)], referencedClasses: Set<String>)? {
        guard let owner = classes[method.owner], owner.isKotlinFileFacade == nil,
              let signature = method.genericSignature, !method.isConstructor
        else { return nil }

        let canUseGenericMembers = !method.owner.hasPrefix("java/") && !method.owner.hasPrefix("javax/")
        var remaining = signature[...]
        var methodTypeParameters: [String] = []
        var methodBounds: [(name: String, type: String)] = []
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
                let javaGenerics = ["java/lang/Class", "java/util/concurrent/Callable", "java/lang/Iterable"]
                let hasTypeParameters = classes[name]?.classTypeParameterNames.isEmpty == false
                guard depth == 0 && mappedCollections.contains(name)
                    || canUseGenericMembers && (!source.contains("<") || mappedCollections.contains(name)
                        || javaGenerics.contains(name) || hasTypeParameters && !name.hasPrefix("java/"))
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
                    let variance = if marker == "+" {
                        "out "
                    } else if marker == "-" && !mappedCollections.contains(name) && name != "java/lang/Iterable" {
                        "in "
                    } else {
                        ""
                    }
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

        if remaining.first == "<", canUseGenericMembers {
            remaining.removeFirst()
            while remaining.first != ">", let colon = remaining.firstIndex(of: ":") {
                let name = String(remaining[..<colon])
                guard JVMProgramBuilder.isIdentifier(name), !methodTypeParameters.contains(name),
                      methodTypeParameters.count < 16 else { return nil }
                methodTypeParameters.append(name)
                remaining = remaining[remaining.index(after: colon)...]
                if remaining.first != ":" {
                    let objectBound = "Ljava/lang/Object;"
                    if remaining.hasPrefix(objectBound) {
                        remaining = remaining.dropFirst(objectBound.count)
                    } else {
                        guard let type = parseType() else { return nil }
                        methodBounds.append((name, type))
                    }
                }
                while remaining.first == ":" {
                    remaining.removeFirst()
                    guard let type = parseType() else { return nil }
                    methodBounds.append((name, type))
                }
            }
            guard remaining.first == ">", !methodTypeParameters.isEmpty else { return nil }
            remaining.removeFirst()
        }
        guard remaining.first == "(" else { return nil }
        remaining.removeFirst()

        var parameters: [String] = []
        for carrier in method.parameters {
            guard let parameter = parseType(carrier) else { return nil }
            parameters.append(parameter)
        }
        guard remaining.first == ")" else { return nil }
        remaining.removeFirst()
        guard let result = parseType(method.result), hasGenericType,
              remaining.isEmpty || remaining.first == "^" else { return nil }
        return (parameters, result, methodTypeParameters, methodBounds, referencedClasses)
    }
}
