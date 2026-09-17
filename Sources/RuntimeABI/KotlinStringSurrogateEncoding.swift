/// Lossless bridge for isolated UTF-16 surrogate code units in Swift String.
///
/// Swift String cannot store an unpaired surrogate as a Unicode scalar. Until
/// Kotlin strings have a native UTF-16 representation, the compiler and runtime
/// encode isolated code units in this reserved BMP private-use range.
public enum KotlinStringSurrogateEncoding {
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
}
