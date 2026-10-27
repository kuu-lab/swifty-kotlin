import Foundation
import CompilerCore
import RuntimeABI

enum JVMEmissionError: Error, CustomStringConvertible {
    case limit(String)

    var description: String {
        switch self {
        case let .limit(message): message
        }
    }
}

/// Big-endian classfile data. All narrowing conversions are checked by callers.
struct JVMBytes {
    var data = Data()

    mutating func u1(_ value: UInt8) { data.append(value) }
    mutating func u2(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }
    mutating func u4(_ value: UInt32) {
        u2(UInt16(truncatingIfNeeded: value >> 16))
        u2(UInt16(truncatingIfNeeded: value))
    }
}

private struct JVMBootstrapMethod: Hashable {
    let methodHandle: UInt16
    let arguments: [UInt16]
}

final class JVMConstantPool {
    private var entries: [Data] = []
    // Data keys preserve distinct UTF-16 spellings, unlike Swift String equality.
    private var indices: [Data: UInt16] = [:]
    private var bootstrapMethods: [JVMBootstrapMethod] = []
    private var bootstrapIndices: [JVMBootstrapMethod: UInt16] = [:]
    private(set) var referencedClassNames: Set<String> = []

    func intern(_ entry: JVMBytes, wide: Bool = false) throws -> UInt16 {
        if let index = indices[entry.data] { return index }
        guard entries.count + (wide ? 2 : 1) <= 65_534 else {
            throw JVMEmissionError.limit("JVM constant pool exceeds 65534 entries.")
        }
        let index = UInt16(entries.count + 1)
        entries.append(entry.data)
        if wide { entries.append(Data()) }
        indices[entry.data] = index
        return index
    }

    func utf8(_ value: String, kotlinLiteral: Bool = false) throws -> UInt16 {
        if !kotlinLiteral, value.contains("L"), value.contains(";") {
            referencedClassNames.formUnion(Self.classReferences(in: value))
        }
        let units = kotlinLiteral ? KotlinStringSurrogateEncoding.utf16CodeUnits(value) : Array(value.utf16)
        var encoded = Data()
        // CONSTANT_Utf8 uses modified UTF-8 over UTF-16 code units: NUL is
        // encoded as C0 80 and supplementary characters as two surrogate units.
        for unit in units {
            switch unit {
            case 1...0x7F: encoded.append(UInt8(unit))
            case 0...0x7FF:
                encoded.append(UInt8(0xC0 | (unit >> 6)))
                encoded.append(UInt8(0x80 | (unit & 0x3F)))
            default:
                encoded.append(UInt8(0xE0 | (unit >> 12)))
                encoded.append(UInt8(0x80 | ((unit >> 6) & 0x3F)))
                encoded.append(UInt8(0x80 | (unit & 0x3F)))
            }
        }
        guard encoded.count <= 65_535 else {
            throw JVMEmissionError.limit("A JVM string constant exceeds 65535 modified UTF-8 bytes.")
        }
        var entry = JVMBytes()
        entry.u1(1); entry.u2(UInt16(encoded.count)); entry.data.append(encoded)
        return try intern(entry)
    }

    func single(_ tag: UInt8, _ index: UInt16) throws -> UInt16 {
        var entry = JVMBytes()
        entry.u1(tag); entry.u2(index)
        return try intern(entry)
    }

    func pair(_ tag: UInt8, _ first: UInt16, _ second: UInt16) throws -> UInt16 {
        var entry = JVMBytes()
        entry.u1(tag); entry.u2(first); entry.u2(second)
        return try intern(entry)
    }

    func classInfo(_ name: String) throws -> UInt16 {
        if name.hasPrefix("[") {
            referencedClassNames.formUnion(Self.classReferences(in: name))
        } else {
            referencedClassNames.insert(name)
        }
        let nameIndex = try utf8(name)
        return try single(7, nameIndex)
    }

    private static func classReferences(in signature: String) -> Set<String> {
        let characters = Array(signature)
        var references: Set<String> = []

        func parseType(at start: Int) -> Int {
            guard start < characters.count else { return start }
            switch characters[start] {
            case "[":
                return parseType(at: start + 1)
            case "T":
                var index = start + 1
                while index < characters.count, characters[index] != ";", characters[index] != ":" { index += 1 }
                return index < characters.count && characters[index] == ";" ? index + 1 : start + 1
            case "L":
                var index = start + 1
                var name = ""
                while index < characters.count {
                    switch characters[index] {
                    case ";":
                        if !name.isEmpty { references.insert(name) }
                        return index + 1
                    case "<":
                        if !name.isEmpty { references.insert(name) }
                        index += 1
                        while index < characters.count, characters[index] != ">" {
                            let next = parseType(at: index)
                            index = next > index ? next : index + 1
                        }
                        if index < characters.count { index += 1 }
                    case ".":
                        name += "$"
                        index += 1
                    default:
                        name.append(characters[index])
                        index += 1
                    }
                }
                if !name.isEmpty { references.insert(name) }
                return index
            case "+", "-":
                return parseType(at: start + 1)
            default:
                return start + 1
            }
        }

        var index = 0
        while index < characters.count {
            let next = parseType(at: index)
            index = next > index ? next : index + 1
        }
        return references
    }

