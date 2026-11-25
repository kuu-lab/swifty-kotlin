import Foundation

struct JVMMetroBindingKey: Hashable, CustomStringConvertible {
    let type: String
    let qualifiers: [String]

    init(_ type: String, qualifiers: [String] = []) {
        // JVM declaration-site wildcards do not change a Metro binding key.
        self.type = type.replacingOccurrences(of: "+L", with: "L").replacingOccurrences(of: "-L", with: "L")
        self.qualifiers = qualifiers.sorted()
    }

    var description: String { (qualifiers + [type]).joined(separator: " ") }
}

extension JVMAnnotation {
    func metroClass(_ name: String) -> String? {
        guard case let .classType(descriptor)? = values.first(where: { $0.0 == name })?.1,
              descriptor.hasPrefix("L"), descriptor.hasSuffix(";") else { return nil }
        return String(descriptor.dropFirst().dropLast())
    }

    func metroClasses(_ name: String) -> [String] {
        guard case let .array(elements)? = values.first(where: { $0.0 == name })?.1 else { return [] }
        return elements.compactMap {
            guard case let .classType(descriptor) = $0, descriptor.hasPrefix("L"), descriptor.hasSuffix(";") else { return nil }
            return String(descriptor.dropFirst().dropLast())
        }
    }
}

extension Array where Element == JVMAnnotation {
    func metro(_ descriptor: String) -> [JVMAnnotation] {
        flatMap { annotation -> [JVMAnnotation] in
            if annotation.descriptor == descriptor { return [annotation] }
            guard annotation.descriptor == String(descriptor.dropLast()) + "$Container;",
                  case let .array(elements)? = annotation.values.first(where: { $0.0 == "value" })?.1 else { return [] }
            return elements.compactMap {
                guard case let .annotation(value) = $0, value.descriptor == descriptor else { return nil }
                return value
            }
        }
    }
}

extension JVMForeignMethod {
    /// The classfile signature retains generic binding keys after JVM erasure.
    var metroTypes: (parameters: [String], result: String) {
        guard let genericSignature, genericSignature.first == "(",
              let close = genericSignature.firstIndex(of: ")") else {
            return (parameters.map(\.descriptor), result.descriptor)
        }
        var cursor = genericSignature.index(after: genericSignature.startIndex)
        var types: [String] = []
        while cursor < close {
            let start = cursor
            while cursor < close, genericSignature[cursor] == "[" { cursor = genericSignature.index(after: cursor) }
            guard cursor < close else { break }
            let kind = genericSignature[cursor]
            if kind == "L" || kind == "T" {
                var depth = 0
                while cursor < close {
                    let char = genericSignature[cursor]
                    cursor = genericSignature.index(after: cursor)
                    if char == "<" { depth += 1 }
                    if char == ">" { depth -= 1 }
                    if char == ";" && depth == 0 { break }
                }
            } else {
                cursor = genericSignature.index(after: cursor)
            }
            types.append(String(genericSignature[start..<cursor]))
        }
        guard types.count == parameters.count else { return (parameters.map(\.descriptor), result.descriptor) }
        let suffix = genericSignature[genericSignature.index(after: close)...]
        let returnSignature = suffix.prefix { $0 != "^" }
        return (types, returnSignature.isEmpty ? result.descriptor : String(returnSignature))
    }
}

struct JVMMetroBinding {
    enum Recipe {
        case input(JVMField)
        case constructor(JVMForeignMethod, [JVMMetroBindingKey], marker: Bool)
        case provider(JVMForeignMethod, receiver: String?, [JVMMetroBindingKey])
        case alias(JVMMetroBindingKey)
        case set([JVMMetroBindingKey])
        case graph
        case parent(JVMField, JVMForeignMethod)
        case extensionGraph(String)
    }

    let recipe: Recipe
    let type: JVMValueType
    let scope: String?
}

extension JVMProgramBuilder {
    func metroBindingKey(_ signature: String, annotations: [JVMAnnotation]) throws -> JVMMetroBindingKey {
        let qualifiers = try annotations.compactMap { annotation -> String? in
            let name = String(annotation.descriptor.dropFirst().dropLast())
            let imported = context.jvmImports?.metroClassInfo(name)?.annotations.contains { $0.descriptor == JVMMetro.qualifier } == true
            let local = classes.values.first { $0.name == name }.map {
                sema.symbols.annotations(for: $0.symbol).contains(where: { $0.annotationFQName == JVMMetro.sourcePackage + ".Qualifier" })
            } == true
            guard imported || local else { return nil }
            return try metroQualifierKey(annotation)
        }
        return JVMMetroBindingKey(signature, qualifiers: qualifiers)
    }

