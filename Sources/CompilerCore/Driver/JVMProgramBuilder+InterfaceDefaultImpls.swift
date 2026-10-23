import Foundation

enum JVMForwardReceiver {
    case none
    case instance
    case parameter(Int)
}

func jvmMemberKey(_ method: JVMForeignMethod) -> String {
    method.name + method.descriptor
}

extension JVMProgramBuilder {
    func sourceInterfaceParents(of symbol: SymbolID) -> [JVMClassPlan] {
        sema.symbols.directSupertypes(for: symbol).compactMap { parent in
            guard let plan = classes[parent], plan.isInterface else { return nil }
            return plan
        }
    }

    func sourceClassParents(of symbol: SymbolID) -> [JVMClassPlan] {
        sema.symbols.directSupertypes(for: symbol).compactMap { parent in
            guard let plan = classes[parent], !plan.isInterface else { return nil }
            return plan
        }
    }

    func declaredInterfaceMethods(_ plan: JVMClassPlan) -> [JVMForeignMethod] {
        plan.methods.map(\.1) + plan.properties.flatMap { _, _, property in
            [property.getter] + (property.setter.map { [$0] } ?? [])
        }
    }

    func effectiveInterfaceMethods(_ plan: JVMClassPlan, visited: Set<SymbolID> = []) -> [String: JVMForeignMethod] {
        guard plan.isInterface, !visited.contains(plan.symbol) else { return [:] }
        let visited = visited.union([plan.symbol])
        var methods: [String: JVMForeignMethod] = [:]
        for method in declaredInterfaceMethods(plan) {
            methods[jvmMemberKey(method)] = method
        }
        for parent in sourceInterfaceParents(of: plan.symbol) {
            for (key, method) in effectiveInterfaceMethods(parent, visited: visited).sorted(by: { $0.key < $1.key }) where methods[key] == nil {
                methods[key] = method
            }
        }
        return methods
    }

    func forwarder(
        owner: String,
        name: String,
        parameters: [JVMValueType],
        result: JVMValueType,
        access: UInt16,
        target: JVMForeignMethod,
        receiver: JVMForwardReceiver,
        argumentOffset: Int,
        ownerIsInterface: Bool = false
    ) -> JVMFunction {
        let hasInstance = access & 8 == 0
        var locals: [JVMValue] = []
        var slot = 0
        if hasInstance {
            let instance = JVMValue(slot: slot, type: .reference(owner, nullable: false))
            locals.append(instance)
            slot += instance.type.width
        }
        for type in parameters {
            locals.append(JVMValue(slot: slot, type: type))
            slot += type.width
        }
        let explicitParameters = Array(locals.dropFirst(hasInstance ? 1 : 0))
        let targetReceiver: JVMValue?
        switch receiver {
        case .none: targetReceiver = nil
        case .instance: targetReceiver = locals.first
        case let .parameter(index): targetReceiver = explicitParameters[index]
        }
        let returned: JVMValue?
        if result == .unit {
            returned = nil
        } else {
            let value = JVMValue(slot: slot, type: result)
            locals.append(value)
            returned = value
        }
        var function = rawFunction(
            owner,
            name: name,
            parameters: parameters,
            result: result,
            access: access,
            locals: locals,
            instructions: [
                .foreignCall(target, receiver: targetReceiver, arguments: Array(explicitParameters.dropFirst(argumentOffset)), result: returned),
                .returnValue(returned),
            ]
        )
        function.reference = JVMFunctionReference(name: name, parameters: parameters, result: result, owner: owner, ownerIsInterface: ownerIsInterface, isSuspend: target.isSuspend)
        function.isSuspend = target.isSuspend
        function.isMetadataHidden = true
        return function
    }

    func interfaceDefaultBridgeName(_ method: JVMForeignMethod) -> String {
        "access$" + method.name + "$jd"
    }

    func interfaceDefaultDispatchMethod(_ method: JVMForeignMethod, owner: String, special: Bool) -> JVMForeignMethod {
        var target = JVMForeignMethod(
            owner: owner,
            name: method.name,
            descriptor: method.descriptor,
            parameters: method.parameters,
            result: method.result,
            isStatic: false,
            isInterface: true,
            isAbstract: false,
            isSpecial: special
        )
        target.isSuspend = method.isSuspend
        return target
    }

    func interfaceDefaultAccessBridges(_ plan: JVMClassPlan, methods: [JVMForeignMethod]) -> [JVMFunction] {
        let interfaceType = JVMValueType.reference(plan.name, nullable: false)
        return methods.map { method in
            var target = interfaceDefaultDispatchMethod(method, owner: plan.name, special: true)
            target.isSuspend = method.isSuspend
            return forwarder(
                owner: plan.name,
                name: interfaceDefaultBridgeName(method),
                parameters: [interfaceType] + method.parameters,
                result: method.result,
                access: 0x1009,
                target: target,
                receiver: .parameter(0),
                argumentOffset: 1,
                ownerIsInterface: true
            )
        }
    }

