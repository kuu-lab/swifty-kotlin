import Foundation

/// A compact, sorted view of the stdlib artifact's imported member keys.
/// Keeping keys as UTF-8 ranges avoids rebuilding tens of thousands of
/// `BundledMemberKey` and `InternedString` values on every compilation.
struct PrecomputedBundledMemberIndex: Sendable {
    private struct Entry: Sendable {
        let ownerComponents: [Range<Int>]
        let name: Range<Int>
        let arity: Int
    }

    private static let magic = Array("KKMI".utf8)
    private static let version: UInt32 = 1
    private static let headerSize = 12
    private static let maximumEntryCount = 2_000_000
    private static let maximumFieldSize = 16 * 1024 * 1024

    private let data: Data
    private let entries: [Entry]
    private let interner: StringInterner

    init?(data: Data, interner: StringInterner) {
        guard data.count >= Self.headerSize,
              Array(data[0 ..< 4]) == Self.magic,
              Self.readUInt32(data, at: 4) == Self.version,
              let rawCount = Self.readUInt32(data, at: 8),
              rawCount <= UInt32(Self.maximumEntryCount)
        else {
            return nil
        }

        var cursor = Self.headerSize
        var decodedEntries: [Entry] = []
        decodedEntries.reserveCapacity(Int(rawCount))
        var previous: Entry?

        for _ in 0 ..< rawCount {
            guard let ownerCount = Self.readUInt32(data, at: cursor), ownerCount <= 1024 else {
                return nil
            }
            cursor += 4

            var ownerComponents: [Range<Int>] = []
            ownerComponents.reserveCapacity(Int(ownerCount))
            for _ in 0 ..< ownerCount {
                guard let range = Self.readStringRange(data, cursor: &cursor) else { return nil }
                ownerComponents.append(range)
            }
            guard let name = Self.readStringRange(data, cursor: &cursor),
                  let rawArity = Self.readUInt32(data, at: cursor)
            else {
                return nil
            }
            cursor += 4

            let entry = Entry(ownerComponents: ownerComponents, name: name, arity: Int(rawArity))
            if let previous, Self.compare(previous, entry, data: data) != .orderedAscending {
                return nil
            }
            decodedEntries.append(entry)
            previous = entry
        }

        guard cursor == data.count else { return nil }
        self.data = data
        entries = decodedEntries
        self.interner = interner
    }

    func contains(owner: [InternedString], name: InternedString, arity: Int) -> Bool {
        contains(owner: owner, name: name, arity: Optional(arity))
    }

    func contains(owner: [InternedString], name: InternedString) -> Bool {
        contains(owner: owner, name: name, arity: nil)
    }

