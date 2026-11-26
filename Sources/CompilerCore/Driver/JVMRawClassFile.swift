import Foundation

/// A classfile constant pool kept as raw entries, so a cloned method can keep
/// every original constant index.
public struct JVMRawConstantPool: Sendable {
    /// Entry bytes (tag included) by constant index. Index 0 and the second
    /// slot of a long/double entry are empty.
    public private(set) var entries: [Data] = [Data()]

    struct Invalid: Error {}

    public init() {}

    /// Parses `constant_pool_count` and the entries that follow it at `offset`.
    /// Returns the offset of the first byte after the pool.
    public static func parse(_ bytes: [UInt8], at start: Int) throws -> (pool: JVMRawConstantPool, end: Int) {
        var offset = start
        func need(_ count: Int) throws {
            guard count >= 0, offset + count <= bytes.count else { throw Invalid() }
        }
        try need(2)
        let count = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        offset += 2
        var pool = JVMRawConstantPool()
        var index = 1
        while index < count {
            try need(1)
            let tag = bytes[offset]
            let size: Int
            switch tag {
            case 1:
                try need(3)
                size = 3 + (Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]))
            case 3, 4, 9, 10, 11, 12, 17, 18: size = 5
            case 5, 6: size = 9
            case 7, 8, 16, 19, 20: size = 3
            case 15: size = 4
            default: throw Invalid()
            }
            try need(size)
            pool.entries.append(Data(bytes[offset..<offset + size]))
            offset += size
            index += 1
            if tag == 5 || tag == 6 {
                guard index < count else { throw Invalid() }
                pool.entries.append(Data())
                index += 1
            }
        }
        return (pool, offset)
    }

    public var count: Int { entries.count }

    private func entry(_ index: Int, tag: UInt8) -> Data? {
        guard entries.indices.contains(index), let first = entries[index].first, first == tag else { return nil }
        return entries[index]
    }

    private func u2(_ data: Data, _ at: Int) -> Int {
        let base = data.startIndex + at
        return Int(data[base]) << 8 | Int(data[base + 1])
    }

    public func utf8(_ index: Int) -> String? {
        guard let data = entry(index, tag: 1) else { return nil }
        return String(decoding: data.dropFirst(3), as: UTF8.self)
    }

    public func className(_ index: Int) -> String? {
        guard let data = entry(index, tag: 7) else { return nil }
        return utf8(u2(data, 1))
    }

    public func string(_ index: Int) -> String? {
        guard let data = entry(index, tag: 8) else { return nil }
        return utf8(u2(data, 1))
    }

    public func integer(_ index: Int) -> Int32? {
        guard let data = entry(index, tag: 3) else { return nil }
        let base = data.startIndex + 1
        let raw = UInt32(data[base]) << 24 | UInt32(data[base + 1]) << 16 | UInt32(data[base + 2]) << 8 | UInt32(data[base + 3])
        return Int32(bitPattern: raw)
    }

    /// Owner, name and descriptor of a field/method/interface-method reference.
    public func memberReference(_ index: Int) -> (owner: String, name: String, descriptor: String)? {
        guard entries.indices.contains(index), let tag = entries[index].first, [9, 10, 11].contains(tag) else { return nil }
        let data = entries[index]
        guard let owner = className(u2(data, 1)), let nameAndType = entry(u2(data, 3), tag: 12),
              let name = utf8(u2(nameAndType, 1)), let descriptor = utf8(u2(nameAndType, 3)) else { return nil }
        return (owner, name, descriptor)
    }

    public func isInvokeDynamicOrDynamic(_ index: Int) -> Bool {
        guard entries.indices.contains(index), let tag = entries[index].first else { return false }
        return tag == 17 || tag == 18
    }
}

/// Instruction-level reading of JVM bytecode.
public enum JVMBytecode {
    public static let nop: UInt8 = 0x00
    public static let invokestatic: UInt8 = 0xB8
    public static let invokedynamic: UInt8 = 0xBA

    /// The byte length of the instruction at `pc`, or nil if `code` is malformed.
    public static func length(of code: [UInt8], at pc: Int) -> Int? {
        guard code.indices.contains(pc) else { return nil }
        let length: Int
        switch code[pc] {
        case 0x00...0x0F, 0x1A...0x35, 0x3B...0x83, 0x85...0x98, 0xAC...0xB1, 0xBE, 0xBF, 0xC2, 0xC3: length = 1
        case 0x10, 0x12, 0x15...0x19, 0x36...0x3A, 0xA9, 0xBC: length = 2
        case 0x11, 0x13, 0x14, 0x84, 0x99...0xA8, 0xB2...0xB8, 0xBB, 0xBD, 0xC0, 0xC1, 0xC6, 0xC7: length = 3
        case 0xC5: length = 4
        case 0xB9, 0xBA, 0xC8, 0xC9: length = 5
        case 0xC4:
            guard code.indices.contains(pc + 1) else { return nil }
            length = code[pc + 1] == 0x84 ? 6 : 4
        case 0xAA:
            let base = (pc + 4) & ~3
            guard let low = int32(code, base + 4), let high = int32(code, base + 8), high >= low else { return nil }
            length = base + 12 + (Int(high) - Int(low) + 1) * 4 - pc
        case 0xAB:
            let base = (pc + 4) & ~3
            guard let pairs = int32(code, base + 4), pairs >= 0 else { return nil }
            length = base + 8 + Int(pairs) * 8 - pc
        default: return nil
        }
        return pc + length <= code.count ? length : nil
    }

