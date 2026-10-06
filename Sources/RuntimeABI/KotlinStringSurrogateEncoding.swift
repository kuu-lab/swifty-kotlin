/// Lossless internal Swift String representation of Kotlin UTF-16.
/// An isolated surrogate is an escape followed by a marker; a literal escape
/// is doubled. Bare private-use scalars always represent themselves.
public enum KotlinStringSurrogateEncoding {
    private static let escape: UInt32 = 0xE800
    private static let markerBase: UInt32 = 0xE000
    private static let markerLimit: UInt32 = markerBase + 0x07FF

    public static func markerValue(for codeUnit: UInt32) -> UInt32? {
        guard (0xD800 ... 0xDFFF).contains(codeUnit) else { return nil }
        return markerBase + codeUnit - 0xD800
    }

    public static func codeUnitValue(for marker: UInt32) -> UInt32? {
        guard (markerBase ... markerLimit).contains(marker) else { return nil }
        return 0xD800 + marker - markerBase
    }

    public static func encode(_ value: String) -> String {
        fromUTF16CodeUnits(Array(value.utf16))
    }

    public static func fromUTF16CodeUnits(_ units: [UInt16]) -> String {
        var result = ""
        result.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            let unit = UInt32(units[index])
            if (0xD800 ... 0xDBFF).contains(unit), index + 1 < units.count,
               (0xDC00 ... 0xDFFF).contains(UInt32(units[index + 1]))
            {
                let low = UInt32(units[index + 1])
                result.unicodeScalars.append(UnicodeScalar(0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00)!)
                index += 2
            } else {
                if let marker = markerValue(for: unit) {
                    result.unicodeScalars.append(UnicodeScalar(escape)!)
                    result.unicodeScalars.append(UnicodeScalar(marker)!)
                } else {
                    if unit == escape {
                        result.unicodeScalars.append(UnicodeScalar(escape)!)
                    }
                    result.unicodeScalars.append(UnicodeScalar(unit)!)
                }
                index += 1
            }
        }
        return result
    }

    /// Decodes to ordinary Unicode text for foreign APIs. Like Swift's UTF-16
    /// decoder, this replaces isolated surrogates with U+FFFD.
    public static func unicodeString(_ value: String) -> String {
        String(decoding: utf16CodeUnits(value), as: UTF16.self)
    }

    /// Decodes to text for process output (stdout/stderr), matching the JDK
    /// CharsetEncoder convention that unpaired surrogates are emitted as '?'.
    public static func printableString(_ value: String) -> String {
        let units = utf16CodeUnits(value)
        var result = ""
        result.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            let unit = UInt32(units[index])
            if (0xD800 ... 0xDBFF).contains(unit), index + 1 < units.count,
               (0xDC00 ... 0xDFFF).contains(UInt32(units[index + 1]))
            {
                let low = UInt32(units[index + 1])
                result.unicodeScalars.append(UnicodeScalar(0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00)!)
                index += 2
            } else if (0xD800 ... 0xDFFF).contains(unit) {
                result.append("?")
                index += 1
            } else {
                result.unicodeScalars.append(UnicodeScalar(unit)!)
                index += 1
            }
        }
        return result
    }

    public static func utf16CodeUnits(_ value: String) -> [UInt16] {
        Array(UTF16CodeUnits(value))
    }

    public struct UTF16CodeUnits: Sequence {
        private let value: String

        public init(_ value: String) {
            self.value = value
        }

        public func makeIterator() -> Iterator {
            Iterator(value)
        }

        public struct Iterator: IteratorProtocol {
            private var scalars: String.UnicodeScalarView.Iterator
            private var pendingScalar: UInt32?
            private var pendingUnit: UInt16?

            fileprivate init(_ value: String) {
                scalars = value.unicodeScalars.makeIterator()
            }

            public mutating func next() -> UInt16? {
                if let unit = pendingUnit {
                    pendingUnit = nil
                    return unit
                }
                let scalar = pendingScalar ?? scalars.next()?.value
                pendingScalar = nil
                guard let scalar else { return nil }
                if scalar == escape, let next = scalars.next()?.value {
                    if next == escape { return UInt16(escape) }
                    if let unit = codeUnitValue(for: next) { return UInt16(unit) }
                    pendingScalar = next
                }
                if scalar <= 0xFFFF { return UInt16(scalar) }
                let offset = scalar - 0x10000
                pendingUnit = UInt16(0xDC00 + (offset & 0x03FF))
                return UInt16(0xD800 + (offset >> 10))
            }
        }
    }
}
