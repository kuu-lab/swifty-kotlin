import Foundation

/// Split a sequence of JVMS field signatures without splitting nested arguments.
private func valueSignatureTypes(_ signature: String) -> [String] {
    let characters = Array(signature)
    var types: [String] = [], index = 0
    while index < characters.count {
        let start = index
        if characters[index] == "*" { types.append("*"); index += 1; continue }
        while index < characters.count && ["[", "+", "-"].contains(characters[index]) { index += 1 }
        guard index < characters.count else { return [] }
        if characters[index] == "L" || characters[index] == "T" {
            var depth = 0
            repeat {
                let c = characters[index]; index += 1
                if c == "<" { depth += 1 }; if c == ">" { depth -= 1 }
                if c == ";" && depth == 0 { break }
            } while index < characters.count
        } else { index += 1 }
        types.append(String(characters[start..<index]))
    }
    return types
}

/// Preserve source type variables and underlying type arguments in ABI adapters.
func adaptedValueSignature(_ function: JVMFunction, reference: JVMFunctionReference, receiverOffset: Int,
                           values: [String: (underlying: String, input: String, parameters: [String])]) -> String? {
    guard let signature = function.genericSignature, let open = signature.firstIndex(of: "("), let close = signature.firstIndex(of: ")") else { return nil }
    let parameters = valueSignatureTypes(String(signature[signature.index(after: open)..<close]))
    guard parameters.count == function.reference.parameters.count,
          reference.parameters.count == parameters.count + receiverOffset else { return nil }
    func adapted(_ source: String, from: JVMValueType, to: JVMValueType, input: Bool = false) -> String {
        guard from.descriptor != to.descriptor else { return source }
        guard let name = from.referenceName, let info = values[name], !info.underlying.hasPrefix("T"), !info.underlying.hasPrefix("[") else { return to.descriptor }
        var result = input ? info.input : info.underlying
        if let start = source.firstIndex(of: "<"), let end = source.lastIndex(of: ">") {
            let arguments = valueSignatureTypes(String(source[source.index(after: start)..<end]))
            // Replace complete type-variable tokens simultaneously, including nested uses.
            var substitutions: [String: String] = [:]
            for (parameter, argument) in zip(info.parameters, arguments) {
                let unprojected = argument.first == "+" || argument.first == "-" ? String(argument.dropFirst()) : argument
                substitutions["T" + parameter + ";"] = unprojected == "*" ? "Ljava/lang/Object;" : unprojected
            }
            func substitute(_ field: String) -> String {
                if field.first == "T" { return substitutions[field] ?? field }
                if let first = field.first, ["[", "+", "-"].contains(first) { return String(first) + substitute(String(field.dropFirst())) }
                guard let open = field.firstIndex(of: "<"), let close = field.lastIndex(of: ">") else { return field }
                let arguments = valueSignatureTypes(String(field[field.index(after: open)..<close]))
                return String(field[...open]) + arguments.map(substitute).joined() + String(field[close...])
            }
            result = substitute(result)
        }
        // Kotlin suppresses declaration-site covariance for final concrete arguments.
        for name in ["String", "Integer", "Long", "Float", "Double", "Boolean", "Byte", "Short", "Character"] {
            result = result.replacingOccurrences(of: "+Ljava/lang/" + name + ";", with: "Ljava/lang/" + name + ";")
        }
        return result
    }
    var physical = Array(reference.parameters.prefix(receiverOffset)).map(\.descriptor)
    if receiverOffset == 1, let owner = reference.owner, let info = values[owner], !info.underlying.hasPrefix("T"), !info.underlying.hasPrefix("[") {
        physical[0] = info.input
    }
    for (i, parameter) in parameters.enumerated() {
        physical.append(adapted(parameter, from: function.reference.parameters[i], to: reference.parameters[i + receiverOffset], input: true))
    }
    let result = adapted(String(signature[signature.index(after: close)...]), from: function.reference.result, to: reference.result)
    return String(signature[..<open]) + "(" + physical.joined() + ")" + result
}
