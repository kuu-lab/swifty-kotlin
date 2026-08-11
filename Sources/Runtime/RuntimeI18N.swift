import Foundation

final class RuntimeLocaleBox {
    let identifier: String
    let language: String
    let country: String
    let variant: String
    let locale: Locale

    init(identifier: String, language: String, country: String, variant: String, locale: Locale) {
        self.identifier = identifier
        self.language = language
        self.country = country
        self.variant = variant
        self.locale = locale
    }
}

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
/// Used wherever locale identifiers are processed in the runtime (I18N, DateFormat, etc.).
func normalizeLocaleIdentifier(_ identifier: String) -> String {
    identifier.replacingOccurrences(of: "_", with: "-")
}

private func parseLocaleComponents(_ identifier: String) -> (language: String, country: String, variant: String) {
    let normalized = normalizeLocaleIdentifier(identifier)
    let separators = CharacterSet(charactersIn: "-@")
    let rawParts = normalized
        .components(separatedBy: separators)
        .flatMap { $0.components(separatedBy: "_") }
        .filter { !$0.isEmpty }

    let language = rawParts.indices.contains(0) ? rawParts[0].lowercased() : ""
    let country = rawParts.indices.contains(1) ? rawParts[1].uppercased() : ""
    let variant = rawParts.count > 2 ? rawParts.dropFirst(2).joined(separator: "_") : ""
    return (language, country, variant)
}

private func localeIdentifier(language: String, country: String, variant: String) -> String {
    var parts: [String] = []
    if !language.isEmpty { parts.append(language.lowercased()) }
    if !country.isEmpty { parts.append(country.uppercased()) }
    if !variant.isEmpty { parts.append(variant) }
    return parts.joined(separator: "-")
}

private func makeRuntimeLocaleBox(identifier: String) -> RuntimeLocaleBox {
    let components = parseLocaleComponents(identifier)
    let canonicalIdentifier = localeIdentifier(
        language: components.language,
        country: components.country,
        variant: components.variant
    )
    let foundationIdentifier = canonicalIdentifier.isEmpty ? normalizeLocaleIdentifier(identifier) : canonicalIdentifier
    return RuntimeLocaleBox(
        identifier: canonicalIdentifier.isEmpty ? foundationIdentifier : canonicalIdentifier,
        language: components.language,
        country: components.country,
        variant: components.variant,
        locale: Locale(identifier: foundationIdentifier)
    )
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
    makeRuntimeLocaleBox(identifier: localeIdentifier(language: language, country: country, variant: ""))
}

@_cdecl("kk_locale_new_flat")
public func kk_locale_new_flat(
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
    return registerRuntimeObject(makeRuntimeLocaleBox(languageOnly: identifier))
}

@_cdecl("kk_locale_new_language_country_flat")
public func kk_locale_new_language_country_flat(
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
    return registerRuntimeObject(makeRuntimeLocaleBox(language: language, country: country))
}