    private static func int32(_ code: [UInt8], _ at: Int) -> Int32? {
        guard at >= 0, at + 4 <= code.count else { return nil }
        let raw = UInt32(code[at]) << 24 | UInt32(code[at + 1]) << 16 | UInt32(code[at + 2]) << 8 | UInt32(code[at + 3])
        return Int32(bitPattern: raw)
    }
}

/// A method's `Code` attribute, with the parts needed to clone it.
public struct JVMRawCode: Sendable {
    public var maxStack: UInt16
    public var maxLocals: UInt16
    public var code: [UInt8]
    public var exceptions: [(start: UInt16, end: UInt16, handler: UInt16, type: UInt16)]
    public var stackMapTable: Data?

    struct Invalid: Error {}

    /// True when any stack map frame records a `null` stack or local type.
    public var stackMapHasNull: Bool {
        guard let table = stackMapTable else { return false }
        let bytes = [UInt8](table)
        var offset = 0
        func u1() -> Int? { guard offset < bytes.count else { return nil }; defer { offset += 1 }; return Int(bytes[offset]) }
        func u2() -> Int? { guard let high = u1(), let low = u1() else { return nil }; return high << 8 | low }
        // Returns true for a Null entry, nil on malformed input.
        func verificationType() -> Bool? {
            guard let tag = u1() else { return nil }
            if tag == 7 || tag == 8 { return u2() == nil ? nil : false }
            return tag == 5
        }
        guard let count = u2() else { return true }
        for _ in 0..<count {
            guard let type = u1() else { return true }
            var types = 0
            switch type {
            case 0...63: break
            case 64...127: types = 1
            case 247: guard u2() != nil else { return true }; types = 1
            case 248...251: guard u2() != nil else { return true }
            case 252...254: guard u2() != nil else { return true }; types = type - 251
            case 255:
                guard u2() != nil, let locals = u2() else { return true }
                for _ in 0..<locals { guard let isNull = verificationType() else { return true }; if isNull { return true } }
                guard let stack = u2() else { return true }
                for _ in 0..<stack { guard let isNull = verificationType() else { return true }; if isNull { return true } }
            default: return true
            }
            for _ in 0..<types { guard let isNull = verificationType() else { return true }; if isNull { return true } }
        }
        return false
    }

    /// Parses the attribute payload that starts at `offset` (after the attribute header).
    static func parse(_ bytes: [UInt8], at start: Int, size: Int, pool: JVMRawConstantPool) throws -> JVMRawCode {
        var offset = start
        let end = start + size
        func u1() throws -> Int { guard offset < end else { throw Invalid() }; defer { offset += 1 }; return Int(bytes[offset]) }
        func u2() throws -> Int { let high = try u1(); return high << 8 | (try u1()) }
        func u4() throws -> Int { let high = try u2(); return high << 16 | (try u2()) }
        let maxStack = try u2(), maxLocals = try u2(), length = try u4()
        guard length > 0, offset + length <= end else { throw Invalid() }
        let code = Array(bytes[offset..<offset + length])
        offset += length
        var exceptions: [(start: UInt16, end: UInt16, handler: UInt16, type: UInt16)] = []
        for _ in 0..<(try u2()) {
            exceptions.append((UInt16(try u2()), UInt16(try u2()), UInt16(try u2()), UInt16(try u2())))
        }
        var stackMap: Data?
        for _ in 0..<(try u2()) {
            let name = try u2(), attributeSize = try u4()
            guard offset + attributeSize <= end else { throw Invalid() }
            if pool.utf8(name) == "StackMapTable" { stackMap = Data(bytes[offset..<offset + attributeSize]) }
            offset += attributeSize
        }
        return JVMRawCode(maxStack: UInt16(maxStack), maxLocals: UInt16(maxLocals), code: code, exceptions: exceptions, stackMapTable: stackMap)
    }
}

