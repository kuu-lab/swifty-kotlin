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

// Week-derived field values captured when the calendar was last
// materialized (any read, setTimeInMillis, or creation). java.util.Calendar
// keeps these as computed field values until the next complete(); week-field
// writes that arrive before any read must resolve against this snapshot
// rather than the pending date, matching JDK stamp-based field selection.
struct RuntimeCalendarWeekSnapshot {
    var weekday: Int
    var weekOfYear: Int
    var yearForWeekOfYear: Int
    var weekOfMonth: Int
    var weekdayOrdinal: Int
}

final class RuntimeCalendarBox {
    var calendar: Foundation.Calendar
    var date: Date
    var timeZoneIdentifier: String
    var weekSnapshot: RuntimeCalendarWeekSnapshot?
    var pendingWeekFields: [Int: Int] = [:]
    // Calendar field id (WEEK_OF_YEAR/WEEK_OF_MONTH/DAY_OF_WEEK_IN_MONTH) of
    // the week-field group most recently written via set(); DAY_OF_WEEK
    // writes resolve within that group. 0 selects the default
    // WEEK_OF_MONTH group, matching java.util.Calendar's stamp ordering.
    var weekFieldGroup = 0

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
    case 14: return ((components.nanosecond ?? 0) + 500_000) / 1_000_000
    case 15: return runtimeTimeZoneRawOffset(in: box.calendar.timeZone)
    case 16: return runtimeTimeZoneOffset(milliseconds: runtimeEpochMilliseconds(box.date), in: box.calendar.timeZone)
            - runtimeTimeZoneRawOffset(in: box.calendar.timeZone)
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Calendar.get received unsupported field \(field)")
    }
}

private func runtimeCalendarMaterializeWeekFields(_ box: RuntimeCalendarBox) {
    let components = runtimeCalendarComponents(box)
    box.weekSnapshot = RuntimeCalendarWeekSnapshot(
        weekday: components.weekday ?? 1,
        weekOfYear: components.weekOfYear ?? 1,
        yearForWeekOfYear: components.yearForWeekOfYear ?? components.year ?? 1970,
        weekOfMonth: components.weekOfMonth ?? 1,
        weekdayOrdinal: components.weekdayOrdinal ?? 1
    )
    box.pendingWeekFields.removeAll()
    box.weekFieldGroup = 0
}

private func runtimeCalendarClearWeekComponents(_ components: inout DateComponents) {
    components.weekday = nil
    components.weekdayOrdinal = nil
    components.weekOfYear = nil
    components.weekOfMonth = nil
    components.yearForWeekOfYear = nil
    components.quarter = nil
    components.isLeapMonth = nil
}

private func runtimeCalendarPendingWeekValue(_ field: Int, box: RuntimeCalendarBox) -> Int? {
    if let pending = box.pendingWeekFields[field] {
        return pending
    }
    guard let snapshot = box.weekSnapshot else {
        return nil
    }
    switch field {
    case 3: return snapshot.weekOfYear
    case 4: return snapshot.weekOfMonth
    case 7: return snapshot.weekday
    case 8: return snapshot.weekdayOrdinal
    default: return nil
    }
}