    private func metroQualifierKey(_ annotation: JVMAnnotation) throws -> String {
        func encode(_ value: JVMAnnotationValue) throws -> String {
            switch value {
            case let .constant(constant):
                switch constant {
                case let .string(text): return "s" + String(text.utf8.count) + ":" + text
                case let .int(number): return "I\(number)"
                case let .long(number): return "J\(number)"
                case let .float(number): return "F\(number.bitPattern)"
                case let .double(number): return "D\(number.bitPattern)"
                case let .boolean(flag): return flag ? "Z1" : "Z0"
                case .null: return "N"
                }
            case let .integral(value, tag): return "\(tag):\(value)"
            case let .classType(name): return name
            case let .enumEntry(owner, entry): return owner + "." + entry
            case let .array(elements): return "[" + (try elements.map(encode)).joined(separator: ",") + "]"
            case let .annotation(annotation): return try metroQualifierKey(annotation)
            }
        }
        let name = String(annotation.descriptor.dropFirst().dropLast())
        var elements: [String: JVMAnnotationValue] = [:]
        if let imported = context.jvmImports?.metroClassInfo(name) {
            for method in imported.methods { elements[method.name] = method.annotationDefault }
        }
        for (name, value) in annotation.values { elements[name] = value }
        return annotation.descriptor + (try elements.keys.sorted().map {
            $0 + "=" + (try encode(elements[$0]!))
        }).joined(separator: ",")
    }

    func metroDependencies(_ method: JVMForeignMethod) throws -> [JVMMetroBindingKey] {
        let parameters = method.metroTypes.parameters
        return try parameters.enumerated().map { index, signature in
            try metroBindingKey(signature, annotations: method.parameterAnnotations.indices.contains(index) ? method.parameterAnnotations[index] : [])
        }
    }

    func metroSourceMethod(_ method: JVMForeignMethod, symbol: SymbolID) throws -> JVMForeignMethod {
        var method = method
        method.annotations = try annotations(for: symbol, target: nil)
        if let signature = sema.symbols.functionSignature(for: symbol) {
            method.parameterAnnotations = try signature.valueParameterSymbols.map {
                try annotations(for: $0, target: nil) + annotations(for: $0, target: "param")
            }
            method.genericSignature = "(" + (try signature.parameterTypes.map {
                try signatureType($0, parameterPosition: true)
            }).joined() + ")" + (method.isConstructor ? "V" : try signatureType(signature.returnType))
        }
        return method
    }

    func metroConstructorBinding(_ name: String) throws -> JVMMetroBinding? {
        if let source = classes.values.first(where: { $0.name == name }) {
            let typeAnnotations = try annotations(for: source.symbol, target: nil)
            let constructors = try source.constructors.compactMap { symbol, _, _ in
                try methods[symbol].map { try metroSourceMethod($0, symbol: symbol) }
            }
            return try metroInjectableConstructor(constructors, annotations: typeAnnotations, owner: name)
        }
        guard let info = context.jvmImports?.metroClassInfo(name) else { return nil }
        let constructors = info.methods.filter { $0.isConstructor && !$0.isProtected }
        if !info.annotations.metro(JVMMetro.inject).isEmpty,
           let lowered = info.kotlinLoweredConstructors.first(where: { $0.entry.parameters.count == $0.source.parameters.count + 1 }),
           let source = info.metroAccessors.first(where: { $0.isConstructor && $0.descriptor == lowered.source.descriptor }) {
            let keys = try metroDependencies(source).enumerated().map { index, key in
                let type = metroValueType(lowered.source.parameters[index].sourceType)?.descriptor ?? key.type
                return JVMMetroBindingKey(type, qualifiers: key.qualifiers)
            }
            return JVMMetroBinding(recipe: .constructor(lowered.entry, keys, marker: true), type: lowered.entry.result,
                                   scope: info.annotations.metro(JVMMetro.singleIn).first?.metroClass("scope"))
        }
        return try metroInjectableConstructor(constructors, annotations: info.annotations, owner: name)
    }

    func metroValueType(_ kotlinName: String) -> JVMValueType? {
        guard !kotlinName.contains("<"), !kotlinName.hasSuffix("?"), !kotlinName.hasPrefix("kotlin."),
              let imports = context.jvmImports else { return nil }
        let segments = kotlinName.split(separator: ".").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
        for boundary in segments.indices.reversed() {
            let name = (segments.prefix(boundary) + [segments.dropFirst(boundary).joined(separator: "$")]).joined(separator: "/")
            let type = JVMValueType.reference(name, nullable: false)
            if imports.importedValueCarrier(for: type) != nil { return type }
        }
        return nil
    }

    private func metroInjectableConstructor(
        _ methods: [JVMForeignMethod], annotations: [JVMAnnotation], owner: String
    ) throws -> JVMMetroBinding? {
        let explicit = methods.filter { !$0.annotations.metro(JVMMetro.inject).isEmpty }
        let candidates = explicit.isEmpty && !annotations.metro(JVMMetro.inject).isEmpty ? methods : explicit
        guard !candidates.isEmpty else { return nil }
        guard candidates.count == 1, let method = candidates.first else {
            throw JVMFrontendError(message: "Metro class \(owner) has multiple injectable constructors.")
        }
        let scope = (method.annotations + annotations).metro(JVMMetro.singleIn).first?.metroClass("scope")
        return JVMMetroBinding(recipe: .constructor(method, try metroDependencies(method), marker: false), type: method.result, scope: scope)
    }
}
