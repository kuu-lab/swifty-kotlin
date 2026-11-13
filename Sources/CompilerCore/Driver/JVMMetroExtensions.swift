extension JVMMetroBindingEmitter {
    func extensionBinding(_ key: JVMMetroBindingKey) throws -> JVMMetroBinding? {
        guard key.qualifiers.isEmpty, key.type.hasPrefix("L"), key.type.hasSuffix(";"), !key.type.contains("<"),
              let imports = program.context.jvmImports else { return nil }
        let name = String(key.type.dropFirst().dropLast())
        if let child = imports.metroClassInfo(name), !child.annotations.metro(JVMMetro.graphExtension).isEmpty {
            return try makeExtension(child, inputs: [])
        }
        guard let factory = imports.metroClassInfo(name), !factory.annotations.metro(JVMMetro.extensionFactory).isEmpty,
              factory.annotations.metro(JVMMetro.contributesTo).contains(where: {
                  $0.metroClass("scope").map(scopes.contains) == true
              }),
              let method = factory.methods.first(where: { $0.isAbstract && !$0.isStatic && !$0.isConstructor }),
              let childName = method.result.referenceName, let child = imports.metroClassInfo(childName),
              !child.annotations.metro(JVMMetro.graphExtension).isEmpty else { return nil }
        try addExtensionFactory(factory, method: method, child: child)
        return JVMMetroBinding(recipe: .graph, type: .reference(factory.name, nullable: false), scope: nil)
    }

    private func makeExtension(_ child: JVMClassInfo, inputs: [(JVMMetroBindingKey, JVMValueType)]) throws -> JVMMetroBinding {
        let name = implementation + "$" + (child.name.split(separator: "/").last.map(String.init) ?? child.name) + "Impl"
        let parentType = JVMValueType.reference(implementation, nullable: false)
        let parentField = JVMField(owner: name, name: "parentGraph", type: parentType, access: 0x0012)
        let fields = inputs.enumerated().map { index, input in
            JVMField(owner: name, name: "input" + String(index), type: input.1, access: 0x0012)
        }
        let annotation = child.annotations.metro(JVMMetro.graphExtension).first
        let scope = annotation?.metroClass("scope")
        let additional = annotation?.metroClasses("additionalScopes") ?? []
        let excluded = Set(annotation?.metroClasses("excludes") ?? [])
        var bindings = try program.metroBindings(scope: scope, additionalScopes: additional, excluded: excluded)
        for (input, field) in zip(inputs, fields) {
            bindings[input.0, default: []].append(JVMMetroBinding(recipe: .input(field), type: field.type, scope: nil))
        }
        try program.addMetroProviders(from: child, to: &bindings)
        let emitter = JVMMetroBindingEmitter(
            program: program, implementation: name, range: range,
            scopes: Set([scope].compactMap { $0 } + additional), bindings: bindings,
            parent: self, parentField: parentField, graphInterface: child.name
        )
        let entries = try program.metroGraphMethods(child.name, range: range).map { method in
            try emitter.entry(method, key: program.metroBindingKey(method.metroTypes.result, annotations: method.annotations))
        }
        let constructor = program.metroConstructor(name, fields: [parentField] + fields)
        let output = program.rawClass(name, interfaces: [child.name] + emitter.extensionInterfaces, access: 0x0030,
                                      functions: [constructor] + entries + emitter.methods,
                                      fields: [parentField] + fields + emitter.fields)
        classes += [output] + emitter.classes
        return JVMMetroBinding(recipe: .extensionGraph(name),
                               type: .reference(child.name, nullable: false), scope: nil)
    }

    private func addExtensionFactory(_ factory: JVMClassInfo, method: JVMForeignMethod, child: JVMClassInfo) throws {
        guard extensionFactories.insert(factory.name).inserted else { return }
        let inputs = try program.metroDependencies(method)
        let types = method.parameters
        let logicalTypes = types.enumerated().map { index, type in
            let parameters = method.kotlinFunction?.parameters ?? []
            return parameters.indices.contains(index) ? program.metroValueType(parameters[index].sourceType) ?? type : type
        }
        let logicalInputs = inputs.enumerated().map { index, key in
            JVMMetroBindingKey(logicalTypes[index] == types[index] ? key.type : logicalTypes[index].descriptor,
                               qualifiers: key.qualifiers)
        }
        let childBinding = try makeExtension(child, inputs: Array(zip(logicalInputs, logicalTypes)))
        guard case let .extensionGraph(name) = childBinding.recipe else { preconditionFailure() }
        let builder = try makeBuilder(method.name, result: method.result)
        let receiver = try builder.value(.reference(implementation, nullable: false))
        let arguments = try types.map { try builder.value($0) }
        let logicalArguments = try zip(arguments, logicalTypes).map { try builder.convert($0, to: $1) }
        let result = try builder.constructJDK(name, parameters: [receiver.type] + logicalTypes, arguments: [receiver] + logicalArguments)
        builder.instructions.append(.returnValue(result))
        let function = program.rawFunction(implementation, name: method.name, parameters: types, result: method.result,
                                           access: 0x0011, locals: builder.locals, instructions: builder.instructions)
        methods.append(function)
        let contribution = program.context.jvmImports?.metroAnnotatedClasses.first {
            $0.interfaces.contains(factory.name)
                && $0.annotations.metro(JVMMetro.contribution).contains {
                    $0.metroClass("scope").map(scopes.contains) == true
                }
        }
        extensionInterfaces.append(contribution?.name ?? factory.name)
    }
}
