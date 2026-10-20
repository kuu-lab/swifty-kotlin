import Foundation

extension JVMProgramBuilder {
    /// Record runtime calls separately from declaration-only and inline APIs.
    /// A declaration in the resource tree is never evidence of a JAR body.
    func stdlibRequirements() -> [JVMStdlibRequirement] {
        var rows: [String: JVMStdlibRequirement] = [:]
        func add(_ owner: String, _ name: String, _ descriptor: String, source: String) {
            guard owner.hasPrefix("kotlin/") else { return }
            let row = JVMStdlibRequirement(owner: owner, name: name, descriptor: descriptor, source: source)
            rows[owner + "." + name + descriptor] = row
        }
        for (symbol, entry) in textLibraryMethods {
            let method = entry.method.isSuspend ? entry.method.suspendABI : entry.method
            if method.name == "<init>" && classes.values.contains(where: { $0.name == method.owner && $0.isAnnotation }) { continue }
            add(method.owner, method.name, method.descriptor, source: sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve).joined(separator: ".") ?? "")
        }
        // Migrated contracts are omitted during the runtime build. Keep their
        // source-owned public signatures in the inventory after that move.
        for (symbol, declaration) in sourceDeclarations where !declaration.modifiers.contains(.private) {
            guard let reference = references[symbol], let owner = reference.owner,
                  ["kotlin/text/", "kotlin/collections/", "kotlin/sequences/"].contains(where: owner.hasPrefix) else { continue }
            add(owner, reference.name, reference.descriptor, source: sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve).joined(separator: ".") ?? "")
        }
        for operation in JVMTextOperation.operations {
            let parameters = [operation.receiverType] + operation.parameters.map { $0.variadic ? JVMValueType.reference("[" + $0.type.descriptor, nullable: false) : $0.type }
            let name = operation.name == "isNotBlank" ? "isBlank" : operation.method ?? operation.name
            // These operations lower directly to JVM/JDK primitives at call sites.
            if ["isEmpty", "isNotEmpty", "uppercase", "lowercase", "reversed"].contains(operation.name) { continue }
            add(operation.owner, name, "(" + parameters.map(\.descriptor).joined() + ")" + operation.result.descriptor, source: operation.receiver + "." + operation.name)
        }
        return rows.values.sorted { ($0.owner, $0.name, $0.descriptor) < ($1.owner, $1.name, $1.descriptor) }
    }
}
