import Foundation

extension JVMClasspathIndex {
    func annotationDeclaration(
        _ info: JVMClassInfo, name: String, visibility: String = "", indentation: String = ""
    ) -> String {
        let retention = info.annotations.first { $0.descriptor == "Ljava/lang/annotation/Retention;" }?.values.first?.1
        let kotlinRetention: String
        switch retention {
        case .enumEntry(_, "RUNTIME"): kotlinRetention = "RUNTIME"
        case .enumEntry(_, "SOURCE"): kotlinRetention = "SOURCE"
        default: kotlinRetention = "BINARY"
        }
        let javaTargets = info.annotations.first { $0.descriptor == "Ljava/lang/annotation/Target;" }?.values.first?.1
        let mapping = [
            "TYPE": ["CLASS", "ANNOTATION_CLASS"], "ANNOTATION_TYPE": ["ANNOTATION_CLASS"],
            "CONSTRUCTOR": ["CONSTRUCTOR"], "FIELD": ["FIELD"],
            "METHOD": ["FUNCTION", "PROPERTY_GETTER", "PROPERTY_SETTER"],
            "PARAMETER": ["VALUE_PARAMETER"], "LOCAL_VARIABLE": ["LOCAL_VARIABLE"],
            "TYPE_PARAMETER": ["TYPE_PARAMETER"], "TYPE_USE": ["TYPE"],
        ]
        let targets: Set<String>
        if case let .array(values) = javaTargets {
            targets = Set(values.flatMap { value -> [String] in
                guard case let .enumEntry(_, target) = value else { return [] }
                return mapping[target] ?? []
            })
        } else {
            targets = Set(mapping.filter { !["TYPE_PARAMETER", "TYPE_USE"].contains($0.key) }.values.flatMap { $0 })
        }
        let targetArguments = targets.sorted().map { "kotlin.annotation.AnnotationTarget." + $0 }.joined(separator: ", ")
        let members = info.methods.filter { method in
            method.owner == info.name && !method.isConstructor && !method.isStatic && method.parameters.isEmpty
                && JVMProgramBuilder.isIdentifier(method.name)
        }.sorted { left, right in
            if left.name == "value" || right.name == "value" { return left.name == "value" && right.name != "value" }
            return left.name < right.name
        }
        let parameters = members.map { method -> String in
            let type = annotationSourceType(method.result)
            let defaultValue = method.annotationDefault.map { " = " + annotationSourceValue($0, type: method.result) } ?? ""
            return "val `\(method.name)`: \(type)\(defaultValue)"
        }
        return indentation + "@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.\(kotlinRetention))\n"
            + indentation + "@kotlin.annotation.Target(\(targetArguments))\n"
            + indentation + visibility + "annotation class `\(name)`(\(parameters.joined(separator: ", ")))\n"
    }

    private func annotationSourceType(_ type: JVMValueType) -> String {
        switch type.referenceName {
        case "java/lang/Class": return "kotlin.reflect.KClass<*>"
        case "[Ljava/lang/Class;": return "kotlin.Array<kotlin.reflect.KClass<*>>"
        default: return kotlinType(type)
        }
    }

    private func annotationSourceValue(_ value: JVMAnnotationValue, type: JVMValueType? = nil) -> String {
        switch value {
        case .constant(.int(let number)), .integral(let number, 66), .integral(let number, 83):
            return String(number)
        case .integral(let number, 67):
            return String(format: "'\\u%04X'", UInt32(truncatingIfNeeded: number))
        case .constant(.long(let number)):
            return number == Int64.min ? "kotlin.Long.MIN_VALUE" : "\(number)L"
        case .constant(.float(let number)):
            return number.isNaN ? "kotlin.Float.NaN" : number.isInfinite
                ? "kotlin.Float.\(number.sign == .minus ? "NEGATIVE" : "POSITIVE")_INFINITY" : "\(number)f"
        case .constant(.double(let number)):
            return number.isNaN ? "kotlin.Double.NaN" : number.isInfinite
                ? "kotlin.Double.\(number.sign == .minus ? "NEGATIVE" : "POSITIVE")_INFINITY" : String(number)
        case .constant(.boolean(let boolean)):
            return String(boolean)
        case .constant(.string(let string)):
            return Self.kotlinStringLiteral(string)
        case .classType(let descriptor):
            if let type = try? JVMDescriptor.parse("()" + descriptor).1, type != .unit {
                return kotlinType(type).components(separatedBy: "<")[0] + "::class"
            }
            return "kotlin.Unit::class"
        case let .enumEntry(descriptor, name):
            return Self.dottedTypeName(String(descriptor.dropFirst().dropLast())) + ".`\(name)`"
        case .array(let values):
            let arrayType = type.map(kotlinType) ?? "kotlin.Array"
            let factory = arrayType.hasPrefix("kotlin.Array") ? "arrayOf" : arrayType.split(separator: ".").last.map {
                $0.prefix(1).lowercased() + $0.dropFirst() + "Of"
            } ?? "arrayOf"
            return "kotlin.\(factory)(\(values.map { annotationSourceValue($0) }.joined(separator: ", ")))"
        case .annotation(let annotation):
            let name = Self.dottedTypeName(String(annotation.descriptor.dropFirst().dropLast()))
            let arguments = annotation.values.map { "`\($0.0)` = \(annotationSourceValue($0.1))" }.joined(separator: ", ")
            return "\(name)(\(arguments))"
        case .constant(.null), .integral:
            return "null"
        }
    }

    static func kotlinStringLiteral(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "$": result += "\\$"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
