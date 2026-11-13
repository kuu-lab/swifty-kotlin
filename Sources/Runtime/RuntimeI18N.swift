import Foundation

#if canImport(Glibc)
import Glibc
#endif

// Locale constructors allocate runtime-owned boxes rather than nominal objects.
private let runtimeLocaleNominalTypeID = runtimeStableNominalTypeID(fqName: "java.util.Locale")

final class RuntimeLocaleBox {
    let identifier: String
    let language: String
    let country: String
    let variant: String
    let script: String
    let locale: Locale

    init(
        identifier: String,
        language: String,
        country: String,
        variant: String,
        script: String = "",
        locale: Locale
    ) {
        self.identifier = identifier
        self.language = language
        self.country = country
        self.variant = variant
        self.script = script
        self.locale = locale
    }
}

private final class RuntimeLocaleDefaultState: @unchecked Sendable {
    private let lock = NSLock()
    private var override: RuntimeLocaleBox?

    func get() -> RuntimeLocaleBox? {
        lock.lock()
        defer { lock.unlock() }
        return override
    }

    func set(_ value: RuntimeLocaleBox?) {
        lock.lock()
        defer { lock.unlock() }
        override = value
    }
}

private let runtimeLocaleDefaultState = RuntimeLocaleDefaultState()

func runtimeLocaleBox(from raw: Int) -> RuntimeLocaleBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeLocaleBox.self)
}

private func i18nStringFromFlat(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> String {
    runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
}

/// Normalizes a locale identifier from Kotlin/Java format (e.g. "en_US") to the IETF BCP 47
/// format expected by Apple APIs (e.g. "en-US") by replacing underscores with hyphens.
func normalizeLocaleIdentifier(_ identifier: String) -> String {
    identifier.replacingOccurrences(of: "_", with: "-")
}

private func localeIdentifier(language: String, country: String, variant: String) -> String {
    var parts: [String] = []
    if !language.isEmpty { parts.append(language.lowercased()) }
    if !country.isEmpty { parts.append(country.uppercased()) }
    if !variant.isEmpty { parts.append(variant) }
    return parts.joined(separator: "-")
}

private func makeRuntimeLocaleBox(languageOnly rawLanguage: String) -> RuntimeLocaleBox {
    let normalizedIdentifier = normalizeLocaleIdentifier(rawLanguage)
    return RuntimeLocaleBox(
        identifier: normalizedIdentifier,
        language: rawLanguage.lowercased(),
        country: "",
        variant: "",
        locale: Locale(identifier: normalizedIdentifier)
    )
}

private func makeRuntimeLocaleBox(language: String, country: String) -> RuntimeLocaleBox {
    let identifier = localeIdentifier(language: language, country: country, variant: "")
    // Preserve the constructor fields, including an empty language and literal separators.
    return RuntimeLocaleBox(
        identifier: identifier,
        language: language.lowercased(),
        country: country.uppercased(),
        variant: "",
        locale: Locale(identifier: identifier)
    )
}

private func makeRuntimeLocaleBox(languageTag: String) -> RuntimeLocaleBox {
    let identifier = normalizeLocaleIdentifier(languageTag)
    let subtags = identifier.split(separator: "-").map(String.init)
    guard let first = subtags.first else {
        return RuntimeLocaleBox(identifier: "", language: "", country: "", variant: "", locale: Locale(identifier: ""))
    }

    var language = first.lowercased()
    if language == "und" { language = "" }
    var country = ""
    var variantParts: [String] = []
    var script = ""
    for subtag in subtags.dropFirst() {
        if subtag.count == 1 { break }
        if script.isEmpty, subtag.count == 4, subtag.allSatisfy(\.isLetter) {
            script = subtag.prefix(1).uppercased() + subtag.dropFirst().lowercased()
        } else if country.isEmpty,
                  (subtag.count == 2 && subtag.allSatisfy(\.isLetter)) ||
                    (subtag.count == 3 && subtag.allSatisfy(\.isNumber)) {
            country = subtag.uppercased()
        } else {
            variantParts.append(subtag)
        }
    }

    return RuntimeLocaleBox(
        identifier: identifier,
        language: language,
        country: country,
        variant: variantParts.joined(separator: "_"),
        script: script,
        locale: Locale(identifier: identifier)
    )
}

private func makeRuntimeLocaleBox(locale: Locale) -> RuntimeLocaleBox {
    let language = locale.languageCode?.lowercased() ?? ""
    let country = locale.regionCode?.uppercased() ?? ""
    return RuntimeLocaleBox(
        identifier: normalizeLocaleIdentifier(locale.identifier),
        language: language,
        country: country,
        variant: "",
        locale: locale
    )
}

private final class RuntimeHostDefaultLocaleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: RuntimeLocaleBox?

    func get() -> RuntimeLocaleBox {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let resolved = runtimeHostDefaultLocaleBox()
        cached = resolved
        return resolved
    }
}

