extension JVMProgramBuilder {
    func isJvmStatic(_ symbol: SymbolID) -> Bool {
        sema.symbols.annotations(for: symbol).contains { annotation in
            annotation.annotationFQName == "kotlin.jvm.JvmStatic" || annotation.annotationFQName == "JvmStatic"
        }
    }

    func jvmStaticMethods(_ plan: JVMClassPlan) throws -> [JVMFunction] {
        guard let companion = classes.values.first(where: { $0.companionOwner == plan.symbol }) else { return [] }
        return try companion.methods.compactMap { declaration, target in
            guard let symbol = companion.methodSymbols[target.name + target.descriptor], isJvmStatic(symbol) else { return nil }
            let builder = try nominalBuilder(plan, name: target.name, parameters: target.parameters,
                                             result: target.result, staticBody: true)
            let parameters = Array(builder.locals)
            let receiver = try builder.value(.reference(companion.name, nullable: false))
            builder.instructions.append(.getStatic(singletonField(companion), receiver))
            let returned = target.result == .unit ? nil : try builder.value(target.result)
            builder.instructions.append(.foreignCall(target, receiver: receiver, arguments: parameters, result: returned))
            builder.instructions.append(.returnValue(returned))
            var result = builder.finish()
            result.access = access(declaration.modifiers, final: !plan.isInterface) | 0x0008
            result.isSynthetic = false
            result.isMetadataHidden = true
            result.checksParameters = false
            return result
        }
    }
}
