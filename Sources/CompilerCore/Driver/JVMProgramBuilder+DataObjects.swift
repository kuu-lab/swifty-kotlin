import Foundation

extension JVMProgramBuilder {
    func dataObjectMethods(_ plan: JVMClassPlan, existing: [JVMFunction]) throws -> [JVMFunction] {
        var functions: [JVMFunction] = []
        func inheritsFinal(_ name: String, _ symbol: SymbolID, _ seen: Set<SymbolID>) -> Bool {
            guard !seen.contains(symbol) else { return false }
            let next = seen.union([symbol])
            if let parent = classes[symbol], let member = parent.methods.first(where: { $0.1.name == name }) { return memberFinal(member.0.modifiers) }
            if let binary = try? className(symbol), let member = context.jvmImports?.classes[binary]?.methods.first(where: { $0.name == name }) { return member.isFinal }
            return sema.symbols.directSupertypes(for: symbol).contains { inheritsFinal(name, $0, next) }
        }
        for name in ["equals", "hashCode", "toString"] {
            let params: [JVMValueType] = name == "equals" ? [.reference("java/lang/Object", nullable: true)] : []
            let result: JVMValueType = name == "equals" ? .boolean : (name == "hashCode" ? .int : .string)
            guard !existing.contains(where: { $0.reference.name == name && $0.reference.parameters == params }) else { continue }
            if sema.symbols.directSupertypes(for: plan.symbol).contains(where: { inheritsFinal(name, $0, []) }) { continue }
            let b = try nominalBuilder(plan, name: name, parameters: params, result: result)
            let returned: JVMValue
            if name == "equals" {
                returned = try b.value(.boolean); b.instructions.append(.instanceOf(b.locals[1], plan.name, returned))
            } else if name == "hashCode" {
                let sourceName = sema.symbols.symbol(plan.symbol)!.fqName.map(context.interner.resolve).joined(separator: ".")
                let hash = sourceName.utf16.reduce(Int32(0)) { ($0 &* 31) &+ Int32($1) }
                returned = try b.constant(.int(hash), .int)
            } else { returned = try b.constant(.string(context.interner.resolve(plan.object!.name)), .string) }
            b.instructions.append(.returnValue(returned))
            var function = b.finish(); function.access = 1; function.isPrivate = false
            functions.append(function)
        }
        return functions
    }
}
