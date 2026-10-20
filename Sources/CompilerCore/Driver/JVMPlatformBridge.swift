import Foundation

/// Platform edges are ABI data. Algorithms belong in the calling Kotlin source.
struct JVMPlatformOperation: Decodable {
    let symbol: String
    let owner: String
    let name: String
    let descriptor: String
    let kind: String
}

extension JVMStdlibCatalog {
    static func platformOperations() throws -> [String: JVMPlatformOperation] {
        let operations = try JSONDecoder().decode([JVMPlatformOperation].self, from: read("platform-operations.json"))
        var result: [String: JVMPlatformOperation] = [:]
        for operation in operations {
            guard operation.symbol.hasPrefix("__jvm"), JVMProgramBuilder.isIdentifier(operation.symbol),
                  operation.owner.hasPrefix("java/"), ["static", "virtual", "interface", "constructor", "getStatic"].contains(operation.kind),
                  result.updateValue(operation, forKey: operation.symbol) == nil else { throw JVMFrontendError(message: "Invalid or duplicate JVM platform operation.") }
            _ = try JVMDescriptor.parse(operation.kind == "getStatic" ? "()" + operation.descriptor : operation.descriptor)
        }
        return result
    }
}

extension JVMFunctionBuilder {
    func platformOperation(_ operation: JVMPlatformOperation, arguments: [JVMValue], result: JVMValueType) throws -> JVMValue? {
        if operation.kind == "constructor" {
            let (parameters, _) = try JVMDescriptor.parse(operation.descriptor)
            guard arguments.count == parameters.count else { throw fail("Invalid JVM platform constructor arguments.") }
            let values = try zip(arguments, parameters).map { try convert($0.0, to: $0.1) }
            return try convert(constructJDK(operation.owner, parameters: parameters, arguments: values), to: result)
        }
        if operation.kind == "getStatic" {
            guard arguments.isEmpty else { throw fail("JVM static field access takes no arguments.") }
            let (_, type) = try JVMDescriptor.parse("()" + operation.descriptor)
            let field = JVMField(owner: operation.owner, name: operation.name, type: type, access: 0x19)
            let value = try value(type); instructions.append(.getStatic(field, value)); return try convert(value, to: result)
        }
        let (parameters, returns) = try JVMDescriptor.parse(operation.descriptor)
        let instance = operation.kind != "static"
        guard arguments.count == parameters.count + (instance ? 1 : 0) else { throw fail("Invalid JVM platform method arguments.") }
        let receiver = try instance ? convert(arguments[0], to: .reference(operation.owner, nullable: false)) : nil
        let values = Array(arguments.dropFirst(instance ? 1 : 0))
        return try jdkCall(operation.owner, operation.name, parameters, returns, receiver: receiver, arguments: values, interface: operation.kind == "interface", resolved: result)
    }
}