private let runtimeHostDefaultLocaleCache = RuntimeHostDefaultLocaleCache()

private func runtimeDefaultLocaleBox() -> RuntimeLocaleBox {
    runtimeLocaleDefaultState.get() ?? runtimeHostDefaultLocaleCache.get()
}

/// The default locale resolved like `java.util.Locale.getDefault()`, as a
/// Foundation locale. APIs whose locale-sensitive behavior must follow the
/// JDK default locale (e.g. Calendar week rules) use this instead of
/// `Locale.current`, which corelibs resolves differently for the C/POSIX
/// family (en_001 with Monday week start vs the JDK's en/en_US with Sunday).
func runtimeDefaultFoundationLocale() -> Locale {
    runtimeDefaultLocaleBox().locale
}

private func runtimeHostDefaultLocaleBox() -> RuntimeLocaleBox {
    #if os(Linux)
    if let locale = runtimeLinuxDefaultLocaleBox() {
        return locale
    }
    #endif
    return makeRuntimeLocaleBox(locale: Locale.current)
}

#if os(Linux)
/// Resolves the process default locale like the JDK's Unix `locale.cpp`:
/// `setlocale(LC_ALL, "")` applies the LC_ALL > LC_xxx > LANG environment
/// per category and validates it against installed locales, then the
/// LC_MESSAGES name feeds the same `ParseLocale` remap — an exact
/// "C"/"POSIX" becomes en_US, while a codeset- or modifier-suffixed name
/// ("C.UTF-8") becomes a bare "en" because `language_names` maps C/POSIX
/// to en with no country. Returns nil for ordinary locales, which
/// corelibs' `Locale.current` already resolves like the JDK — except that
/// it falls back to en_GB for the C/POSIX family, diverging from the JVM's
/// en/en_US (currency "¤" vs "£", US vs UK date patterns). The C locale is
/// restored immediately; only the resolved name is needed.
private func runtimeLinuxDefaultLocaleBox() -> RuntimeLocaleBox? {
    guard let savedPtr = setlocale(LC_ALL, nil) else { return nil }
    let saved = String(cString: savedPtr)
    _ = setlocale(LC_ALL, "")
    let resolved = setlocale(LC_MESSAGES, nil).map { String(cString: $0) } ?? "C"
    _ = saved.withCString { setlocale(LC_ALL, $0) }

    var name = resolved
    if let dot = name.firstIndex(of: ".") { name = String(name[..<dot]) }
    if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
    guard name == "C" || name == "POSIX" else { return nil }
    return name == resolved
        ? makeRuntimeLocaleBox(language: "en", country: "US")
        : makeRuntimeLocaleBox(language: "en", country: "")
}
#endif

func runtimeLocaleToString(_ box: RuntimeLocaleBox) -> String {
    var result = box.language
    if !box.country.isEmpty || (!box.language.isEmpty && !box.variant.isEmpty) {
        result += "_" + box.country
    }
    if !box.variant.isEmpty && (!box.language.isEmpty || !box.country.isEmpty) {
        result += "_" + box.variant
    }
    if !box.script.isEmpty {
        result += "_#" + box.script
    }
    return result
}

