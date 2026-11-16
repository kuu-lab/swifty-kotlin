import Foundation
#if canImport(Darwin)
import Darwin
import CoreFoundation
#else
import Glibc
#endif

// Value-type Foundation bridges: NSDate/NSDateFormatter/NSTimeZone/NSLocale/
// NSUserDefaults/NSUUID plus NSLog and the NSThread convenience entry points.
// Every native object lives in a RuntimeForeignResourceLease exactly like the
// stream/run-loop/thread resources in RuntimeAppleFoundationBindings.swift.

#if canImport(Darwin)

/// Bit 62 tags foreign-resource tokens that travel through heterogeneous
/// `Any?` channels (NSUserDefaults.objectForKey and friends). A stored plist
/// integer can then never be mistaken for a wrapped Foundation object; real
/// tokens stay far below 2^62.
private let runtimeFoundationForeignTokenTag = Int(1) << 62

private func runtimeFoundationTaggedToken(_ token: Int) -> Int {
    token | runtimeFoundationForeignTokenTag
}

private func runtimeFoundationUntagToken(_ tagged: Int) -> Int? {
    guard tagged & runtimeFoundationForeignTokenTag != 0 else { return nil }
    return tagged & ~runtimeFoundationForeignTokenTag
}

private func runtimeFoundationNSDate(_ handle: Int) -> NSDate? {
    runtimeForeignResource(handle, as: NSDate.self)
}

private func runtimeFoundationDateFormatter(_ handle: Int) -> DateFormatter? {
    runtimeForeignResource(handle, as: DateFormatter.self)
}

private func runtimeFoundationTimeZone(_ handle: Int) -> NSTimeZone? {
    runtimeForeignResource(handle, as: NSTimeZone.self)
}

private func runtimeFoundationLocale(_ handle: Int) -> NSLocale? {
    runtimeForeignResource(handle, as: NSLocale.self)
}

private func runtimeFoundationUserDefaults(_ handle: Int) -> UserDefaults? {
    runtimeForeignResource(handle, as: UserDefaults.self)
}

private func runtimeFoundationUUID(_ handle: Int) -> NSUUID? {
    runtimeForeignResource(handle, as: NSUUID.self)
}

/// NSDate methods that take a counterpart date accept the Swift `Date`
/// overlay; the lease always stores the `NSDate` class cluster object.
private func runtimeFoundationCounterpartDate(_ handle: Int) -> Date? {
    runtimeFoundationNSDate(handle).map { $0 as Date }
}

/// `Any?` -> property-list value. The outer optional is nil for Kotlin null
/// AND for unsupported values; `runtimeFoundationPlistIsSupported` separates
/// them so setters can throw instead of silently dropping.
private func runtimeFoundationKotlinToPlist(_ raw: Int) -> Any?? {
    if raw == runtimeNullSentinelInt { return .some(nil) }
    if let string = runtimeStringFromRaw(raw) { return string }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          runtimeIsObjectPointer(pointer) else { return nil }
    if let box = tryCast(pointer, to: RuntimeBoolBox.self) { return box.value }
    if let box = tryCast(pointer, to: RuntimeIntBox.self) { return box.value }
    if let box = tryCast(pointer, to: RuntimeLongBox.self) { return box.value }
    if let box = tryCast(pointer, to: RuntimeULongBox.self) {
        // box.value holds the raw 64-bit pattern as Int; non-negative means
        // the ULong fits in Int64, negative means it exceeds Int64.max.
        return box.value >= 0 ? box.value : Double(UInt64(bitPattern: Int64(box.value)))
    }
    if let box = tryCast(pointer, to: RuntimeFloatBox.self) { return box.value }
    if let box = tryCast(pointer, to: RuntimeDoubleBox.self) { return box.value }
    if let box = tryCast(pointer, to: RuntimeCharBox.self) {
        return runtimeCharacterFromRaw(box.value)
    }
    if let list = runtimeListBox(from: raw) {
        var values: [Any] = []
        values.reserveCapacity(list.elements.count)
        for element in list.elements {
            // Nested null has no plist representation: modern CFPrefs
            // validation rejects NSNull and aborts the process, so the
            // whole value is reported unsupported and the setter throws.
            guard let converted = runtimeFoundationKotlinToPlist(element),
                  let value = converted else { return nil }
            values.append(value)
        }
        return values
    }
    if let map = runtimeMapBox(from: raw) {
        var dictionary: [String: Any] = [:]
        let keys = map.keyValues.map(\.legacyRawValue)
        let values = map.entryValues.map(\.legacyRawValue)
        for (keyRaw, valueRaw) in zip(keys, values) {
            guard let key = runtimeStringFromRaw(keyRaw),
                  let converted = runtimeFoundationKotlinToPlist(valueRaw),
                  let value = converted else { return nil }
            dictionary[key] = value
        }
        return dictionary
    }
    // A Kotlin NSObject facade (NSDate/NSData/NSURL/…) resolves to the real
    // Foundation object through its foreign-resource lease.
    if let object = runtimeForeignResourceForOwner(raw, as: NSObject.self) {
        return object
    }
    return nil
}

