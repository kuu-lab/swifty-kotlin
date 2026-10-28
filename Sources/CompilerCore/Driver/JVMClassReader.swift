import Foundation

struct JVMClassInfo {
    let name: String
    let flags: UInt16
    let superclass: String?
    let interfaces: [String]
    let methods: [JVMForeignMethod]
    var fields: [JVMForeignField] = []
    var bridgeMethods: [JVMForeignMethod] = []
    var classTypeParameterNames: [String] = []
    var innerClasses: [JVMInnerClassInfo] = []
    var hasInnerClassesAttribute = false
    var hasEnclosingMethod = false
    var isInterface: Bool { flags & 0x0200 != 0 }
}

struct JVMInnerClassInfo {
    let name: String
    let outerName: String?
    let innerName: String?
    let access: UInt16
}

struct JVMForeignField {
    let name: String
    let descriptor: String
    let access: UInt16
    var isStatic: Bool { access & 8 != 0 }
    var isPublic: Bool { access & 1 != 0 }
}

/// Reads declarations only. Dependency code and class initializers are never run.
struct JVMClassReader {
    var bytes: [UInt8]
    var offset = 0
    var strings: [Int: String] = [:]
    var classes: [Int: Int] = [:]
    struct Invalid: Error {}

    mutating func u1() throws -> UInt8 {
        guard offset < bytes.count else { throw Invalid() }
        defer { offset += 1 }; return bytes[offset]
    }
    mutating func u2() throws -> UInt16 { let a = try u1(); return UInt16(a) << 8 | UInt16(try u1()) }
    mutating func u4() throws -> UInt32 { let a = try u2(); return UInt32(a) << 16 | UInt32(try u2()) }
    mutating func skip(_ n: Int) throws {
        guard n >= 0, n <= bytes.count - offset else { throw Invalid() }; offset += n
    }
    func text(_ index: Int) throws -> String { guard let s = strings[index] else { throw Invalid() }; return s }
    func className(_ index: Int) throws -> String { guard let s = classes[index] else { throw Invalid() }; return try text(s) }
    mutating func attributes() throws {
        let count = try u2()
        for _ in 0..<count { _ = try u2(); let size = try u4(); try skip(Int(size)) }
    }
    private mutating func classAttributes() throws -> (signature: String?, innerClasses: [JVMInnerClassInfo], hasInnerClassesAttribute: Bool, hasEnclosingMethod: Bool) {
        let count = try u2()
        var signature: String?
        var innerClasses: [JVMInnerClassInfo] = []
        var hasInnerClassesAttribute = false
        var hasEnclosingMethod = false
        for _ in 0..<count {
            let attributeName = try text(Int(u2()))
            let size = try u4()
            guard size <= UInt32(bytes.count - offset) else { throw Invalid() }
            let end = offset + Int(size)
            switch attributeName {
            case "Signature":
                guard signature == nil, size == 2 else { throw Invalid() }
                signature = try text(Int(u2()))
            case "InnerClasses":
                guard !hasInnerClassesAttribute, size >= 2 else { throw Invalid() }
                hasInnerClassesAttribute = true
                let entryCount = Int(try u2())
                guard size == UInt32(2 + entryCount * 8) else { throw Invalid() }
                for _ in 0..<entryCount {
                    let innerIndex = Int(try u2())
                    let outerIndex = Int(try u2())
                    let innerNameIndex = Int(try u2())
                    let access = try u2()
                    innerClasses.append(JVMInnerClassInfo(
                        name: try className(innerIndex),
                        outerName: outerIndex == 0 ? nil : try className(outerIndex),
                        innerName: innerNameIndex == 0 ? nil : try text(innerNameIndex),
                        access: access
                    ))
                }
            case "EnclosingMethod":
                guard !hasEnclosingMethod, size == 4 else { throw Invalid() }
                hasEnclosingMethod = true
                try skip(Int(size))
            default:
                try skip(Int(size))
            }
            guard offset == end else { throw Invalid() }
        }
        return (signature, innerClasses, hasInnerClassesAttribute, hasEnclosingMethod)
    }