@_cdecl("__kk_locale_toString_flat")
public func __kk_locale_toString_flat(
    _ localeRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    guard let box = runtimeLocaleBox(from: localeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_locale_toString_flat received invalid Locale handle")
    }
    return runtimeRegisterFlatString(
        runtimeLocaleToString(box),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("__kk_locale_new_flat")
public func __kk_locale_new_flat(
    _ identifierData: UnsafePointer<UInt8>?,
    _ identifierLength: Int,
    _ identifierByteCount: Int,
    _ identifierHash: Int
) -> Int {
    let identifier = i18nStringFromFlat(
        data: identifierData,
        length: identifierLength,
        byteCount: identifierByteCount,
        hash: identifierHash
    )
    return registerRuntimeObject(
        makeRuntimeLocaleBox(languageOnly: identifier), typeID: runtimeLocaleNominalTypeID
    )
}

@_cdecl("__kk_locale_new_language_country_flat")
public func __kk_locale_new_language_country_flat(
    _ languageData: UnsafePointer<UInt8>?,
    _ languageLength: Int,
    _ languageByteCount: Int,
    _ languageHash: Int,
    _ countryData: UnsafePointer<UInt8>?,
    _ countryLength: Int,
    _ countryByteCount: Int,
    _ countryHash: Int
) -> Int {
    let language = i18nStringFromFlat(
        data: languageData,
        length: languageLength,
        byteCount: languageByteCount,
        hash: languageHash
    )
    let country = i18nStringFromFlat(
        data: countryData,
        length: countryLength,
        byteCount: countryByteCount,
        hash: countryHash
    )
    return registerRuntimeObject(
        makeRuntimeLocaleBox(language: language, country: country), typeID: runtimeLocaleNominalTypeID
    )
}

private func requiredRuntimeLocale(_ raw: Int, symbol: String) -> RuntimeLocaleBox {
    guard let box = runtimeLocaleBox(from: raw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(symbol) received invalid Locale handle")
    }
    return box
}

private func runtimeLocaleStringRaw(_ value: String) -> Int {
    runtimeMakeStringRaw(value)
}

private func runtimeLocaleDisplayLanguage(_ box: RuntimeLocaleBox, in displayLocale: RuntimeLocaleBox) -> String {
    guard !box.language.isEmpty else { return "" }
    return displayLocale.locale.localizedString(forLanguageCode: box.language) ?? box.language
}

private func runtimeLocaleDisplayCountry(_ box: RuntimeLocaleBox, in displayLocale: RuntimeLocaleBox) -> String {
    guard !box.country.isEmpty else { return "" }
    return displayLocale.locale.localizedString(forRegionCode: box.country) ?? box.country
}

private func runtimeLocaleDisplayName(_ box: RuntimeLocaleBox, in displayLocale: RuntimeLocaleBox) -> String {
    let language = runtimeLocaleDisplayLanguage(box, in: displayLocale)
    let country = runtimeLocaleDisplayCountry(box, in: displayLocale)
    var result: String
    if !language.isEmpty && !country.isEmpty {
        result = "\(language) (\(country))"
    } else {
        result = language.isEmpty ? country : language
    }
    if !box.variant.isEmpty {
        result += result.isEmpty ? box.variant : " (\(box.variant))"
    }
    if !box.script.isEmpty {
        let script = displayLocale.locale.localizedString(forScriptCode: box.script) ?? box.script
        result += result.isEmpty ? script : " (\(script))"
    }
    return result
}

@_cdecl("__kk_locale_get_default")
public func __kk_locale_get_default() -> Int {
    registerRuntimeObject(runtimeDefaultLocaleBox(), typeID: runtimeLocaleNominalTypeID)
}

@_cdecl("__kk_locale_set_default")
public func __kk_locale_set_default(_ localeRaw: Int) {
    runtimeLocaleDefaultState.set(requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_set_default"))
}

@_cdecl("__kk_locale_for_language_tag")
public func __kk_locale_for_language_tag(_ tagRaw: Int) -> Int {
    guard let languageTag = runtimeStringBox(fromRaw: tagRaw)?.value else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_locale_for_language_tag received invalid String handle")
    }
    return registerRuntimeObject(
        makeRuntimeLocaleBox(languageTag: languageTag),
        typeID: runtimeLocaleNominalTypeID
    )
}

@_cdecl("__kk_locale_get_language")
public func __kk_locale_get_language(_ localeRaw: Int) -> Int {
    runtimeLocaleStringRaw(requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_get_language").language)
}

@_cdecl("__kk_locale_get_country")
public func __kk_locale_get_country(_ localeRaw: Int) -> Int {
    runtimeLocaleStringRaw(requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_get_country").country)
}

@_cdecl("__kk_locale_get_variant")
public func __kk_locale_get_variant(_ localeRaw: Int) -> Int {
    runtimeLocaleStringRaw(requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_get_variant").variant)
}

@_cdecl("__kk_locale_get_display_name")
public func __kk_locale_get_display_name(_ localeRaw: Int, _ displayLocaleRaw: Int) -> Int {
    let locale = requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_get_display_name")
    let displayLocale = requiredRuntimeLocale(displayLocaleRaw, symbol: "__kk_locale_get_display_name")
    return runtimeLocaleStringRaw(runtimeLocaleDisplayName(locale, in: displayLocale))
}

@_cdecl("__kk_locale_get_display_language")
public func __kk_locale_get_display_language(_ localeRaw: Int, _ displayLocaleRaw: Int) -> Int {
    let locale = requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_get_display_language")
    let displayLocale = requiredRuntimeLocale(displayLocaleRaw, symbol: "__kk_locale_get_display_language")
    return runtimeLocaleStringRaw(runtimeLocaleDisplayLanguage(locale, in: displayLocale))
}

@_cdecl("__kk_locale_get_display_country")
public func __kk_locale_get_display_country(_ localeRaw: Int, _ displayLocaleRaw: Int) -> Int {
    let locale = requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_get_display_country")
    let displayLocale = requiredRuntimeLocale(displayLocaleRaw, symbol: "__kk_locale_get_display_country")
    return runtimeLocaleStringRaw(runtimeLocaleDisplayCountry(locale, in: displayLocale))
}

@_cdecl("__kk_locale_to_language_tag")
public func __kk_locale_to_language_tag(_ localeRaw: Int) -> Int {
    let locale = requiredRuntimeLocale(localeRaw, symbol: "__kk_locale_to_language_tag")
    return runtimeLocaleStringRaw(locale.identifier.replacingOccurrences(of: "_", with: "-"))
}