    func defaultImplsClass(for plan: JVMClassPlan, methods: [JVMForeignMethod]) -> JVMClass? {
        guard !methods.isEmpty else { return nil }
        let name = plan.name + "$DefaultImpls"
        let interfaceType = JVMValueType.reference(plan.name, nullable: false)
        let functions = methods.map { method -> JVMFunction in
            let parameters = [interfaceType] + method.parameters
            let accessName = interfaceDefaultBridgeName(method)
            let accessMethod = JVMForeignMethod(
                owner: plan.name,
                name: accessName,
                descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + method.result.descriptor,
                parameters: parameters,
                result: method.result,
                isStatic: true,
                isInterface: true,
                isAbstract: false,
                isSuspend: method.isSuspend
            )
            var function = forwarder(
                owner: name,
                name: method.name,
                parameters: parameters,
                result: method.result,
                access: 0x0009,
                target: accessMethod,
                receiver: .none,
                argumentOffset: 0
            )
            function.isSynthetic = false
            return function
        }
        var helper = JVMClass(name: name, superclass: "java/lang/Object", interfaces: [], access: 0x0031, functions: functions, properties: [])
        helper.outerName = plan.name
        helper.innerName = "DefaultImpls"
        helper.emitMetadata = false
        if let site = sema.symbols.symbol(plan.symbol)?.declSite {
            helper.sourceFileName = URL(fileURLWithPath: context.sourceManager.path(of: site.start.file)).lastPathComponent
        }
        return helper
    }

    func interfaceIsSubtype(_ child: JVMClassPlan, of parent: JVMClassPlan, visited: Set<SymbolID> = []) -> Bool {
        if child.symbol == parent.symbol { return true }
        guard !visited.contains(child.symbol) else { return false }
        let visited = visited.union([child.symbol])
        return sourceInterfaceParents(of: child.symbol).contains { candidate in
            candidate.symbol == parent.symbol || interfaceIsSubtype(candidate, of: parent, visited: visited)
        }
    }

    func inheritedClassMethodSignatures(_ plan: JVMClassPlan, includeInterfaceDefaults: Bool = true, visited: Set<SymbolID> = []) -> Set<String> {
        guard !visited.contains(plan.symbol) else { return [] }
        let visited = visited.union([plan.symbol])
        var signatures = Set(plan.methods.filter { !$0.1.isSpecial }.map { jvmMemberKey($0.1) })
        for (_, _, property) in plan.properties {
            if !property.getter.isSpecial { signatures.insert(jvmMemberKey(property.getter)) }
            if let setter = property.setter, !setter.isSpecial { signatures.insert(jvmMemberKey(setter)) }
        }
        signatures.formUnion(plan.delegatedMethods.map { jvmMemberKey($0.1) })
        for (property, _, _) in plan.delegatedProperties {
            signatures.insert(jvmMemberKey(property.getter))
            if let setter = property.setter { signatures.insert(jvmMemberKey(setter)) }
        }
        if includeInterfaceDefaults {
            for parent in sourceInterfaceParents(of: plan.symbol) {
                signatures.formUnion(effectiveInterfaceMethods(parent).values.filter { !$0.isAbstract }.map(jvmMemberKey))
            }
        }
        for parent in sourceClassParents(of: plan.symbol) {
            signatures.formUnion(inheritedClassMethodSignatures(parent, visited: visited))
        }
        for parent in sema.symbols.directSupertypes(for: plan.symbol) where classes[parent] == nil && sema.symbols.symbol(parent)?.kind != .interface {
            guard let sourceName = try? className(parent),
                  let imported = context.jvmImports?.classes[JVMClasspathIndex.builtinName(sourceName) ?? sourceName] else { continue }
            signatures.formUnion(imported.methods.filter { !$0.isStatic && !$0.isConstructor && !$0.isSpecial }.map(jvmMemberKey))
        }
        return signatures
    }

    func interfaceDefaultForwarders(_ plan: JVMClassPlan, existing: [JVMFunction]) -> [JVMFunction] {
        guard !plan.isInterface else { return [] }
        let directInterfaces = sourceInterfaceParents(of: plan.symbol)
        let mostSpecific = directInterfaces.filter { candidate in
            !directInterfaces.contains { other in
                other.symbol != candidate.symbol && interfaceIsSubtype(other, of: candidate)
            }
        }
        let inheritedFromClass = inheritedClassMethodSignatures(plan, includeInterfaceDefaults: false)
        let blocked = inheritedFromClass.union(existing.filter { !$0.isPrivate }.map { $0.reference.name + $0.reference.descriptor })
        var selected: [String: (method: JVMForeignMethod, interface: JVMClassPlan)] = [:]
        for interface in mostSpecific {
            for method in effectiveInterfaceMethods(interface).values.sorted(by: { jvmMemberKey($0) < jvmMemberKey($1) }) where !method.isAbstract {
                let key = jvmMemberKey(method)
                guard let prior = selected[key] else {
                    selected[key] = (method, interface)
                    continue
                }
                if let candidateOwner = classes.values.first(where: { $0.name == method.owner }),
                   let priorOwner = classes.values.first(where: { $0.name == prior.method.owner }),
                   interfaceIsSubtype(candidateOwner, of: priorOwner) {
                    selected[key] = (method, interface)
                }
            }
        }
        return selected.keys.sorted().compactMap { key in
            guard !blocked.contains(key), let candidate = selected[key] else { return nil }
            let target = interfaceDefaultDispatchMethod(candidate.method, owner: candidate.interface.name, special: true)
            var function = forwarder(
                owner: plan.name,
                name: candidate.method.name,
                parameters: candidate.method.parameters,
                result: candidate.method.result,
                access: 0x0041,
                target: target,
                receiver: .instance,
                argumentOffset: 0
            )
            function.isSynthetic = false
            return function
        }
    }
}