    private func contains(owner: [InternedString], name: InternedString, arity: Int?) -> Bool {
        let ownerBytes = owner.map { Array(interner.resolve($0).utf8) }
        let nameBytes = Array(interner.resolve(name).utf8)
        var lower = 0
        var upper = entries.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if Self.compare(
                entries[middle],
                owner: ownerBytes,
                name: nameBytes,
                arity: arity,
                data: data
            ) == .orderedAscending {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < entries.count else { return false }
        return Self.compare(
            entries[lower],
            owner: ownerBytes,
            name: nameBytes,
            arity: arity,
            data: data
        ) == .orderedSame
    }

    static func encode(keys: Set<BundledMemberKey>, interner: StringInterner) -> Data {
        let sortedKeys = keys.sorted { lhs, rhs in
            let ownerOrder = compareStrings(
                lhs.ownerFQName.map { interner.resolve($0) },
                rhs.ownerFQName.map { interner.resolve($0) }
            )
            if ownerOrder != .orderedSame { return ownerOrder == .orderedAscending }
            let nameOrder = compareUTF8(interner.resolve(lhs.name), interner.resolve(rhs.name))
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.arity < rhs.arity
        }

        var result = Data(Self.magic)
        appendUInt32(Self.version, to: &result)
        appendUInt32(UInt32(clamping: sortedKeys.count), to: &result)
        for key in sortedKeys {
            appendUInt32(UInt32(clamping: key.ownerFQName.count), to: &result)
            for component in key.ownerFQName {
                appendString(interner.resolve(component), to: &result)
            }
            appendString(interner.resolve(key.name), to: &result)
            appendUInt32(UInt32(clamping: key.arity), to: &result)
        }
        return result
    }

    private static func compare(
        _ lhs: Entry,
        _ rhs: Entry,
        data: Data
    ) -> ComparisonResult {
        let sharedOwnerCount = min(lhs.ownerComponents.count, rhs.ownerComponents.count)
        for index in 0 ..< sharedOwnerCount {
            let order = compare(lhs.ownerComponents[index], rhs.ownerComponents[index], data: data)
            if order != .orderedSame { return order }
        }
        if lhs.ownerComponents.count != rhs.ownerComponents.count {
            return lhs.ownerComponents.count < rhs.ownerComponents.count ? .orderedAscending : .orderedDescending
        }
        let nameOrder = compare(lhs.name, rhs.name, data: data)
        if nameOrder != .orderedSame { return nameOrder }
        if lhs.arity == rhs.arity { return .orderedSame }
        return lhs.arity < rhs.arity ? .orderedAscending : .orderedDescending
    }

    private static func compare(
        _ entry: Entry,
        owner: [[UInt8]],
        name: [UInt8],
        arity: Int?,
        data: Data
    ) -> ComparisonResult {
        let sharedOwnerCount = min(entry.ownerComponents.count, owner.count)
        for index in 0 ..< sharedOwnerCount {
            let order = compare(entry.ownerComponents[index], to: owner[index], data: data)
            if order != .orderedSame { return order }
        }
        if entry.ownerComponents.count != owner.count {
            return entry.ownerComponents.count < owner.count ? .orderedAscending : .orderedDescending
        }
        let nameOrder = compare(entry.name, to: name, data: data)
        if nameOrder != .orderedSame { return nameOrder }
        guard let arity else { return .orderedSame }
        if entry.arity == arity { return .orderedSame }
        return entry.arity < arity ? .orderedAscending : .orderedDescending
    }

    private static func compare(_ lhs: Range<Int>, _ rhs: Range<Int>, data: Data) -> ComparisonResult {
        let sharedCount = min(lhs.count, rhs.count)
        for offset in 0 ..< sharedCount {
            let leftByte = data[lhs.lowerBound + offset]
            let rightByte = data[rhs.lowerBound + offset]
            if leftByte != rightByte {
                return leftByte < rightByte ? .orderedAscending : .orderedDescending
            }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }

    private static func compare(_ lhs: Range<Int>, to rhs: [UInt8], data: Data) -> ComparisonResult {
        let sharedCount = min(lhs.count, rhs.count)
        for offset in 0 ..< sharedCount {
            let leftByte = data[lhs.lowerBound + offset]
            let rightByte = rhs[offset]
            if leftByte != rightByte {
                return leftByte < rightByte ? .orderedAscending : .orderedDescending
            }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }

    private static func compareStrings(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        let sharedCount = min(lhs.count, rhs.count)
        for index in 0 ..< sharedCount {
            let order = compareUTF8(lhs[index], rhs[index])
            if order != .orderedSame { return order }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }

    private static func compareUTF8(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let sharedCount = min(left.count, right.count)
        for index in 0 ..< sharedCount where left[index] != right[index] {
            return left[index] < right[index] ? .orderedAscending : .orderedDescending
        }
        if left.count == right.count { return .orderedSame }
        return left.count < right.count ? .orderedAscending : .orderedDescending
    }

    private static func readStringRange(_ data: Data, cursor: inout Int) -> Range<Int>? {
        guard let rawLength = readUInt32(data, at: cursor),
              rawLength <= UInt32(maximumFieldSize)
        else {
            return nil
        }
        cursor += 4
        let length = Int(rawLength)
        guard cursor <= data.count, length <= data.count - cursor else { return nil }
        let range = cursor ..< cursor + length
        cursor += length
        return range
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func appendString(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        appendUInt32(UInt32(clamping: bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