    private static func classTypeParameterNames(in signature: String?) throws -> [String] {
        guard let signature, signature.first == "<" else { return [] }
        let scalars = Array(signature)
        var index = 1
        var names: [String] = []

        func parseReferenceType() throws {
            guard index < scalars.count else { throw Invalid() }
            switch scalars[index] {
            case "[":
                index += 1
                try parseType()
            case "T":
                index += 1
                while index < scalars.count, scalars[index] != ";" { index += 1 }
                guard index < scalars.count else { throw Invalid() }
                index += 1
            case "L":
                index += 1
                while index < scalars.count {
                    switch scalars[index] {
                    case ";": index += 1; return
                    case "<":
                        index += 1
                        while index < scalars.count, scalars[index] != ">" {
                            if scalars[index] == "*" { index += 1; continue }
                            if scalars[index] == "+" || scalars[index] == "-" { index += 1 }
                            try parseReferenceType()
                        }
                        guard index < scalars.count else { throw Invalid() }
                        index += 1
                    default: index += 1
                    }
                }
                throw Invalid()
            default: throw Invalid()
            }
        }
        func parseType() throws {
            guard index < scalars.count else { throw Invalid() }
            if "BCDFIJSZ".contains(scalars[index]) { index += 1; return }
            try parseReferenceType()
        }

        while index < scalars.count, scalars[index] != ">" {
            let start = index
            while index < scalars.count, scalars[index] != ":" { index += 1 }
            guard index < scalars.count, index > start else { throw Invalid() }
            let name = String(scalars[start..<index])
            guard JVMProgramBuilder.isIdentifier(name) else { throw Invalid() }
            names.append(name)
            index += 1
            if index < scalars.count, scalars[index] != ":" { try parseReferenceType() }
            while index < scalars.count, scalars[index] == ":" {
                index += 1
                try parseReferenceType()
            }
        }
        guard index < scalars.count, scalars[index] == ">" else { throw Invalid() }
        return names
    }