/// Property-list object -> Kotlin `Any?` raw. Foundation objects other than
/// the plist scalars/collections travel as tagged foreign-resource tokens;
/// `__foundation_object_probe`/`__wrapFoundation` unwrap them on the Kotlin
/// side.
private func runtimeFoundationPlistToKotlin(_ object: Any?) -> Int {
    guard let object else { return runtimeNullSentinelInt }
    if let string = object as? String { return runtimeMakeStringRaw(string) }
    if let number = object as? NSNumber {
        // CFBoolean is an NSNumber subclass; check the type ID first so
        // true/false do not surface as 1/0.
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return kk_box_bool(number.boolValue ? 1 : 0)
        }
        switch String(cString: number.objCType) {
        case "f":
            return kk_box_float(kk_float_to_bits(number.floatValue))
        case "d":
            return kk_box_double(kk_double_to_bits(number.doubleValue))
        case "Q":
            let unsigned = number.uint64Value
            return unsigned <= UInt64(Int64.max)
                ? kk_box_long(Int(truncatingIfNeeded: unsigned))
                : kk_box_double(kk_double_to_bits(Double(unsigned)))
        default:
            return kk_box_long(Int(number.int64Value))
        }
    }
    if let array = object as? [Any] {
        return runtimeMakeListRaw(array.map(runtimeFoundationPlistToKotlin))
    }
    if let dictionary = object as? [String: Any] {
        var keys: [Int] = []
        var values: [Int] = []
        keys.reserveCapacity(dictionary.count)
        values.reserveCapacity(dictionary.count)
        for (key, value) in dictionary {
            keys.append(runtimeMakeStringRaw(key))
            values.append(runtimeFoundationPlistToKotlin(value))
        }
        return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
    }
    // Plist null round-trips as Kotlin null rather than an opaque facade.
    if object is NSNull { return runtimeNullSentinelInt }
    if let object = object as? NSObject {
        return kk_box_long(runtimeFoundationTaggedToken(runtimeForeignResourceCreate(object)))
    }
    return runtimeNullSentinelInt
}

private func runtimeFoundationStringListRaw(_ strings: [String]) -> Int {
    runtimeMakeListRaw(strings.map(runtimeMakeStringRaw))
}

