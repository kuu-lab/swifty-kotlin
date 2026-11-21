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

    func javaInstanceFieldSourceType(_ field: JVMForeignField, in owner: JVMClassInfo, erased: JVMValueType) -> String {
        let source: String
        if let signature = field.genericSignature {
            var accessor = JVMForeignMethod(owner: owner.name, name: field.name, descriptor: "()" + field.descriptor,
                                            parameters: [], result: erased, isStatic: false, isInterface: owner.isInterface, isAbstract: false)
            accessor.genericSignature = "()" + signature
            source = javaGenericTypes(accessor)?.result ?? kotlinType(erased)
        } else {
            source = kotlinType(erased)
        }
        // Java fields use platform collection types, which permit mutating
        // the referenced collection even when the field itself is final.
        if owner.isKotlinFileFacade == nil && erased.referenceName == "java/util/Map" {
            let readOnly = "kotlin.collections.Map"
            if source.hasPrefix(readOnly + "<") {
                return "kotlin.collections.MutableMap" + source.dropFirst(readOnly.count)
            }
        }
        return source
    }

    func javaTypeParameterBounds(_ info: JVMClassInfo) -> (bounds: [String], referencedClasses: Set<String>) {
        var bounds: [String] = []
        var references: Set<String> = []
        for name in info.classTypeParameterNames {
            for (binary, source) in renderableJavaClassBounds(name, in: info) {
                bounds.append("`\(name)`: " + source + "?")
                references.insert(binary)
            }
        }
        return (bounds, references)
    }

    func javaClassTypeParameterErasure(_ name: String, in info: JVMClassInfo) -> String {
        renderableJavaClassBounds(name, in: info).first.map { "L" + $0.binary + ";" } ?? "Ljava/lang/Object;"
    }

    private func renderableJavaClassBounds(_ name: String, in info: JVMClassInfo) -> [(binary: String, source: String)] {
        (info.javaClassTypeParameterBounds[name] ?? []).compactMap { bound -> (binary: String, source: String)? in
            guard bound.first == "L" else { return nil }
            let binary = String(bound.dropFirst().prefix { $0 != "<" && $0 != ";" })
            let carrier: JVMValueType = .reference(binary, nullable: false)
            guard exposeSuspendType(carrier) else { return nil }
            let source = kotlinType(carrier)
            return source.contains("<") ? nil : (binary, source)
        }
    }

    /// Recover Java source types for simple parameterized signatures. The
    /// classfile descriptor remains the source of truth for invocation.
    func javaGenericTypes(_ method: JVMForeignMethod) -> (parameters: [String], result: String, typeParameters: [String], bounds: [(name: String, type: String)], referencedClasses: Set<String>)? {
        guard let owner = classes[method.owner], owner.isKotlinFileFacade == nil,
              let signature = method.genericSignature
        else { return nil }

        let canUseGenericMembers = !method.owner.hasPrefix("java/") && !method.owner.hasPrefix("javax/")
        var remaining = signature[...]
        var methodTypeParameters: [String] = []
        var methodBounds: [(name: String, type: String)] = []
        var methodErasures: [String: String] = [:]
        var hasGenericType = false
        var referencedClasses: Set<String> = []

        func parseType(_ carrier: JVMValueType? = nil, depth: Int = 0) -> String? {
            guard depth < 16, let first = remaining.first else { return nil }
            remaining.removeFirst()
            if first == "T" {
                guard let end = remaining.firstIndex(of: ";") else { return nil }
                let name = String(remaining[..<end])
                let isMethodVariable = methodTypeParameters.contains(name)
                guard canUseGenericMembers, isMethodVariable
                    || owner.classTypeParameterNames.contains(name) && !method.isStatic else { return nil }
                if let carrier {
                    let erasure = isMethodVariable ? methodErasures[name] ?? "Ljava/lang/Object;"
                        : javaClassTypeParameterErasure(name, in: owner)
                    guard carrier.descriptor == erasure else { return nil }
                }
                remaining = remaining[remaining.index(after: end)...]
                hasGenericType = true
                return "`\(name)`"
            }
            if first == "[" {
                let component = carrier.flatMap { type -> JVMValueType? in
                    guard type.descriptor.hasPrefix("[") else { return nil }
                    return try? JVMDescriptor.parse("()" + type.descriptor.dropFirst()).1
                }
                if let component, component.referenceName == nil, let carrier {
                    guard let marker = remaining.first, marker == component.descriptor.first else { return nil }
                    remaining.removeFirst()
                    return kotlinType(carrier)
                }
                guard let element = parseType(component, depth: depth + 1) else { return nil }
                return "kotlin.Array<" + element + ">"
            }
            if first != "L" {
                guard let carrier, first == carrier.descriptor.first else { return nil }
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
                let javaGenerics = ["java/lang/Class", "java/util/concurrent/Callable", "java/lang/Iterable", "java/lang/Comparable"]
                let hasTypeParameters = classes[name]?.classTypeParameterNames.isEmpty == false
                guard depth == 0 && mappedCollections.contains(name)
                    || canUseGenericMembers && (!source.contains("<") || mappedCollections.contains(name)
                        || javaGenerics.contains(name) || hasTypeParameters && !name.hasPrefix("java/"))
                else { return nil }
                source = String(source.prefix { $0 != "<" })
                remaining.removeFirst()
                var arguments: [String] = []
                var argumentIndex = 0
                while let marker = remaining.first, marker != ">" {
                    defer { argumentIndex += 1 }
                    if marker == "*" {
                        remaining.removeFirst()
                        arguments.append("*")
                        continue
                    }
                    if marker == "+" || marker == "-" { remaining.removeFirst() }
                    guard let argument = parseType(depth: depth + 1) else { return nil }
                    // `? super X` must keep its `in` projection even on the
                    // mapped collections — Kotlin allows a use-site `in`
                    // projection on covariant declarations, and dropping it
                    // would expose `List<? super String>` as `List<String>`
                    // and let String reads compile onto Integer elements.
                    let variance: String
                    if marker == "+" {
                        variance = "out "
                    } else if marker == "-" {
                        variance = "in "
                        // Use-site `in` on the covariant Kotlin read-only
                        // collections is rejected, so `List<? super X>` is
                        // exposed as `MutableList<in X>` — Java collections
                        // are mutable anyway and the lower bound survives.
                        // Map's key is invariant — `Map<in K, V>` is valid
                        // there, so only covariant positions swap to Mutable.
                        let covariantArguments: [String: Set<Int>] = [
                            "kotlin.collections.List": [0],
                            "kotlin.collections.Set": [0],
                            "kotlin.collections.Map": [1],
                            "kotlin.collections.Iterable": [0],
                            "kotlin.collections.Collection": [0],
                        ]
                        for (readonly, positions) in covariantArguments
                        where positions.contains(argumentIndex)
                            && (source.hasPrefix(readonly + "<") || source == readonly) {
                            source = "kotlin.collections.Mutable" + source.dropFirst("kotlin.collections.".count)
                            break
                        }
                    } else {
                        variance = ""
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
                func appendBound() -> Bool {
                    let bound = remaining
                    guard let type = parseType() else { return false }
                    methodBounds.append((name, type))
                    if methodErasures[name] == nil {
                        let binary = String(bound.dropFirst().prefix { $0 != "<" && $0 != ";" })
                        let boxed: Set<String> = ["java/lang/Boolean", "java/lang/Byte", "java/lang/Character", "java/lang/Short",
                                                  "java/lang/Integer", "java/lang/Long", "java/lang/Float", "java/lang/Double"]
                        methodErasures[name] = bound.first == "L" && !boxed.contains(binary) ? "L" + binary + ";" : ""
                    }
                    return true
                }
                if remaining.first != ":" {
                    let objectBound = "Ljava/lang/Object;"
                    if remaining.hasPrefix(objectBound) {
                        remaining = remaining.dropFirst(objectBound.count)
                    } else {
                        guard appendBound() else { return nil }
                    }
                }
                while remaining.first == ":" {
                    remaining.removeFirst()
                    guard appendBound() else { return nil }
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
        guard let result = parseType(method.isConstructor ? .unit : method.result), hasGenericType,
              remaining.isEmpty || remaining.first == "^" else { return nil }
        return (parameters, result, methodTypeParameters, methodBounds, referencedClasses)
    }
}
