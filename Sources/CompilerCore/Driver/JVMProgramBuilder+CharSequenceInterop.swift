import Foundation

extension JVMProgramBuilder {
    func charSequenceInteropMethods(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        var visited: Set<SymbolID> = []
        func inheritsCharSequence(_ symbol: SymbolID) -> Bool {
            guard visited.insert(symbol).inserted else { return false }
            for parent in sema.symbols.directSupertypes(for: symbol) {
                if (try? className(parent)) == "kotlin/CharSequence" || inheritsCharSequence(parent) {
                    return true
                }
            }
            return false
        }
        guard inheritsCharSequence(plan.symbol) else { return [] }

        var signatures = Set(existing.map { $0.reference.name + $0.reference.descriptor })
        var functions: [JVMFunction] = []
        func forward(_ target: JVMForeignMethod, as name: String) throws -> JVMFunction {
            let builder = try nominalBuilder(plan, name: name, parameters: target.parameters, result: target.result)
            let arguments = Array(builder.locals.dropFirst().prefix(target.parameters.count))
            let result = target.result == .unit ? nil : try builder.value(target.result)
            builder.instructions.append(.foreignCall(target, receiver: builder.thisValue!, arguments: arguments, result: result))
            builder.instructions.append(.returnValue(result))
            var function = builder.finish()
            function.access = 0x1001
            function.isSynthetic = true
            function.isMetadataHidden = true
            return function
        }

        if let target = plan.methods.map(\.1).first(where: {
            $0.name == "get" && $0.parameters == [.int] && $0.result == .char
        }), !(plan.isInterface && target.isAbstract),
           signatures.insert("charAt" + target.descriptor).inserted {
            functions.append(try forward(target, as: "charAt"))
        }

        if let target = plan.properties.map({ $0.2 }).first(where: {
            $0.name == "length" && $0.getter.parameters.isEmpty && $0.getter.result == .int
        })?.getter, !(plan.isInterface && target.isAbstract),
           signatures.insert("length" + target.descriptor).inserted {
            functions.append(try forward(target, as: "length"))
        }

        return functions
    }
}
