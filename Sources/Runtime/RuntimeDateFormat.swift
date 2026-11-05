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

/// `java.text.MessageFormat` date/time sub-formats.
/// kind: 0=date, 1=time, 2=date+time; style: 0=short, 1=medium, 2=long, 3=full.
@_cdecl("__kk_messageformat_datetime")
public func __kk_messageformat_datetime(_ kind: Int, _ style: Int, _ millis: Int, _ localeRaw: Int) -> Int {
    let box = runtimeLocaleBox(from: localeRaw)
    let formatter = DateFormatter()
    formatter.locale = box?.locale ?? .current
    formatter.timeZone = .current
    let formatterStyle: DateFormatter.Style
    switch style {
    case 0: formatterStyle = .short
    case 2: formatterStyle = .long
    case 3: formatterStyle = .full
    default: formatterStyle = .medium
    }
    switch kind {
    case 0:
        formatter.dateStyle = formatterStyle
        formatter.timeStyle = .none
    case 1:
        formatter.dateStyle = .none
        formatter.timeStyle = formatterStyle
    default:
        formatter.dateStyle = formatterStyle
        formatter.timeStyle = formatterStyle
    }
    let date = Date(timeIntervalSince1970: Double(millis) / 1_000)
    return runtimeMakeStringRaw(formatter.string(from: date))
}

/// `java.text.MessageFormat` custom date/time patterns (`{n,date,pattern}`).
/// The pattern uses `SimpleDateFormat`/LDML letters, which Foundation's
/// `DateFormatter.dateFormat` understands for the common subset.
@_cdecl("__kk_simple_date_format_format")
public func __kk_simple_date_format_format(_ patternRaw: Int, _ millis: Int, _ localeRaw: Int) -> Int {
    guard let pattern = runtimeStringFromRaw(patternRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: SimpleDateFormat.format received an invalid pattern handle")
    }
    let box = runtimeLocaleBox(from: localeRaw)
    let formatter = DateFormatter()
    formatter.locale = box?.locale ?? .current
    formatter.timeZone = .current
    formatter.isLenient = true
    formatter.dateFormat = pattern
    let date = Date(timeIntervalSince1970: Double(millis) / 1_000)
    return runtimeMakeStringRaw(formatter.string(from: date))
}