private func runtimeCalendarSetField(_ field: Int, value: Int, box: RuntimeCalendarBox) {
    var components = runtimeCalendarComponents(box)
    switch field {
    case 0: components.era = value
    case 1: components.year = value
    case 2: components.month = value + 1
    case 3, 4, 7, 8:
        let group = field == 7 ? (box.weekFieldGroup == 0 ? 4 : box.weekFieldGroup) : field
        switch group {
        case 3:
            components.yearForWeekOfYear = components.year
            components.weekOfYear = field == 3 ? value : (runtimeCalendarPendingWeekValue(3, box: box) ?? components.weekOfYear)
            components.weekday = field == 7 ? value : (runtimeCalendarPendingWeekValue(7, box: box) ?? components.weekday)
            components.year = nil
            components.month = nil
            components.day = nil
            components.weekOfMonth = nil
            components.weekdayOrdinal = nil
            components.quarter = nil
            components.isLeapMonth = nil
        case 8:
            components.weekdayOrdinal = field == 8 ? value : (runtimeCalendarPendingWeekValue(8, box: box) ?? components.weekdayOrdinal)
            components.weekday = field == 7 ? value : (runtimeCalendarPendingWeekValue(7, box: box) ?? components.weekday)
            components.day = nil
            components.weekOfYear = nil
            components.yearForWeekOfYear = nil
            components.weekOfMonth = nil
            components.quarter = nil
            components.isLeapMonth = nil
        default:
            components.weekOfMonth = field == 4 ? value : (runtimeCalendarPendingWeekValue(4, box: box) ?? components.weekOfMonth)
            components.weekday = field == 7 ? value : (runtimeCalendarPendingWeekValue(7, box: box) ?? components.weekday)
            components.day = nil
            components.weekOfYear = nil
            components.yearForWeekOfYear = nil
            components.weekdayOrdinal = nil
            components.quarter = nil
            components.isLeapMonth = nil
        }
        if field != 7 {
            box.weekFieldGroup = field
        }
        box.pendingWeekFields[field] = value
    case 5: components.day = value
    case 6: components.day = value
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
    // dateComponents(in:from:) also reports week-derived fields
    // (weekOfYear/yearForWeekOfYear/weekday...). When they stay populated,
    // Calendar.date(from:) resolves the date from the week fields and
    // silently ignores year/month/day writes — e.g. set(YEAR) was a no-op.
    // Week-field writes (3, 4, 7, 8) keep the sibling fields of their own
    // group and drop the rest above; every other field drops them here.
    if field != 3 && field != 4 && field != 7 && field != 8 {
        runtimeCalendarClearWeekComponents(&components)
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

@_cdecl("__kk_time_zone_get_display_name")
public func __kk_time_zone_get_display_name(
    _ timeZoneRaw: Int,
    _ inDaylight: Int,
    _ style: Int,
    _ localeRaw: Int
) -> Int {
    let box = requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_time_zone_get_display_name")
    let daylight = inDaylight != 0
    let nameStyle: Foundation.TimeZone.NameStyle
    if style == 1 {
        nameStyle = daylight ? .daylightSaving : .standard
    } else {
        nameStyle = daylight ? .shortDaylightSaving : .shortStandard
    }
    let locale = runtimeLocaleBox(from: localeRaw)?.locale
    let name = box.timeZone.localizedName(for: nameStyle, locale: locale) ?? box.timeZone.identifier
    return runtimeMakeStringRaw(name)
}

@_cdecl("__kk_calendar_create")
public func __kk_calendar_create(_ timeZoneRaw: Int) -> Int {
    let timeZoneBox = requiredRuntimeTimeZone(timeZoneRaw, symbol: "__kk_calendar_create")
    var calendar = Foundation.Calendar(identifier: .gregorian)
    calendar.locale = runtimeDefaultFoundationLocale()
    calendar.timeZone = timeZoneBox.timeZone
    let box = RuntimeCalendarBox(calendar: calendar, timeZoneIdentifier: timeZoneBox.identifier)
    runtimeCalendarMaterializeWeekFields(box)
    return registerRuntimeObject(box, typeID: runtimeCalendarNominalTypeID)
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
    calendar.locale = runtimeDefaultFoundationLocale()
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
    let box = RuntimeCalendarBox(calendar: calendar, date: date, timeZoneIdentifier: timeZoneBox.identifier)
    runtimeCalendarMaterializeWeekFields(box)
    return registerRuntimeObject(box, typeID: runtimeCalendarNominalTypeID)
}

@_cdecl("__kk_calendar_get_time_in_millis")
public func __kk_calendar_get_time_in_millis(_ calendarRaw: Int) -> Int {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_time_in_millis")
    runtimeCalendarMaterializeWeekFields(box)
    return runtimeEpochMilliseconds(box.date)
}

@_cdecl("__kk_calendar_set_time_in_millis")
public func __kk_calendar_set_time_in_millis(_ calendarRaw: Int, _ value: Int) {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_set_time_in_millis")
    box.date = runtimeDate(milliseconds: value)
    runtimeCalendarMaterializeWeekFields(box)
}

@_cdecl("__kk_calendar_set_week_date")
public func __kk_calendar_set_week_date(_ calendarRaw: Int, _ weekYear: Int, _ weekOfYear: Int, _ dayOfWeek: Int) {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_set_week_date")
    var components = runtimeCalendarComponents(box)
    components.yearForWeekOfYear = weekYear
    components.weekOfYear = weekOfYear
    components.weekday = dayOfWeek
    components.year = nil
    components.month = nil
    components.day = nil
    components.weekOfMonth = nil
    components.weekdayOrdinal = nil
    components.quarter = nil
    components.isLeapMonth = nil
    if let updatedDate = box.calendar.date(from: components) {
        box.date = updatedDate
    }
    runtimeCalendarMaterializeWeekFields(box)
}

@_cdecl("__kk_calendar_get_field")
public func __kk_calendar_get_field(_ calendarRaw: Int, _ field: Int) -> Int {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_field")
    runtimeCalendarMaterializeWeekFields(box)
    return runtimeCalendarField(field, box: box)
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
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_add_field")
    runtimeCalendarMaterializeWeekFields(box)
    runtimeCalendarAddField(
        field,
        amount: amount,
        box: box
    )
}

// MARK: - Calendar field bounds (KUU-4288)
//
// JDK `java.util.GregorianCalendar` publishes fixed per-field bounds. The
// least-maximum column additionally folds in the 1582 Gregorian-cutover
// adjustment that the JDK derives from its hybrid Julian/Gregorian calendar;
// this runtime is proleptic Gregorian, so the cutover-adjusted constants
// (which assume the default Sunday/`minimalDaysInFirstWeek=1` week rules)
// are stored directly.
private let runtimeCalendarFieldMinValues = [0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, -46_800_000, 0]
private let runtimeCalendarFieldMaxValues = [1, 292_278_994, 11, 53, 6, 31, 366, 7, 6, 1, 11, 23, 59, 59, 999, 50_400_000, 7_200_000]
private let runtimeCalendarFieldLeastMaxValues = [1, 292_269_054, 11, 50, 3, 28, 355, 7, 3, 1, 11, 23, 59, 59, 999, 50_400_000, 1_200_000]

private func runtimeCalendarFieldBound(_ values: [Int], _ field: Int, symbol: String) -> Int {
    guard values.indices.contains(field) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(symbol) received unsupported field \(field)")
    }
    return values[field]
}

/// Upper bound (inclusive) of `component` within `parent` for the calendar's
/// current date, matching JDK `getActualMaximum` for fields whose maximum is
/// state-dependent (day-of-month leap awareness, day-of-year, week fields,
/// day-of-week-in-month). Falls back to the JDK structural maximum when the
/// platform cannot express the range (e.g. extremely large years).
private func runtimeCalendarRangeMaximum(
    _ component: Foundation.Calendar.Component,
    in parent: Foundation.Calendar.Component,
    field: Int,
    box: RuntimeCalendarBox
) -> Int {
    guard let range = box.calendar.range(of: component, in: parent, for: box.date) else {
        return runtimeCalendarFieldMaxValues[field]
    }
    return range.upperBound - 1
}

/// JDK `GregorianCalendar.getActualMaximum(WEEK_OF_YEAR)`: the number of
/// weeks in the current calendar year under the calendar's first-week rules
/// (the JDK formula; verified identical to the JDK for every month of
/// 1999-2026 under the default Sunday/1 rules).
private func runtimeCalendarActualMaximumWeekOfYear(_ box: RuntimeCalendarBox) -> Int {
    let epochMs = runtimeCalendarEpochMilliseconds(box.date)
    let offsetMs = Int64(box.calendar.timeZone.secondsFromGMT(for: box.date)) * 1_000
    let local = runtimeCalendarLocalFields(epochMilliseconds: epochMs, offsetMilliseconds: offsetMs)
    let year = local.civil.year
    var jan1Components = DateComponents()
    jan1Components.calendar = box.calendar
    jan1Components.timeZone = box.calendar.timeZone
    jan1Components.year = Int(year)
    jan1Components.month = 1
    jan1Components.day = 1
    guard let jan1 = box.calendar.date(from: jan1Components), year > 0, year < 100_000 else { return 52 }
    var dayOfWeek = box.calendar.component(.weekday, from: jan1)
    dayOfWeek -= box.calendar.firstWeekday
    if dayOfWeek < 0 { dayOfWeek += 7 }
    let isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    let magic = dayOfWeek + box.calendar.minimumDaysInFirstWeek - 1
    return (magic == 6 || (isLeap && (magic == 5 || magic == 12))) ? 53 : 52
}

/// Epoch milliseconds for `date`, saturated to stay clear of the
/// Double->Int64 trap at 2^63. Day-level precision is all the calendar
/// year-offset comparison needs, and this also serves instants far beyond
/// what `runtimeEpochMilliseconds` accepts.
private func runtimeCalendarEpochMilliseconds(_ date: Date) -> Int64 {
    let milliseconds = date.timeIntervalSince1970 * 1_000
    guard milliseconds.isFinite else { return 0 }
    if milliseconds >= 4.6e18 { return Int64.max }
    if milliseconds <= -4.6e18 { return Int64.min }
    return Int64(milliseconds.rounded(.towardZero))
}

private func runtimeCalendarFloorDiv(_ value: Int64, _ divisor: Int64) -> Int64 {
    value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
}

/// Proleptic-Gregorian civil date for `days` days since 1970-01-01
/// (Howard Hinnant's algorithm). Needed because Foundation's calendar math
/// saturates around year 500k while JDK calendar bounds reach ~292 million.
private func runtimeCalendarCivilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
    let z = days + 719_468
    let era = runtimeCalendarFloorDiv(z, 146_097)
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    var year = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPrime = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
    let month = monthPrime + (monthPrime < 10 ? 3 : -9)
    if month <= 2 { year += 1 }
    return (year, month, day)
}

private func runtimeCalendarDayOfYear(year: Int64, month: Int64, day: Int64) -> Int64 {
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    let cumulative = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    var result = Int64(cumulative[Int(month) - 1]) + day
    if month > 2 && leap { result += 1 }
    return result
}

/// Local civil date and wall-clock fields for an epoch-millisecond instant,
/// split so no intermediate can overflow Int64 (the maximum instant plus a
/// positive zone offset would otherwise wrap).
private func runtimeCalendarLocalFields(
    epochMilliseconds: Int64,
    offsetMilliseconds: Int64
) -> (millisOfDay: Int64, civil: (year: Int64, month: Int64, day: Int64)) {
    let dayMilliseconds: Int64 = 86_400_000
    let epochDay = runtimeCalendarFloorDiv(epochMilliseconds, dayMilliseconds)
    let epochMillisOfDay = epochMilliseconds - epochDay * dayMilliseconds
    let shifted = epochMillisOfDay + offsetMilliseconds
    let shiftDays = runtimeCalendarFloorDiv(shifted, dayMilliseconds)
    return (
        shifted - shiftDays * dayMilliseconds,
        runtimeCalendarCivilFromDays(epochDay + shiftDays)
    )
}

/// Position of `box.date` within its calendar year in wall-clock
/// milliseconds, matching JDK `GregorianCalendar.getYearOffsetInMillis`.
/// Computed arithmetically so it also works for the ~292-million-year
/// instants involved in `getActualMaximum(YEAR)`.
private func runtimeCalendarYearOffsetInMillis(
    box: RuntimeCalendarBox,
    epochMilliseconds: Int64? = nil
) -> Int64 {
    let epochMs = epochMilliseconds ?? runtimeCalendarEpochMilliseconds(box.date)
    // ZONE_OFFSET + DST_OFFSET is the total offset from GMT at this instant.
    let offsetMs = Int64(box.calendar.timeZone.secondsFromGMT(for: box.date)) * 1_000
    let dayMs: Int64 = 86_400_000
    let local = runtimeCalendarLocalFields(epochMilliseconds: epochMs, offsetMilliseconds: offsetMs)
    let dayOfYear = runtimeCalendarDayOfYear(
        year: local.civil.year, month: local.civil.month, day: local.civil.day
    )
    return Int64(dayOfYear - 1) * dayMs + local.millisOfDay - offsetMs
}

/// JDK `GregorianCalendar.getActualMaximum(YEAR)`: the year containing the
/// maximum representable instant (Long.MAX_VALUE epoch milliseconds in the
/// JDK; Int64.max here, the same domain), decremented when the current
/// position within the year is later than the maximum instant's.
private func runtimeCalendarActualMaximumYear(_ box: RuntimeCalendarBox) -> Int {
    let maxBox = RuntimeCalendarBox(
        calendar: box.calendar,
        date: runtimeDate(milliseconds: Int.max),
        timeZoneIdentifier: box.timeZoneIdentifier
    )
    let maxOffsetMs = Int64(box.calendar.timeZone.secondsFromGMT(for: maxBox.date)) * 1_000
    let maxLocal = runtimeCalendarLocalFields(
        epochMilliseconds: Int64.max, offsetMilliseconds: maxOffsetMs
    )
    var value = Int(maxLocal.civil.year)
    if runtimeCalendarYearOffsetInMillis(box: box)
        > runtimeCalendarYearOffsetInMillis(box: maxBox, epochMilliseconds: Int64.max) {
        value -= 1
    }
    return value
}

private func runtimeCalendarActualMaximum(_ field: Int, box: RuntimeCalendarBox) -> Int {
    switch field {
    case 1:
        return runtimeCalendarActualMaximumYear(box)
    case 2:
        return 11 // MONTH: December — every month occurs in every year
    case 3:
        return runtimeCalendarActualMaximumWeekOfYear(box)
    case 4:
        return runtimeCalendarRangeMaximum(.weekOfMonth, in: .month, field: field, box: box)
    case 5:
        return runtimeCalendarRangeMaximum(.day, in: .month, field: field, box: box)
    case 6:
        return runtimeCalendarRangeMaximum(.day, in: .year, field: field, box: box)
    case 8:
        return runtimeCalendarRangeMaximum(.weekdayOrdinal, in: .month, field: field, box: box)
    case 0, 7, 9, 10, 11, 12, 13, 14, 15, 16:
        return runtimeCalendarFieldBound(
            runtimeCalendarFieldMaxValues, field,
            symbol: "__kk_calendar_get_actual_maximum"
        )
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_calendar_get_actual_maximum received unsupported field \(field)")
    }
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

@_cdecl("__kk_calendar_get_minimum")
public func __kk_calendar_get_minimum(_ calendarRaw: Int, _ field: Int) -> Int {
    _ = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_minimum")
    return runtimeCalendarFieldBound(
        runtimeCalendarFieldMinValues, field, symbol: "__kk_calendar_get_minimum"
    )
}

@_cdecl("__kk_calendar_get_maximum")
public func __kk_calendar_get_maximum(_ calendarRaw: Int, _ field: Int) -> Int {
    _ = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_maximum")
    return runtimeCalendarFieldBound(
        runtimeCalendarFieldMaxValues, field, symbol: "__kk_calendar_get_maximum"
    )
}

@_cdecl("__kk_calendar_get_greatest_minimum")
public func __kk_calendar_get_greatest_minimum(_ calendarRaw: Int, _ field: Int) -> Int {
    _ = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_greatest_minimum")
    return runtimeCalendarFieldBound(
        runtimeCalendarFieldMinValues, field, symbol: "__kk_calendar_get_greatest_minimum"
    )
}

@_cdecl("__kk_calendar_get_least_maximum")
public func __kk_calendar_get_least_maximum(_ calendarRaw: Int, _ field: Int) -> Int {
    _ = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_least_maximum")
    return runtimeCalendarFieldBound(
        runtimeCalendarFieldLeastMaxValues, field, symbol: "__kk_calendar_get_least_maximum"
    )
}

@_cdecl("__kk_calendar_get_actual_minimum")
public func __kk_calendar_get_actual_minimum(_ calendarRaw: Int, _ field: Int) -> Int {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_actual_minimum")
    runtimeCalendarMaterializeWeekFields(box)
    // JDK GregorianCalendar returns getMinimum(field) for every field except
    // DAY_OF_MONTH inside the 1582 cutover year (this runtime is proleptic
    // Gregorian and has no cutover), so the minimum table is authoritative.
    return runtimeCalendarFieldBound(
        runtimeCalendarFieldMinValues, field, symbol: "__kk_calendar_get_actual_minimum"
    )
}

@_cdecl("__kk_calendar_get_week_year")
public func __kk_calendar_get_week_year(_ calendarRaw: Int) -> Int {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_week_year")
    runtimeCalendarMaterializeWeekFields(box)
    let components = runtimeCalendarComponents(box)
    return components.yearForWeekOfYear ?? components.year ?? 1970
}

@_cdecl("__kk_calendar_get_actual_maximum")
public func __kk_calendar_get_actual_maximum(_ calendarRaw: Int, _ field: Int) -> Int {
    let box = requiredRuntimeCalendar(calendarRaw, symbol: "__kk_calendar_get_actual_maximum")
    runtimeCalendarMaterializeWeekFields(box)
    return runtimeCalendarActualMaximum(field, box: box)
}