private func runtimeFoundationMapRaw(_ dictionary: [String: Any]?) -> Int {
    guard let dictionary else { return runtimeNullSentinelInt }
    var keys: [Int] = []
    var values: [Int] = []
    keys.reserveCapacity(dictionary.count)
    values.reserveCapacity(dictionary.count)
    for (key, value) in dictionary {
        keys.append(runtimeMakeStringRaw(key))
        values.append(runtimeFoundationPlistToKotlin(value))
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

/// Kotlin `Map<Any?, Any?>` raw -> `[String: Any]` plist dictionary.
private func runtimeFoundationKotlinMapToPlist(_ raw: Int) -> [String: Any]? {
    guard let map = runtimeMapBox(from: raw) else { return nil }
    var dictionary: [String: Any] = [:]
    let keys = map.keyValues.map(\.legacyRawValue)
    let values = map.entryValues.map(\.legacyRawValue)
    for (keyRaw, valueRaw) in zip(keys, values) {
        guard let key = runtimeStringFromRaw(keyRaw),
              let converted = runtimeFoundationKotlinToPlist(valueRaw),
              let value = converted else { return nil }
        dictionary[key] = value
    }
    return dictionary
}
#endif

// MARK: - NSDate

@_cdecl("__kk_foundation_date_now")
public func __kk_foundation_date_now(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSDate())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_create_reference")
public func __kk_foundation_date_create_reference(_ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSDate(timeIntervalSinceReferenceDate: kk_bits_to_double(seconds)))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_create_since")
public func __kk_foundation_date_create_since(_ seconds: Int, _ since: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let since = runtimeFoundationCounterpartDate(since) else {
            try throwFoundationFailure("Invalid NSDate counterpart")
        }
        return runtimeForeignResourceCreate(NSDate(timeInterval: kk_bits_to_double(seconds), since: since))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// kind: 0 = timeIntervalSince1970, 1 = timeIntervalSinceNow,
/// 2 = timeIntervalSinceReferenceDate.
@_cdecl("__kk_foundation_date_interval")
public func __kk_foundation_date_interval(_ handle: Int, _ kind: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let date = runtimeFoundationNSDate(handle) else {
            try throwFoundationFailure("Invalid NSDate")
        }
        let interval: TimeInterval
        switch kind {
        case 0: interval = date.timeIntervalSince1970
        case 1: interval = date.timeIntervalSinceNow
        default: interval = date.timeIntervalSinceReferenceDate
        }
        return kk_double_to_bits(interval)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_add")
public func __kk_foundation_date_add(_ handle: Int, _ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let date = runtimeFoundationNSDate(handle) else {
            try throwFoundationFailure("Invalid NSDate")
        }
        return runtimeForeignResourceCreate(date.addingTimeInterval(kk_bits_to_double(seconds)) as NSDate)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// kind: 0 = earlierDate, 1 = laterDate.
@_cdecl("__kk_foundation_date_extreme")
public func __kk_foundation_date_extreme(_ handle: Int, _ other: Int, _ kind: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let date = runtimeFoundationNSDate(handle),
              let other = runtimeFoundationCounterpartDate(other) else {
            try throwFoundationFailure("Invalid NSDate operand")
        }
        let result = kind == 0 ? date.earlierDate(other) : date.laterDate(other)
        return runtimeForeignResourceCreate(result as NSDate)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_compare")
public func __kk_foundation_date_compare(_ handle: Int, _ other: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let date = runtimeFoundationNSDate(handle),
              let other = runtimeFoundationCounterpartDate(other) else {
            try throwFoundationFailure("Invalid NSDate operand")
        }
        return Int(date.compare(other).rawValue)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_is_equal")
public func __kk_foundation_date_is_equal(_ handle: Int, _ other: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let date = runtimeFoundationNSDate(handle) else {
            try throwFoundationFailure("Invalid NSDate receiver")
        }
        guard other != runtimeNullSentinelInt && other >= 0,
              let counterpart = runtimeFoundationCounterpartDate(other) else { return 0 }
        return date.isEqual(to: counterpart) ? 1 : 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_interval_since")
public func __kk_foundation_date_interval_since(_ handle: Int, _ other: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let date = runtimeFoundationNSDate(handle),
              let other = runtimeFoundationCounterpartDate(other) else {
            try throwFoundationFailure("Invalid NSDate operand")
        }
        return kk_double_to_bits(date.timeIntervalSince(other))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_description")
public func __kk_foundation_date_description(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let date = runtimeFoundationNSDate(handle) else {
            try throwFoundationFailure("Invalid NSDate")
        }
        return runtimeMakeStringRaw(date.description)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// kind: 0 = distantPast, 1 = distantFuture.
@_cdecl("__kk_foundation_date_distant")
public func __kk_foundation_date_distant(_ kind: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        let date = kind == 0 ? NSDate.distantPast : NSDate.distantFuture
        return runtimeForeignResourceCreate(date as NSDate)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_factory_since1970")
public func __kk_foundation_date_factory_since1970(_ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSDate(timeIntervalSince1970: kk_bits_to_double(seconds)))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_factory_since_now")
public func __kk_foundation_date_factory_since_now(_ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSDate(timeIntervalSinceNow: kk_bits_to_double(seconds)))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_factory_since")
public func __kk_foundation_date_factory_since(_ seconds: Int, _ since: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let since = runtimeFoundationCounterpartDate(since) else {
            try throwFoundationFailure("Invalid NSDate counterpart")
        }
        return runtimeForeignResourceCreate(NSDate(timeInterval: kk_bits_to_double(seconds), since: since))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

// MARK: - NSDateFormatter

@_cdecl("__kk_foundation_date_formatter_create")
public func __kk_foundation_date_formatter_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(DateFormatter())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_date_format")
public func __kk_foundation_date_formatter_date_format(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        // The Swift overlay vends "" for an unset dateFormat where the ObjC
        // property reports nil; collapse empty to the Kotlin null.
        guard let format = formatter.dateFormat, !format.isEmpty else {
            return runtimeNullSentinelInt
        }
        return runtimeMakeStringRaw(format)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_set_date_format")
public func __kk_foundation_date_formatter_set_date_format(_ handle: Int, _ format: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        formatter.dateFormat = runtimeStringFromRaw(format)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// kind: 0 = dateStyle, 1 = timeStyle, 2 = formatterBehavior.
@_cdecl("__kk_foundation_date_formatter_style")
public func __kk_foundation_date_formatter_style(_ handle: Int, _ kind: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        switch kind {
        case 0: return Int(formatter.dateStyle.rawValue)
        case 1: return Int(formatter.timeStyle.rawValue)
        default: return Int(formatter.formatterBehavior.rawValue)
        }
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// DateFormatter.Style/Behavior rawValue is UInt on the modern SDK overlays.
private func runtimeFoundationFormatterStyleRaw(_ raw: Int) -> UInt {
    UInt(truncatingIfNeeded: raw)
}

@_cdecl("__kk_foundation_date_formatter_set_style")
public func __kk_foundation_date_formatter_set_style(_ handle: Int, _ kind: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        let styleRaw = runtimeFoundationFormatterStyleRaw(value)
        switch kind {
        case 0:
            if let style = DateFormatter.Style(rawValue: styleRaw) { formatter.dateStyle = style }
        case 1:
            if let style = DateFormatter.Style(rawValue: styleRaw) { formatter.timeStyle = style }
        default:
            if let behavior = DateFormatter.Behavior(rawValue: styleRaw) { formatter.formatterBehavior = behavior }
        }
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// kind: 0 = isLenient.
@_cdecl("__kk_foundation_date_formatter_bool")
public func __kk_foundation_date_formatter_bool(_ handle: Int, _ kind: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        return formatter.isLenient ? 1 : 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_set_bool")
public func __kk_foundation_date_formatter_set_bool(_ handle: Int, _ kind: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        formatter.isLenient = value != 0
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// kind: 0 = locale (NSLocale token), 1 = timeZone (NSTimeZone token).
/// Untagged tokens: the Kotlin side knows the static type, so no plist
/// integer can be confused with the result.
@_cdecl("__kk_foundation_date_formatter_object")
public func __kk_foundation_date_formatter_object(_ handle: Int, _ kind: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        switch kind {
        case 0:
            guard let locale = formatter.locale else { return runtimeNullSentinelInt }
            return kk_box_long(runtimeForeignResourceCreate(locale as NSLocale))
        case 1:
            guard let timeZone = formatter.timeZone else { return runtimeNullSentinelInt }
            return kk_box_long(runtimeForeignResourceCreate(timeZone as NSTimeZone))
        default:
            return runtimeNullSentinelInt
        }
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_set_object")
public func __kk_foundation_date_formatter_set_object(_ handle: Int, _ kind: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle) else {
            try throwFoundationFailure("Invalid NSDateFormatter")
        }
        switch kind {
        case 0:
            if value == runtimeNullSentinelInt || value < 0 {
                formatter.locale = nil
            } else if let locale = runtimeForeignResource(value, as: NSLocale.self) {
                formatter.locale = Locale(identifier: locale.localeIdentifier)
            } else {
                try throwFoundationFailure("Invalid NSDateFormatter locale")
            }
        case 1:
            if value == runtimeNullSentinelInt || value < 0 {
                formatter.timeZone = nil
            } else if let zone = runtimeForeignResource(value, as: NSTimeZone.self) {
                formatter.timeZone = TimeZone(identifier: zone.name)
                    ?? TimeZone(secondsFromGMT: zone.secondsFromGMT)
            } else {
                try throwFoundationFailure("Invalid NSDateFormatter time zone")
            }
        default:
            try throwFoundationFailure("Unknown NSDateFormatter object property")
        }
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_string_from_date")
public func __kk_foundation_date_formatter_string_from_date(_ handle: Int, _ date: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle),
              let counterpart = runtimeFoundationCounterpartDate(date) else {
            try throwFoundationFailure("Invalid NSDateFormatter stringFromDate")
        }
        return runtimeMakeStringRaw(formatter.string(from: counterpart))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_date_from_string")
public func __kk_foundation_date_formatter_date_from_string(_ handle: Int, _ string: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let formatter = runtimeFoundationDateFormatter(handle),
              let text = runtimeStringFromRaw(string) else {
            try throwFoundationFailure("Invalid NSDateFormatter dateFromString")
        }
        guard let date = formatter.date(from: text) else { return runtimeNullSentinelInt }
        return kk_box_long(runtimeForeignResourceCreate(date as NSDate))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_localized_string")
public func __kk_foundation_date_formatter_localized_string(_ date: Int, _ dateStyle: Int, _ timeStyle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let counterpart = runtimeFoundationCounterpartDate(date) else {
            try throwFoundationFailure("Invalid NSDate for localized formatting")
        }
        let rendered = DateFormatter.localizedString(
            from: counterpart,
            dateStyle: DateFormatter.Style(rawValue: runtimeFoundationFormatterStyleRaw(dateStyle)) ?? .medium,
            timeStyle: DateFormatter.Style(rawValue: runtimeFoundationFormatterStyleRaw(timeStyle)) ?? .short
        )
        return runtimeMakeStringRaw(rendered)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_date_formatter_format_from_template")
public func __kk_foundation_date_formatter_format_from_template(_ template: Int, _ options: Int, _ locale: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let template = runtimeStringFromRaw(template) else {
            try throwFoundationFailure("Invalid date format template")
        }
        let localeObject: Locale?
        if locale == runtimeNullSentinelInt || locale < 0 {
            localeObject = nil
        } else if let nsLocale = runtimeForeignResource(locale, as: NSLocale.self) {
            localeObject = Locale(identifier: nsLocale.localeIdentifier)
        } else {
            try throwFoundationFailure("Invalid template locale")
        }
        guard let format = DateFormatter.dateFormat(fromTemplate: template, options: options, locale: localeObject) else {
            return runtimeNullSentinelInt
        }
        return runtimeMakeStringRaw(format)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

// MARK: - NSTimeZone

@_cdecl("__kk_foundation_timezone_create_name")
public func __kk_foundation_timezone_create_name(_ name: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let name = runtimeStringFromRaw(name), let zone = NSTimeZone(name: name) else {
            try throwFoundationFailure("Unknown NSTimeZone name")
        }
        return runtimeForeignResourceCreate(zone)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_name")
public func __kk_foundation_timezone_name(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let zone = runtimeFoundationTimeZone(handle) else {
            try throwFoundationFailure("Invalid NSTimeZone")
        }
        return runtimeMakeStringRaw(zone.name)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_abbreviation")
public func __kk_foundation_timezone_abbreviation(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let zone = runtimeFoundationTimeZone(handle) else {
            try throwFoundationFailure("Invalid NSTimeZone")
        }
        // NSTimeZone exposes no no-argument abbreviation in Swift; the
        // date-parameterized form at the current date is the same value KN's
        // `abbreviation` property reports.
        return zone.abbreviation(for: Date()).map(runtimeMakeStringRaw) ?? runtimeNullSentinelInt
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_seconds_from_gmt")
public func __kk_foundation_timezone_seconds_from_gmt(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let zone = runtimeFoundationTimeZone(handle) else {
            try throwFoundationFailure("Invalid NSTimeZone")
        }
        return zone.secondsFromGMT
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_seconds_from_gmt_for_date")
public func __kk_foundation_timezone_seconds_from_gmt_for_date(_ handle: Int, _ date: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let zone = runtimeFoundationTimeZone(handle),
              let counterpart = runtimeFoundationCounterpartDate(date) else {
            try throwFoundationFailure("Invalid NSTimeZone/date operand")
        }
        return zone.secondsFromGMT(for: counterpart)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_abbreviation_for_date")
public func __kk_foundation_timezone_abbreviation_for_date(_ handle: Int, _ date: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let zone = runtimeFoundationTimeZone(handle),
              let counterpart = runtimeFoundationCounterpartDate(date) else {
            try throwFoundationFailure("Invalid NSTimeZone/date operand")
        }
        return zone.abbreviation(for: counterpart).map(runtimeMakeStringRaw) ?? runtimeNullSentinelInt
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_is_equal")
public func __kk_foundation_timezone_is_equal(_ handle: Int, _ other: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let zone = runtimeFoundationTimeZone(handle),
              let other = runtimeFoundationTimeZone(other) else {
            try throwFoundationFailure("Invalid NSTimeZone operand")
        }
        return zone.isEqual(other) ? 1 : 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_local")
public func __kk_foundation_timezone_local(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        // NSTimeZone.local/system vend the TimeZone struct overlay; `as
        // NSTimeZone` performs the toll-free bridge to the class cluster object.
        return runtimeForeignResourceCreate(NSTimeZone.local as NSTimeZone)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_system")
public func __kk_foundation_timezone_system(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSTimeZone.system as NSTimeZone)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_with_name")
public func __kk_foundation_timezone_with_name(_ name: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let name = runtimeStringFromRaw(name) else {
            try throwFoundationFailure("Invalid NSTimeZone name")
        }
        guard let zone = NSTimeZone(name: name) else { return runtimeNullSentinelInt }
        return kk_box_long(runtimeForeignResourceCreate(zone))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_with_abbreviation")
public func __kk_foundation_timezone_with_abbreviation(_ abbreviation: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let abbreviation = runtimeStringFromRaw(abbreviation) else {
            try throwFoundationFailure("Invalid NSTimeZone abbreviation")
        }
        guard let zone = NSTimeZone(abbreviation: abbreviation) else { return runtimeNullSentinelInt }
        return kk_box_long(runtimeForeignResourceCreate(zone))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_timezone_for_seconds_from_gmt")
public func __kk_foundation_timezone_for_seconds_from_gmt(_ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        // init(forSecondsFromGMT:) is non-failable on the modern SDK.
        return runtimeForeignResourceCreate(NSTimeZone(forSecondsFromGMT: seconds))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

// MARK: - NSLocale

@_cdecl("__kk_foundation_locale_create_identifier")
public func __kk_foundation_locale_create_identifier(_ identifier: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let identifier = runtimeStringFromRaw(identifier) else {
            try throwFoundationFailure("Invalid NSLocale identifier")
        }
        return runtimeForeignResourceCreate(NSLocale(localeIdentifier: identifier))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_locale_identifier")
public func __kk_foundation_locale_identifier(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let locale = runtimeFoundationLocale(handle) else {
            try throwFoundationFailure("Invalid NSLocale")
        }
        return runtimeMakeStringRaw(locale.localeIdentifier)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_locale_language_code")
public func __kk_foundation_locale_language_code(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let locale = runtimeFoundationLocale(handle) else {
            try throwFoundationFailure("Invalid NSLocale")
        }
        // NSLocale.languageCode is nonnull on the modern SDK (empty string when
        // absent); countryCode stays optional.
        return runtimeMakeStringRaw(locale.languageCode)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_locale_country_code")
public func __kk_foundation_locale_country_code(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let locale = runtimeFoundationLocale(handle) else {
            try throwFoundationFailure("Invalid NSLocale")
        }
        return locale.countryCode.map(runtimeMakeStringRaw) ?? runtimeNullSentinelInt
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_locale_current")
public func __kk_foundation_locale_current(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        // NSLocale.current/autoupdatingCurrent vend the Locale struct overlay;
        // `as NSLocale` performs the same toll-free bridge Date uses for NSDate.
        return runtimeForeignResourceCreate(NSLocale.current as NSLocale)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_locale_autoupdating")
public func __kk_foundation_locale_autoupdating(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSLocale.autoupdatingCurrent as NSLocale)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_locale_with_identifier")
public func __kk_foundation_locale_with_identifier(_ identifier: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let identifier = runtimeStringFromRaw(identifier) else {
            try throwFoundationFailure("Invalid NSLocale identifier")
        }
        return runtimeForeignResourceCreate(NSLocale(localeIdentifier: identifier))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

// MARK: - NSUserDefaults

@_cdecl("__kk_foundation_defaults_standard")
public func __kk_foundation_defaults_standard(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(UserDefaults.standard)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_create_suite")
public func __kk_foundation_defaults_create_suite(_ suiteName: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let suiteName = runtimeStringFromRaw(suiteName),
              let defaults = UserDefaults(suiteName: suiteName) else {
            try throwFoundationFailure("Cannot create NSUserDefaults suite")
        }
        return runtimeForeignResourceCreate(defaults)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_object_for_key")
public func __kk_foundation_defaults_object_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        return runtimeFoundationPlistToKotlin(defaults.object(forKey: key))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_string_for_key")
public func __kk_foundation_defaults_string_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        return defaults.string(forKey: key).map(runtimeMakeStringRaw) ?? runtimeNullSentinelInt
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_bool_for_key")
public func __kk_foundation_defaults_bool_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        return defaults.bool(forKey: key) ? 1 : 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_integer_for_key")
public func __kk_foundation_defaults_integer_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        return defaults.integer(forKey: key)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_double_for_key")
public func __kk_foundation_defaults_double_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        return kk_double_to_bits(defaults.double(forKey: key))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_float_for_key")
public func __kk_foundation_defaults_float_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        return kk_float_to_bits(defaults.float(forKey: key))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_set_object")
public func __kk_foundation_defaults_set_object(_ handle: Int, _ value: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        guard let converted = runtimeFoundationKotlinToPlist(value) else {
            try throwFoundationFailure("NSUserDefaults value is not a property-list object")
        }
        if let plist = converted {
            defaults.set(plist, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_set_bool")
public func __kk_foundation_defaults_set_bool(_ handle: Int, _ value: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        defaults.set(value != 0, forKey: key)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_set_integer")
public func __kk_foundation_defaults_set_integer(_ handle: Int, _ value: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        defaults.set(value, forKey: key)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_set_double")
public func __kk_foundation_defaults_set_double(_ handle: Int, _ value: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        defaults.set(kk_bits_to_double(value), forKey: key)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_set_float")
public func __kk_foundation_defaults_set_float(_ handle: Int, _ value: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        defaults.set(kk_bits_to_float(value), forKey: key)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_remove_object_for_key")
public func __kk_foundation_defaults_remove_object_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        defaults.removeObject(forKey: key)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_synchronize")
public func __kk_foundation_defaults_synchronize(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle) else {
            try throwFoundationFailure("Invalid NSUserDefaults")
        }
        return defaults.synchronize() ? 1 : 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_dictionary_representation")
public func __kk_foundation_defaults_dictionary_representation(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle) else {
            try throwFoundationFailure("Invalid NSUserDefaults")
        }
        return runtimeFoundationMapRaw(defaults.dictionaryRepresentation())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_persistent_domain_for_name")
public func __kk_foundation_defaults_persistent_domain_for_name(_ handle: Int, _ name: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let name = runtimeStringFromRaw(name) else {
            try throwFoundationFailure("Invalid NSUserDefaults/domain")
        }
        return runtimeFoundationMapRaw(defaults.persistentDomain(forName: name))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_set_persistent_domain")
public func __kk_foundation_defaults_set_persistent_domain(_ handle: Int, _ domain: Int, _ name: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let name = runtimeStringFromRaw(name),
              let dictionary = runtimeFoundationKotlinMapToPlist(domain) else {
            try throwFoundationFailure("Invalid NSUserDefaults persistent domain")
        }
        defaults.setPersistentDomain(dictionary, forName: name)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_remove_persistent_domain_for_name")
public func __kk_foundation_defaults_remove_persistent_domain_for_name(_ handle: Int, _ name: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let name = runtimeStringFromRaw(name) else {
            try throwFoundationFailure("Invalid NSUserDefaults/domain")
        }
        defaults.removePersistentDomain(forName: name)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_register_defaults")
public func __kk_foundation_defaults_register_defaults(_ handle: Int, _ domain: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let dictionary = runtimeFoundationKotlinMapToPlist(domain) else {
            try throwFoundationFailure("Invalid NSUserDefaults registration dictionary")
        }
        defaults.register(defaults: dictionary)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_volatile_domain_names")
public func __kk_foundation_defaults_volatile_domain_names(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard runtimeFoundationUserDefaults(handle) != nil else {
            try throwFoundationFailure("Invalid NSUserDefaults")
        }
        // volatileDomainNames/persistentDomainNames are API_DEPRECATED and
        // unavailable to Swift on modern macOS; there is no supported way to
        // enumerate domains, so report an empty list like an empty suite.
        return runtimeMakeListRaw([])
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_persistent_domain_names")
public func __kk_foundation_defaults_persistent_domain_names(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard runtimeFoundationUserDefaults(handle) != nil else {
            try throwFoundationFailure("Invalid NSUserDefaults")
        }
        return runtimeMakeListRaw([])
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_defaults_object_is_forced_for_key")
public func __kk_foundation_defaults_object_is_forced_for_key(_ handle: Int, _ key: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let defaults = runtimeFoundationUserDefaults(handle),
              let key = runtimeStringFromRaw(key) else {
            try throwFoundationFailure("Invalid NSUserDefaults/key")
        }
        return defaults.objectIsForced(forKey: key) ? 1 : 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

// MARK: - NSUUID

@_cdecl("__kk_foundation_uuid_create")
public func __kk_foundation_uuid_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSUUID())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_uuid_string")
public func __kk_foundation_uuid_string(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let uuid = runtimeFoundationUUID(handle) else {
            try throwFoundationFailure("Invalid NSUUID")
        }
        return runtimeMakeStringRaw(uuid.uuidString)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

// MARK: - NSThread conveniences

@_cdecl("__kk_foundation_thread_callstack")
public func __kk_foundation_thread_callstack(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeFoundationStringListRaw(Thread.callStackSymbols)
        #else
        return runtimeMakeListRaw([])
        #endif
    }
}

@_cdecl("__kk_foundation_thread_is_main")
public func __kk_foundation_thread_is_main(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return Thread.isMainThread ? 1 : 0
        #else
        return Thread.isMainThread ? 1 : 0
        #endif
    }
}

@_cdecl("__kk_foundation_thread_sleep")
public func __kk_foundation_thread_sleep(_ seconds: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        Thread.sleep(forTimeInterval: kk_bits_to_double(seconds))
        return 0
        #else
        Thread.sleep(forTimeInterval: kk_bits_to_double(seconds))
        return 0
        #endif
    }
}

// MARK: - NSLog

/// Renders one NSLog vararg for the `%@`/`%s` family. Foundation objects
/// stored behind Kotlin facades render through their real `description`;
/// everything else uses the shared Any printer so strings, numbers, lists and
/// maps match `println` output.
private func runtimeFoundationNSLogObject(_ raw: Int) -> String {
    if raw == runtimeNullSentinelInt { return "null" }
    if let object = runtimeForeignResourceForOwner(raw, as: NSObject.self) {
        return object.description
    }
    return runtimeRenderAnyForPrint(raw)
}

private func runtimeFoundationNSLogString(_ raw: Int) -> String {
    if let string = runtimeStringFromRaw(raw) { return string }
    return runtimeFoundationNSLogObject(raw)
}

/// Integer argument for `%d`-family conversions; unboxes every integral
/// Kotlin box and treats null/missing as 0 like printf does for nil objects.
private func runtimeFoundationNSLogInteger(_ raw: Int) -> Int64 {
    guard raw != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          runtimeIsObjectPointer(pointer) else { return 0 }
    if let box = tryCast(pointer, to: RuntimeBoolBox.self) { return box.value ? 1 : 0 }
    if let box = tryCast(pointer, to: RuntimeIntBox.self) { return Int64(box.value) }
    if let box = tryCast(pointer, to: RuntimeLongBox.self) { return Int64(box.value) }
    if let box = tryCast(pointer, to: RuntimeULongBox.self) { return Int64(box.value) }
    if let box = tryCast(pointer, to: RuntimeCharBox.self) { return Int64(box.value) }
    if let box = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return box.value.isFinite ? Int64(box.value) : (box.value < 0 ? Int64.min : Int64.max)
    }
    if let box = tryCast(pointer, to: RuntimeFloatBox.self) {
        return box.value.isFinite ? Int64(box.value) : (box.value < 0 ? Int64.min : Int64.max)
    }
    return 0
}

private func runtimeFoundationNSLogDouble(_ raw: Int) -> Double {
    guard raw != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          runtimeIsObjectPointer(pointer) else { return 0 }
    if let box = tryCast(pointer, to: RuntimeDoubleBox.self) { return box.value }
    if let box = tryCast(pointer, to: RuntimeFloatBox.self) { return Double(box.value) }
    if let box = tryCast(pointer, to: RuntimeLongBox.self) { return Double(box.value) }
    if let box = tryCast(pointer, to: RuntimeIntBox.self) { return Double(box.value) }
    if let box = tryCast(pointer, to: RuntimeBoolBox.self) { return box.value ? 1 : 0 }
    return 0
}

private func runtimeFoundationNSLogUnichar(_ raw: Int) -> unichar {
    guard raw != runtimeNullSentinelInt else { return 0 }
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw),
       runtimeIsObjectPointer(pointer),
       let box = tryCast(pointer, to: RuntimeCharBox.self) {
        return unichar(box.value)
    }
    return unichar(runtimeFoundationNSLogInteger(raw))
}

/// Parses one printf conversion starting at `index` (which points at '%')
/// and appends the rendered argument to `output`. Returns the index just
/// past the conversion, or nil when the spec is unsupported/truncated.
private func runtimeFoundationNSLogRenderSpec(
    _ format: String, from start: String.Index, arguments: [Int], nextArgument: inout Int,
    output: inout String
) -> String.Index? {
    var index = format.index(after: start)
    guard index < format.endIndex else { return nil }
    // Flags.
    while index < format.endIndex {
        let c = format[index]
        guard c == "-" || c == "+" || c == " " || c == "#" || c == "0" else { break }
        index = format.index(after: index)
    }
    // Field width.
    while index < format.endIndex, format[index].isNumber {
        index = format.index(after: index)
    }
    // Precision.
    if index < format.endIndex, format[index] == "." {
        index = format.index(after: index)
        while index < format.endIndex, format[index].isNumber {
            index = format.index(after: index)
        }
    }
    // Length modifiers are advisory; the Kotlin-side values are already
    // boxed, so only the conversion family matters.
    while index < format.endIndex {
        let c = format[index]
        guard c == "h" || c == "l" || c == "L" || c == "j" || c == "z" || c == "t" || c == "q" else { break }
        index = format.index(after: index)
    }
    guard index < format.endIndex else { return nil }
    let conversion = format[index]
    index = format.index(after: index)
    // '%%' emits a literal percent and never consumes a vararg.
    if conversion == "%" {
        output.append("%")
        return index
    }
    let raw = nextArgument < arguments.count ? arguments[nextArgument] : runtimeNullSentinelInt
    nextArgument += 1
    switch conversion {
    case "d", "i":
        output.append(String(runtimeFoundationNSLogInteger(raw)))
    case "u":
        output.append(String(UInt64(bitPattern: runtimeFoundationNSLogInteger(raw))))
    case "o":
        output.append(String(runtimeFoundationNSLogInteger(raw), radix: 8))
    case "x", "X":
        let digits = String(runtimeFoundationNSLogInteger(raw), radix: 16)
        output.append(conversion == "X" ? digits.uppercased() : digits)
    case "f", "F", "e", "E", "g", "G", "a", "A":
        let value = runtimeFoundationNSLogDouble(raw)
        let spec = "%\(conversion)"
        output.append(String(format: spec, value))
    case "c":
        output.append(runtimeCharacterFromRaw(Int(runtimeFoundationNSLogUnichar(raw))))
    case "C":
        if let scalar = UnicodeScalar(runtimeFoundationNSLogUnichar(raw)) {
            output.append(Character(scalar))
        }
    case "s", "S":
        output.append(runtimeFoundationNSLogString(raw))
    case "p":
        output.append(String(format: "%p", raw))
    case "@":
        output.append(runtimeFoundationNSLogObject(raw))
    default:
        // Unknown conversion: emit it literally rather than dropping input.
        output.append("%")
        output.append(conversion)
        nextArgument -= 1
    }
    return index
}

@_cdecl("__kk_foundation_nslog")
public func __kk_foundation_nslog(_ format: Int, _ arguments: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let format = runtimeStringFromRaw(format) else {
            try throwFoundationFailure("Invalid NSLog format")
        }
        let argumentRaws = runtimeArrayBox(from: arguments)?.elements ?? []
        var output = ""
        output.reserveCapacity(format.utf8.count + 32)
        var index = format.startIndex
        var nextArgument = 0
        while index < format.endIndex {
            if format[index] != "%" {
                output.append(format[index])
                index = format.index(after: index)
                continue
            }
            guard let next = runtimeFoundationNSLogRenderSpec(
                format, from: index, arguments: argumentRaws, nextArgument: &nextArgument, output: &output
            ) else {
                // Truncated spec at end of format: emit the '%' literally.
                output.append("%")
                index = format.index(after: index)
                continue
            }
            index = next
        }
        // NSLog prepends timestamp/pid like the real SDK; %@ keeps the expanded
        // text opaque so embedded '%' characters are never reinterpreted.
        NSLog("%@", output as NSString)
        return 0
        #else
        return 0
        #endif
    }
}

// MARK: - NSObject description / foreign-token probe

@_cdecl("__kk_foundation_object_description")
public func __kk_foundation_object_description(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let object = runtimeForeignResource(handle, as: NSObject.self) else {
            try throwFoundationFailure("Invalid NSObject handle")
        }
        return runtimeMakeStringRaw(object.description)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// Probes whether an `Any?` value is a tagged foreign-resource token and, if
/// so, returns the bare token for `__wrapFoundation`. Returns -1 for every
/// other value (genuine Longs, strings, collections, null).
@_cdecl("__kk_foundation_object_probe")
public func __kk_foundation_object_probe(_ raw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: -1) {
        #if canImport(Darwin)
        guard raw != runtimeNullSentinelInt,
              let pointer = UnsafeMutableRawPointer(bitPattern: raw),
              runtimeIsObjectPointer(pointer),
              let box = tryCast(pointer, to: RuntimeLongBox.self),
              let token = runtimeFoundationUntagToken(box.value),
              runtimeForeignResource(token, as: NSObject.self) != nil else {
            return -1
        }
        return token
        #else
        return -1
        #endif
    }
}