    mutating func read() throws -> JVMClassInfo {
        guard try u4() == 0xCAFEBABE else { throw Invalid() }
        _ = try u2(); guard try u2() >= 45 else { throw Invalid() }
        let count = Int(try u2())
        var index = 1
        while index < count {
            switch try u1() {
            case 1:
                let length = Int(try u2()); guard length <= bytes.count - offset else { throw Invalid() }
                var units: [UInt16] = []
                let end = offset + length
                while offset < end {
                    let first = try u1()
                    if first > 0 && first < 128 { units.append(UInt16(first)) }
                    else if first & 0xE0 == 0xC0 {
                        guard offset < end else { throw Invalid() }; let b = try u1()
                        guard b & 0xC0 == 0x80 else { throw Invalid() }
                        units.append(UInt16(first & 31) << 6 | UInt16(b & 63))
                    } else if first & 0xF0 == 0xE0 {
                        guard offset + 1 < end else { throw Invalid() }; let b = try u1(), c = try u1()
                        guard b & 0xC0 == 0x80, c & 0xC0 == 0x80 else { throw Invalid() }
                        units.append(UInt16(first & 15) << 12 | UInt16(b & 63) << 6 | UInt16(c & 63))
                    } else { throw Invalid() }
                }
                strings[index] = String(decoding: units, as: UTF16.self)
            case 7: classes[index] = Int(try u2())
            case 3, 4: try skip(4)
            case 5, 6:
                guard index + 1 < count else { throw Invalid() }; try skip(8); index += 1
            case 8, 16, 19, 20: try skip(2)
            case 9, 10, 11, 12, 17, 18: try skip(4)
            case 15: try skip(3)
            default: throw Invalid()
            }
            index += 1
        }
        let flags = try u2(), this = try u2(), base = try u2()
        let name = try className(Int(this))
        let superclass = base == 0 ? nil : try className(Int(base))
        var interfaces: [String] = []
        let interfaceCount = try u2()
        for _ in 0..<interfaceCount { interfaces.append(try className(Int(u2()))) }
        let fieldCount = try u2()
        var fields: [JVMForeignField] = []
        for _ in 0..<fieldCount {
            let access = try u2(), nameIndex = try u2(), descriptorIndex = try u2()
            let fieldName = try text(Int(nameIndex)), descriptor = try text(Int(descriptorIndex))
            fields.append(JVMForeignField(name: fieldName, descriptor: descriptor, access: access))
            try attributes()
        }
        var methods: [JVMForeignMethod] = []
        var bridgeMethods: [JVMForeignMethod] = []
        let methodCount = try u2()
        for _ in 0..<methodCount {
            let access = try u2(), nameIndex = try u2(), descriptorIndex = try u2()
            let methodName = try text(Int(nameIndex)), descriptor = try text(Int(descriptorIndex))
            if access & 1 != 0, (access & 0x1040 == 0 || access & 0x0040 != 0), methodName != "<clinit>",
               let signature = try? JVMDescriptor.parse(descriptor),
               signature.0.reduce(0, { $0 + $1.width }) <= (access & 8 != 0 ? 255 : 254) {
                var method = JVMForeignMethod(owner: name, name: methodName, descriptor: descriptor,
                    parameters: signature.0, result: methodName == "<init>" ? .reference(name, nullable: false) : signature.1,
                    isStatic: access & 8 != 0, isInterface: flags & 0x0200 != 0, isAbstract: access & 0x0400 != 0)
                method.isFinal = access & 16 != 0
                if access & 0x0040 != 0 { bridgeMethods.append(method) }
                else { methods.append(method) }
            }
            try attributes()
        }
        let classAttributes = try classAttributes()
        guard offset == bytes.count else { throw Invalid() }
        return JVMClassInfo(
            name: name,
            flags: flags,
            superclass: superclass,
            interfaces: interfaces,
            methods: methods,
            fields: fields,
            bridgeMethods: bridgeMethods,
            classTypeParameterNames: try Self.classTypeParameterNames(in: classAttributes.signature),
            innerClasses: classAttributes.innerClasses,
            hasInnerClassesAttribute: classAttributes.hasInnerClassesAttribute,
            hasEnclosingMethod: classAttributes.hasEnclosingMethod
        )
    }
}

enum JVMDescriptor {
    static func parse(_ descriptor: String) throws -> ([JVMValueType], JVMValueType) {
        let bytes = Array(descriptor.utf8)
        var i = 0
        var arrayDepth = 0
        func type() throws -> JVMValueType {
            guard i < bytes.count else { throw JVMClassReader.Invalid() }
            let byte = bytes[i]; i += 1
            switch byte {
            case 66: return .byte
            case 83: return .short
            case 67: return .char
            case 73: return .int
            case 74: return .long
            case 70: return .float
            case 68: return .double
            case 90: return .boolean
            case 86: return .unit
            case 91:
                guard arrayDepth < 255 else { throw JVMClassReader.Invalid() }
                arrayDepth += 1; defer { arrayDepth -= 1 }
                let component = try type()
                guard component != .unit else { throw JVMClassReader.Invalid() }
                return .reference("[" + component.descriptor, nullable: true)
            case 76:
                let start = i
                while i < bytes.count, bytes[i] != 59 { i += 1 }
                guard i < bytes.count, i > start else { throw JVMClassReader.Invalid() }
                let name = String(decoding: bytes[start..<i], as: UTF8.self); i += 1
                guard name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ JVMProgramBuilder.isIdentifier(String($0)) }) else { throw JVMClassReader.Invalid() }
                return .reference(name, nullable: true)
            default: throw JVMClassReader.Invalid()
            }
        }
        guard bytes.first == 40 else { throw JVMClassReader.Invalid() }; i += 1
        var parameters: [JVMValueType] = []
        while i < bytes.count, bytes[i] != 41 {
            let t = try type(); guard t != .unit else { throw JVMClassReader.Invalid() }; parameters.append(t)
        }
        guard i < bytes.count else { throw JVMClassReader.Invalid() }; i += 1
        let result = try type()
        guard i == bytes.count else { throw JVMClassReader.Invalid() }
        return (parameters, result)
    }
}