    func member(_ tag: UInt8, owner: String, name: String, descriptor: String) throws -> UInt16 {
        let ownerIndex = try classInfo(owner)
        let nameIndex = try utf8(name)
        let descriptorIndex = try utf8(descriptor)
        let nameAndType = try pair(12, nameIndex, descriptorIndex)
        return try pair(tag, ownerIndex, nameAndType)
    }

    func methodType(_ descriptor: String) throws -> UInt16 {
        try single(16, utf8(descriptor))
    }

    func methodHandle(referenceKind: UInt8, referenceTag: UInt8, owner: String, name: String, descriptor: String) throws -> UInt16 {
        var entry = JVMBytes()
        entry.u1(15); entry.u1(referenceKind)
        entry.u2(try member(referenceTag, owner: owner, name: name, descriptor: descriptor))
        return try intern(entry)
    }

    func invokeDynamic(name: String, descriptor: String, samDescriptor: String, implementation: JVMFunctionReference, instantiatedDescriptor: String) throws -> UInt16 {
        let metafactoryDescriptor = "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;"
        let bootstrapHandle = try methodHandle(
            referenceKind: 6,
            referenceTag: 10,
            owner: "java/lang/invoke/LambdaMetafactory",
            name: "metafactory",
            descriptor: metafactoryDescriptor
        )
        let implementationHandle = try methodHandle(
            referenceKind: 6,
            referenceTag: implementation.ownerIsInterface ? 11 : 10,
            owner: implementation.owner ?? "",
            name: implementation.name,
            descriptor: implementation.descriptor
        )
        let bootstrap = JVMBootstrapMethod(
            methodHandle: bootstrapHandle,
            arguments: [try methodType(samDescriptor), implementationHandle, try methodType(instantiatedDescriptor)]
        )
        let bootstrapIndex: UInt16
        if let existing = bootstrapIndices[bootstrap] {
            bootstrapIndex = existing
        } else {
            guard bootstrapMethods.count < Int(UInt16.max) else {
                throw JVMEmissionError.limit("JVM BootstrapMethods attribute exceeds 65535 entries.")
            }
            bootstrapIndex = UInt16(bootstrapMethods.count)
            bootstrapMethods.append(bootstrap)
            bootstrapIndices[bootstrap] = bootstrapIndex
        }
        let nameIndex = try utf8(name)
        let descriptorIndex = try utf8(descriptor)
        let nameAndType = try pair(12, nameIndex, descriptorIndex)
        return try pair(18, bootstrapIndex, nameAndType)
    }

    func bootstrapMethodsAttribute() throws -> (nameIndex: UInt16, data: Data)? {
        guard !bootstrapMethods.isEmpty else { return nil }
        guard bootstrapMethods.count <= Int(UInt16.max) else {
            throw JVMEmissionError.limit("JVM BootstrapMethods attribute exceeds 65535 entries.")
        }
        var bytes = JVMBytes()
        bytes.u2(UInt16(bootstrapMethods.count))
        for method in bootstrapMethods {
            guard method.arguments.count <= Int(UInt16.max) else {
                throw JVMEmissionError.limit("JVM bootstrap method exceeds 65535 arguments.")
            }
            bytes.u2(method.methodHandle); bytes.u2(UInt16(method.arguments.count))
            for argument in method.arguments { bytes.u2(argument) }
        }
        return (try utf8("BootstrapMethods"), bytes.data)
    }


    func constant(_ constant: JVMConstant) throws -> UInt16 {
        var entry = JVMBytes()
        var wide = false
        switch constant {
        case .null: throw JVMEmissionError.limit("Null is an instruction, not a pool constant.")
        case let .int(n): entry.u1(3); entry.u4(UInt32(bitPattern: n))
        case let .long(n):
            entry.u1(5); let bits = UInt64(bitPattern: n)
            entry.u4(UInt32(truncatingIfNeeded: bits >> 32)); entry.u4(UInt32(truncatingIfNeeded: bits)); wide = true
        case let .float(n): entry.u1(4); entry.u4(n.bitPattern)
        case let .double(n):
            entry.u1(6); let bits = n.bitPattern
            entry.u4(UInt32(truncatingIfNeeded: bits >> 32)); entry.u4(UInt32(truncatingIfNeeded: bits)); wide = true
        case let .string(s): return try single(8, utf8(s, kotlinLiteral: true))
        case let .boolean(b): entry.u1(3); entry.u4(b ? 1 : 0)
        }
        return try intern(entry, wide: wide)
    }

    func write(to bytes: inout JVMBytes) {
        bytes.u2(UInt16(entries.count + 1))
        for entry in entries { bytes.data.append(entry) }
    }
}
