import Foundation

private let runtimeTimeZoneNominalTypeID = runtimeStableNominalTypeID(fqName: "java.util.TimeZone")
private let runtimeCalendarNominalTypeID = runtimeStableNominalTypeID(fqName: "java.util.Calendar")

final class RuntimeTimeZoneBox {
    let timeZone: Foundation.TimeZone
    let identifier: String

    init(_ timeZone: Foundation.TimeZone, identifier: String? = nil) {
        self.timeZone = timeZone
        self.identifier = identifier ?? timeZone.identifier
    }
}

final class RuntimeCalendarBox {
    var calendar: Foundation.Calendar
    var date: Date
    var timeZoneIdentifier: String

    init(calendar: Foundation.Calendar, date: Date = Date(), timeZoneIdentifier: String? = nil) {
        self.calendar = calendar
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier ?? calendar.timeZone.identifier
    }
}

private func runtimeTimeZoneBox(from raw: Int) -> RuntimeTimeZoneBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeTimeZoneBox.self)
}

private func runtimeCalendarBox(from raw: Int) -> RuntimeCalendarBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeCalendarBox.self)
}

private func requiredRuntimeTimeZone(_ raw: Int, symbol: String) -> RuntimeTimeZoneBox {
    guard let box = runtimeTimeZoneBox(from: raw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(symbol) received an invalid TimeZone handle")
    }
    return box
}

private func requiredRuntimeCalendar(_ raw: Int, symbol: String) -> RuntimeCalendarBox {
    guard let box = runtimeCalendarBox(from: raw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(symbol) received an invalid Calendar handle")
    }
    return box
}

private func runtimeTimeZoneOffset(milliseconds: Int, in timeZone: Foundation.TimeZone) -> Int {
    let timestamp = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    return timeZone.secondsFromGMT(for: timestamp) * 1_000
}

private func runtimeTimeZoneRawOffset(in timeZone: Foundation.TimeZone) -> Int {
    let january = Date(timeIntervalSince1970: 1_578_096_000) // 2020-01-15T00:00:00Z
    let july = Date(timeIntervalSince1970: 1_594_771_200) // 2020-07-15T00:00:00Z
    return min(timeZone.secondsFromGMT(for: january), timeZone.secondsFromGMT(for: july)) * 1_000
}

private func runtimeDate(milliseconds: Int) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
}

private func runtimeEpochMilliseconds(_ date: Date) -> Int {
    let milliseconds = date.timeIntervalSince1970 * 1_000
    guard milliseconds.isFinite, milliseconds >= Double(Int.min), milliseconds < Double(Int.max) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Calendar time is outside the supported range")
    }
    return Int(milliseconds.rounded(.towardZero))
}

private func runtimeCalendarComponents(_ box: RuntimeCalendarBox) -> DateComponents {
    box.calendar.dateComponents(in: box.calendar.timeZone, from: box.date)
}

private func runtimeCalendarField(_ field: Int, box: RuntimeCalendarBox) -> Int {
    let components = runtimeCalendarComponents(box)
    switch field {
    case 0: return (components.era ?? 1) == 0 ? 0 : 1
    case 1: return components.year ?? 1970
    case 2: return (components.month ?? 1) - 1
    case 3: return components.weekOfYear ?? 1
    case 4: return components.weekOfMonth ?? 1
    case 5: return components.day ?? 1
    case 6: return box.calendar.ordinality(of: .day, in: .year, for: box.date) ?? 1
    case 7: return components.weekday ?? 1
    case 8: return box.calendar.ordinality(of: .weekdayOrdinal, in: .month, for: box.date) ?? 1
    case 9: return (components.hour ?? 0) >= 12 ? 1 : 0
    case 10: return (components.hour ?? 0) % 12
    case 11: return components.hour ?? 0
    case 12: return components.minute ?? 0
    case 13: return components.second ?? 0
    case 14: return (components.nanosecond ?? 0) / 1_000_000
    case 15: return runtimeTimeZoneRawOffset(in: box.calendar.timeZone)
    case 16: return runtimeTimeZoneOffset(milliseconds: runtimeEpochMilliseconds(box.date), in: box.calendar.timeZone)
            - runtimeTimeZoneRawOffset(in: box.calendar.timeZone)
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Calendar.get received unsupported field \(field)")
    }
}

private func runtimeCalendarSetField(_ field: Int, value: Int, box: RuntimeCalendarBox) {
    var components = runtimeCalendarComponents(box)
    switch field {
    case 0: components.era = value
    case 1: components.year = value
    case 2: components.month = value + 1
    case 3: components.weekOfYear = value
    case 4: components.weekOfMonth = value
    case 5: components.day = value
    case 6: components.day = value
    case 7: components.weekday = value
    case 8: components.weekdayOrdinal = value
    case 9:
        let hour = components.hour ?? 0
        components.hour = (hour % 12) + value * 12
    case 10:
        let hour = components.hour ?? 0
        components.hour = (hour / 12) * 12 + value
    case 11: components.hour = value
    case 12: components.minute = value
    case 13: components.second = value
    case 14: components.nanosecond = value * 1_000_000
    case 15, 16:
        return
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Calendar.set received unsupported field \(field)")
    }
    if let updatedDate = box.calendar.date(from: components) {
        box.date = updatedDate
    }
}

private func runtimeCalendarAddField(_ field: Int, amount: Int, box: RuntimeCalendarBox) {
    let component: Foundation.Calendar.Component
    switch field {
    case 0: component = .era
    case 1: component = .year
    case 2: component = .month
    case 3: component = .weekOfYear
    case 4: component = .weekOfMonth
    case 5, 6, 7, 8: component = .day
    case 9, 10, 11: component = .hour
    case 12: component = .minute
    case 13: component = .second
    case 14: component = .nanosecond
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Calendar.add received unsupported field \(field)")
    }
    if let updatedDate = box.calendar.date(byAdding: component, value: amount, to: box.date) {
        box.date = updatedDate
    }
}

