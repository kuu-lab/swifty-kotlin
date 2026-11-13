extension JVMProgramBuilder {
    func prepareMetroGraphs() throws {
        guard context.jvmImports?.metroDeclarationsFile != nil else { return }
        let factories = classes.values.filter {
            recordsContain($0.symbol, JVMMetro.sourcePackage + ".DependencyGraph.Factory")
        }.sorted { $0.name < $1.name }
        for factory in factories {
            let range = factory.interface?.range ?? factory.declaration?.range
            guard factory.isInterface, let parent = factory.outer, let graph = classes[parent], graph.isInterface,
                  recordsContain(parent, JVMMetro.sourcePackage + ".DependencyGraph") else {
                throw JVMFrontendError(message: "Metro factory must be an interface nested inside a dependency graph.", range: range)
            }
            let methods = declaredInterfaceMethods(factory).filter(\.isAbstract)
            guard methods.count == 1, let method = methods.first, !method.isSuspend,
                  method.result.referenceName == graph.name else {
                throw JVMFrontendError(message: "Metro factory must have one abstract method returning its dependency graph.", range: range)
            }
            let factorySymbol = factory.methodSymbols[jvmMemberKey(method)]
            let parameterSymbols = factorySymbol.flatMap { sema.symbols.functionSignature(for: $0)?.valueParameterSymbols } ?? []
            guard try parameterSymbols.count == method.parameters.count && parameterSymbols.allSatisfy({
                try (annotations(for: $0, target: nil) + annotations(for: $0, target: "param"))
                    .contains { $0.descriptor == JVMMetro.provides }
            }) else {
                throw JVMFrontendError(message: "Metro factory arguments must declare @Provides instance bindings.", range: range)
            }

            let implementation = graph.name + "$Impl"
            let fields = method.parameters.enumerated().map { index, type in
                JVMField(owner: implementation, name: "input" + String(index), type: type, access: 0x0012)
            }
            let graphMethods = try metroGraphMethods(graph, implementation: implementation, inputs: fields)
            var graphClass = rawClass(implementation, interfaces: [graph.name], access: 0x0031,
                                      functions: [metroConstructor(implementation, fields: fields)] + graphMethods, fields: fields)
            graphClass.outerName = graph.name
            graphClass.innerName = "Impl"
            graphClass.annotations = [JVMAnnotation(descriptor: JVMMetro.implementation)]
            let (factoryClass, instance) = try metroFactoryClass(factory, method: method, implementation: implementation)
            metroFactoryFields[factory.symbol] = instance
            metroClasses += [graphClass, factoryClass]
        }
    }

    private func metroGraphMethods(
        _ graph: JVMClassPlan, implementation: String, inputs: [JVMField]
    ) throws -> [JVMFunction] {
        var entries = effectiveInterfaceMethods(graph)
        var pending = graph.interfaces
        var visited: Set<String> = []
        while let owner = pending.popLast() {
            guard visited.insert(owner).inserted else { continue }
            if let source = classes.values.first(where: { $0.name == owner && $0.isInterface }) {
                pending += source.interfaces
            } else if let info = context.jvmImports?.classes[owner] {
                pending += info.interfaces
                for method in info.methods where method.owner == owner && !method.isStatic && !method.isConstructor {
                    if entries[jvmMemberKey(method)] == nil { entries[jvmMemberKey(method)] = method }
                }
            }
        }

        let groupedInputs = Dictionary(grouping: inputs, by: { $0.type.descriptor })
        let receiver = JVMValue(slot: 0, type: .reference(implementation, nullable: false))
        return try entries.values.filter(\.isAbstract).sorted { jvmMemberKey($0) < jvmMemberKey($1) }.map { method in
            guard !method.isSuspend, method.parameters.isEmpty,
                  let matches = groupedInputs[method.result.descriptor], matches.count == 1, let field = matches.first else {
                throw JVMFrontendError(
                    message: "Metro graph \(graph.name) cannot resolve binding for \(method.name)\(method.descriptor).",
                    range: graph.interface?.range
                )
            }
            let result = JVMValue(slot: 1, type: field.type)
            return rawFunction(implementation, name: method.name, parameters: [], result: method.result,
                               access: 0x0011, locals: [receiver, result],
                               instructions: [.getField(field, receiver, result), .returnValue(result)])
        }
    }

    private func metroConstructor(_ owner: String, fields: [JVMField], access: UInt16 = 0) -> JVMFunction {
        let receiver = JVMValue(slot: 0, type: .reference(owner, nullable: false))
        var locals = [receiver]
        var instructions: [JVMInstruction] = [.foreignCall(objectConstructor(), receiver: receiver, arguments: [], result: nil)]
        var slot = 1
        for field in fields {
            let parameter = JVMValue(slot: slot, type: field.type)
            slot += field.type.width
            locals.append(parameter)
            instructions.append(.putField(field, receiver, parameter))
        }
        instructions.append(.returnValue(nil))
        return rawFunction(owner, name: "<init>", parameters: fields.map(\.type), result: .unit,
                           access: access, locals: locals, instructions: instructions, constructor: true)
    }

    private func metroFactoryClass(
        _ factory: JVMClassPlan, method: JVMForeignMethod, implementation: String
    ) throws -> (JVMClass, JVMField) {
        let owner = factory.name + "$Impl"
        let type = JVMValueType.reference(owner, nullable: false)
        let instance = JVMField(owner: owner, name: "INSTANCE", type: type, access: 0x0019)
        let singleton = JVMValue(slot: 0, type: type)
        let initialize = rawFunction(owner, name: "<clinit>", parameters: [], result: .unit, access: 0x0008,
                                     locals: [singleton], instructions: [
            .allocate(owner, singleton),
            .foreignCall(metroConstructorTarget(owner, parameters: []), receiver: singleton, arguments: [], result: nil),
            .putStatic(instance, singleton),
            .returnValue(nil),
        ])

        var slot = 1
        let arguments = method.parameters.map { type in
            defer { slot += type.width }
            return JVMValue(slot: slot, type: type)
        }
        let receiver = JVMValue(slot: 0, type: type)
        let graph = JVMValue(slot: slot, type: .reference(implementation, nullable: false))
        var create = rawFunction(owner, name: method.name, parameters: method.parameters, result: method.result,
                                 access: 0x0011, locals: [receiver] + arguments + [graph], instructions: [
            .allocate(implementation, graph),
            .foreignCall(metroConstructorTarget(implementation, parameters: method.parameters),
                         receiver: graph, arguments: arguments, result: nil),
            .returnValue(graph),
        ])
        create.checksParameters = false
        var output = rawClass(owner, interfaces: [factory.name], access: 0x0031,
                              functions: [metroConstructor(owner, fields: [], access: 0x0002), initialize, create],
                              fields: [instance])
        output.outerName = factory.name
        output.innerName = "Impl"
        output.annotations = [JVMAnnotation(descriptor: JVMMetro.implementation)]
        return (output, instance)
    }

    private func metroConstructorTarget(_ owner: String, parameters: [JVMValueType]) -> JVMForeignMethod {
        JVMForeignMethod(owner: owner, name: "<init>", descriptor: "(" + parameters.map(\.descriptor).joined() + ")V",
                         parameters: parameters, result: .reference(owner, nullable: false), isStatic: false,
                         isInterface: false, isAbstract: false)
    }
}
