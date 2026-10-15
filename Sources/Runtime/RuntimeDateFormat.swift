import Foundation

@_cdecl("__kk_simple_date_format_parse")
public func kk_simple_date_format_parse(_ patternRaw: Int, _ sourceRaw: Int) -> Int {
    guard let pattern = runtimeStringFromRaw(patternRaw),
          let source = runtimeStringFromRaw(sourceRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: SimpleDateFormat.parse received an invalid string handle")
    }

    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = .current
    formatter.isLenient = true
    formatter.dateFormat = pattern

    guard let date = formatter.date(from: source) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: SimpleDateFormat.parse could not parse the input")
    }
    let epochMilliseconds = date.timeIntervalSince1970 * 1_000
    guard epochMilliseconds.isFinite,
          epochMilliseconds >= Double(Int.min),
          epochMilliseconds < Double(Int.max)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: SimpleDateFormat.parse result is outside the supported range")
    }
    return Int(epochMilliseconds.rounded(.towardZero))
}