@_cdecl("__kk_time_zone_get_default")
public func __kk_time_zone_get_default() -> Int {
    registerRuntimeObject(RuntimeTimeZoneBox(.current), typeID: runtimeTimeZoneNominalTypeID)
}

@_cdecl("__kk_time_zone_get_time_zone")
public func __kk_time_zone_get_time_zone(_ idRaw: Int) -> Int {
    guard let id = runtimeStringBox(fromRaw: idRaw)?.value else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_time_zone_get_time_zone received invalid String handle")
    }
    if let timeZone = Foundation.TimeZone(identifier: id) {
        return registerRuntimeObject(
            RuntimeTimeZoneBox(timeZone, identifier: id),
            typeID: runtimeTimeZoneNominalTypeID
        )
    }
    let fallback = Foundation.TimeZone(secondsFromGMT: 0)!
    return registerRuntimeObject(RuntimeTimeZoneBox(fallback), typeID: runtimeTimeZoneNominalTypeID)
}

@_cdecl("__kk_time_zone_get_id")
public func __kk_time_zone_get_id(_ timeZoneRaw: Int) -> Int {
    runtimeMakeStringRaw(
        requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_time_zone_get_id").identifier
    )
}

@_cdecl("__kk_time_zone_get_raw_offset")
public func __kk_time_zone_get_raw_offset(_ timeZoneRaw: Int) -> Int {
    runtimeTimeZoneRawOffset(in: requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_time_zone_get_raw_offset").timeZone)
}

@_cdecl("__kk_time_zone_get_offset")
public func __kk_time_zone_get_offset(_ timeZoneRaw: Int, _ epochMilliseconds: Int) -> Int {
    runtimeTimeZoneOffset(
        milliseconds: epochMilliseconds,
        in: requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_time_zone_get_offset").timeZone
    )
}

@_cdecl("__kk_calendar_create")
public func __kk_calendar_create(_ timeZoneRaw: Int) -> Int {
    let timeZoneBox = requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_calendar_create")
    var calendar = Foundation.Calendar(identifier: .gregorian)
    calendar.locale = Locale.current
    calendar.timeZone = timeZoneBox.timeZone
    return registerRuntimeObject(
        RuntimeCalendarBox(calendar: calendar, timeZoneIdentifier: timeZoneBox.identifier),
        typeID: runtimeCalendarNominalTypeID
    )
}

/// Atomically builds a calendar for explicit wall-clock fields so intermediate
/// normalization cannot disturb sibling fields (e.g. setting February before
/// the day on a 31st rolls the date into March). Out-of-range fields normalize
/// the way java.util.Calendar lenient mode does; a completely unresolvable
/// combination falls back to the epoch.
@_cdecl("__kk_calendar_create_fields")
public func __kk_calendar_create_fields(
    _ timeZoneRaw: Int,
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
    _ second: Int
) -> Int {
    let timeZoneBox = requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_calendar_create_fields")
    var calendar = Foundation.Calendar(identifier: .gregorian)
    calendar.locale = Locale.current
    calendar.timeZone = timeZoneBox.timeZone
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = timeZoneBox.timeZone
    components.era = 1
    components.year = year
    components.month = month + 1
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    components.nanosecond = 0
    let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    return registerRuntimeObject(
        RuntimeCalendarBox(calendar: calendar, date: date, timeZoneIdentifier: timeZoneBox.identifier),
        typeID: runtimeCalendarNominalTypeID
    )
}

@_cdecl("__kk_calendar_get_time_in_millis")
public func __kk_calendar_get_time_in_millis(_ calendarRaw: Int) -> Int {
    runtimeEpochMilliseconds(requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_time_in_millis").date)
}

@_cdecl("__kk_calendar_set_time_in_millis")
public func __kk_calendar_set_time_in_millis(_ calendarRaw: Int, _ value: Int) {
    requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_set_time_in_millis").date = runtimeDate(milliseconds: value)
}

@_cdecl("__kk_calendar_get_field")
public func __kk_calendar_get_field(_ calendarRaw: Int, _ field: Int) -> Int {
    runtimeCalendarField(field, box: requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_field"))
}

@_cdecl("__kk_calendar_set_field")
public func __kk_calendar_set_field(_ calendarRaw: Int, _ field: Int, _ value: Int) {
    runtimeCalendarSetField(
        field,
        value: value,
        box: requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_set_field")
    )
}

@_cdecl("__kk_calendar_add_field")
public func __kk_calendar_add_field(_ calendarRaw: Int, _ field: Int, _ amount: Int) {
    runtimeCalendarAddField(
        field,
        amount: amount,
        box: requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_add_field")
    )
}

@_cdecl("__kk_calendar_get_time_zone")
public func __kk_calendar_get_time_zone(_ calendarRaw: Int) -> Int {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_time_zone")
    return registerRuntimeObject(
        RuntimeTimeZoneBox(box.calendar.timeZone, identifier: box.timeZoneIdentifier),
        typeID: runtimeTimeZoneNominalTypeID
    )
}

@_cdecl("__kk_calendar_set_time_zone")
public func __kk_calendar_set_time_zone(_ calendarRaw: Int, _ timeZoneRaw: Int) {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_set_time_zone")
    let timeZone = requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_calendar_set_time_zone")
    box.calendar.timeZone = timeZone.timeZone
    box.timeZoneIdentifier = timeZone.identifier
}
