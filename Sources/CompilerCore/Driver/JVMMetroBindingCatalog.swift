extension JVMProgramBuilder {
    func metroBindings(
        scope: String?, additionalScopes: [String], excluded: Set<String>
    ) throws -> [JVMMetroBindingKey: [JVMMetroBinding]] {
        let scopes = Set([scope].compactMap { $0 } + additionalScopes)
        guard !scopes.isEmpty else { return [:] }
        let local = try classes.values.sorted(by: { $0.name < $1.name }).compactMap { plan -> JVMClassInfo? in
            guard sema.symbols.annotations(for: plan.symbol).contains(where: {
                $0.annotationFQName.hasPrefix(JVMMetro.sourcePackage + ".")
            }) else { return nil }
            let annotations = try annotations(for: plan.symbol, target: nil)
            let methods = try plan.methods.compactMap { _, method in
                try plan.methodSymbols[jvmMemberKey(method)].map { try metroSourceMethod(method, symbol: $0) }
            }
            return JVMClassInfo(name: plan.name, flags: plan.isInterface ? 0x0201 : 1,
                                superclass: nil, interfaces: plan.interfaces, methods: methods, annotations: annotations)
        }
        let localNames = Set(local.map(\.name))
        let imported = context.jvmImports?.metroAnnotatedClasses.filter { !localNames.contains($0.name) } ?? []
        let all = local + imported
        let contributionKinds = [JVMMetro.contributesTo, JVMMetro.contributesBinding, JVMMetro.contributesIntoSet]
        func contributions(_ info: JVMClassInfo) -> [JVMAnnotation] {
            contributionKinds.flatMap { info.annotations.metro($0) }.filter { annotation in
                annotation.metroClass("scope").map(scopes.contains) == true
            }
        }
        let replaced = excluded.union(all.flatMap { info in
            contributions(info).flatMap { $0.metroClasses("replaces") }
        })
        var bindings: [JVMMetroBindingKey: [JVMMetroBinding]] = [:]
        for info in all where !replaced.contains(info.name) {
            let applicable = contributions(info)
            if applicable.contains(where: { $0.descriptor == JVMMetro.contributesTo }) {
                try addMetroProviders(from: info, to: &bindings)
            }
            let aliases = applicable.filter { $0.descriptor == JVMMetro.contributesBinding }
            let sets = applicable.filter { $0.descriptor == JVMMetro.contributesIntoSet }
            guard !aliases.isEmpty || !sets.isEmpty else { continue }
            let implementation = JVMMetroBindingKey("L" + info.name + ";")
            if localNames.contains(info.name) {
                guard aliases.count + sets.count == 1, info.interfaces.count == 1, let interface = info.interfaces.first else {
                    throw JVMFrontendError(message: "Metro contribution \(info.name) requires an explicit supported bound type.")
                }
                let key = try metroBindingKey("L" + interface + ";", annotations: info.annotations)
                if sets.isEmpty {
                    bindings[key, default: []].append(JVMMetroBinding(recipe: .alias(implementation), type: .reference(interface, nullable: false), scope: nil))
                } else {
                    addMetroSetElement(implementation, element: key, bindings: &bindings)
                }
            } else {
                let mirrors = all.filter { contribution in
                    contribution.annotations.metro(JVMMetro.origin).first?.metroClass("value") == info.name
                        && contribution.annotations.metro(JVMMetro.contribution).contains {
                            $0.metroClass("scope").map(scopes.contains) == true
                        }
                }
                for contribution in mirrors {
                    let mirrorName = contribution.name + "$BindsMirror"
                    guard let mirror = context.jvmImports?.metroClassInfo(mirrorName) else { continue }
                    for method in mirror.methods where method.annotations.metro(JVMMetro.binds).count == 1 && method.parameters.count == 1 {
                        let key = try metroBindingKey(method.metroTypes.result, annotations: method.annotations)
                        let input = try metroDependencies(method)[0]
                        if method.annotations.metro(JVMMetro.intoSet).isEmpty {
                            bindings[key, default: []].append(JVMMetroBinding(recipe: .alias(input), type: method.result, scope: nil))
                        } else {
                            addMetroSetElement(input, element: key, bindings: &bindings)
                        }
                    }
                }
            }
        }
        return bindings
    }

    private func addMetroSetElement(
        _ input: JVMMetroBindingKey, element: JVMMetroBindingKey, bindings: inout [JVMMetroBindingKey: [JVMMetroBinding]]
    ) {
        let key = JVMMetroBindingKey("Ljava/util/Set<" + element.type + ">;", qualifiers: element.qualifiers)
        var candidates = bindings[key] ?? []
        var elements: [JVMMetroBindingKey] = []
        if let index = candidates.firstIndex(where: { if case .set = $0.recipe { true } else { false } }),
           case let .set(previous) = candidates.remove(at: index).recipe {
            elements = previous
        }
        if !elements.contains(input) { elements.append(input) }
        candidates.append(JVMMetroBinding(recipe: .set(elements), type: .reference("java/util/Set", nullable: false), scope: nil))
        bindings[key] = candidates
    }

    private func addMetroProviders(from info: JVMClassInfo, to bindings: inout [JVMMetroBindingKey: [JVMMetroBinding]]) throws {
        for method in info.methods + info.metroAccessors where method.annotations.metro(JVMMetro.provides).count == 1 {
            guard !method.isConstructor, !method.isAbstract, !method.isSuspend, method.result != .unit else { continue }
            let key = try metroBindingKey(method.metroTypes.result, annotations: method.annotations)
            let scope = method.annotations.metro(JVMMetro.singleIn).first?.metroClass("scope")
            let receiver = method.isStatic ? nil : info.name
            var target = method
            if info.metroAccessors.contains(where: { $0.name == method.name && $0.descriptor == method.descriptor }) {
                let receiverDescriptor = method.isStatic ? "" : "L" + info.name + ";"
                let expected = "(" + receiverDescriptor + method.descriptor.dropFirst()
                guard let accessor = info.metroAccessors.first(where: {
                    $0.isStatic && $0.descriptor == expected
                        && ($0.name == "access$" + method.name || $0.name == "access$" + method.name + "$jd")
                }) else {
                    throw JVMFrontendError(message: "Metro provider \(method.owner).\(method.name) lacks an accessible JVM entry point.")
                }
                target = accessor
            }
            bindings[key, default: []].append(JVMMetroBinding(
                recipe: .provider(target, receiver: receiver, try metroDependencies(method)),
                type: method.result, scope: scope
            ))
        }
    }
}