/// A classpath method whose bytecode carries `reifiedOperationMarker` calls.
/// The class bytes are shared (copy-on-write) with the reader.
public struct JVMReifiedBody: Sendable {
    public static let markerName = "reifiedOperationMarker"
    public static let needClassReificationName = "needClassReification"
    public static let markerOwner = "kotlin/jvm/internal/Intrinsics"

    public let classBytes: [UInt8]
    public let codeOffset: Int
    public let codeSize: Int

    /// One `iconst op; ldc "T"; invokestatic reifiedOperationMarker; <placeholder>` sequence.
    public struct Site: Sendable {
        public let start: Int
        /// First byte after the placeholder instruction that follows the marker.
        public let end: Int
        public let operation: Int
        public let identifier: String
        public let placeholderOpcode: UInt8
    }

    public struct Analysis: Sendable {
        public let pool: JVMRawConstantPool
        public let code: JVMRawCode
        public let sites: [Site]
        /// Set when the body has a shape that cannot be copied as-is.
        public let unsupported: String?
        /// True when running the body needs a compiler to resolve reified types.
        public let requiresReification: Bool
    }

    public init(classBytes: [UInt8], codeOffset: Int, codeSize: Int) {
        self.classBytes = classBytes
        self.codeOffset = codeOffset
        self.codeSize = codeSize
    }

    /// Parses the class's constant pool and this method's code.
    public func analyze(pool known: JVMRawConstantPool? = nil) throws -> Analysis {
        let pool: JVMRawConstantPool
        if let known {
            pool = known
        } else {
            guard classBytes.count > 10 else { throw JVMRawConstantPool.Invalid() }
            pool = try JVMRawConstantPool.parse(classBytes, at: 8).pool
        }
        let code = try JVMRawCode.parse(classBytes, at: codeOffset, size: codeSize, pool: pool)
        var sites: [Site] = []
        var unsupported: String?
        var needsClassReification = false
        var previous: [Int] = []
        var pc = 0
        while pc < code.code.count {
            guard let length = JVMBytecode.length(of: code.code, at: pc) else { throw JVMRawCode.Invalid() }
            let opcode = code.code[pc]
            if opcode == JVMBytecode.invokedynamic { unsupported = "invokedynamic" }
            if opcode == JVMBytecode.invokestatic, let reference = pool.memberReference(Self.index(code.code, pc + 1)) {
                if reference.owner == Self.markerOwner, reference.name == Self.markerName {
                    if let site = Self.site(code.code, pool: pool, markerStart: previous.count >= 2 ? previous[previous.count - 2] : nil,
                                            stringStart: previous.last, invoke: pc, invokeLength: length) {
                        sites.append(site)
                    } else {
                        unsupported = unsupported ?? "an unrecognized reifiedOperationMarker call"
                    }
                } else if reference.owner == Self.markerOwner, reference.name == Self.needClassReificationName {
                    needsClassReification = true
                }
            }
            previous.append(pc)
            pc += length
        }
        let requiresReification = !sites.isEmpty || needsClassReification
        if needsClassReification { unsupported = unsupported ?? "a lambda or object that needs class reification" }
        return Analysis(pool: pool, code: code, sites: sites, unsupported: requiresReification ? unsupported : nil, requiresReification: requiresReification)
    }

    private static func index(_ code: [UInt8], _ at: Int) -> Int {
        Int(code[at]) << 8 | Int(code[at + 1])
    }

    private static func site(
        _ code: [UInt8], pool: JVMRawConstantPool, markerStart: Int?, stringStart: Int?, invoke: Int, invokeLength: Int
    ) -> Site? {
        guard let markerStart, let stringStart,
              let operation = integerPush(code, at: markerStart, pool: pool),
              code[stringStart] == 0x12 || code[stringStart] == 0x13,
              let identifier = pool.string(code[stringStart] == 0x12 ? Int(code[stringStart + 1]) : index(code, stringStart + 1)),
              let placeholderLength = JVMBytecode.length(of: code, at: invoke + invokeLength) else { return nil }
        let placeholder = invoke + invokeLength
        return Site(start: markerStart, end: placeholder + placeholderLength, operation: operation,
                    identifier: identifier, placeholderOpcode: code[placeholder])
    }

    private static func integerPush(_ code: [UInt8], at pc: Int, pool: JVMRawConstantPool) -> Int? {
        switch code[pc] {
        case 0x02...0x08: return Int(code[pc]) - 0x03
        case 0x10: return Int(Int8(bitPattern: code[pc + 1]))
        case 0x11: return Int(Int16(bitPattern: UInt16(code[pc + 1]) << 8 | UInt16(code[pc + 2])))
        case 0x12: return pool.integer(Int(code[pc + 1])).map(Int.init)
        case 0x13: return pool.integer(index(code, pc + 1)).map(Int.init)
        default: return nil
        }
    }
}
