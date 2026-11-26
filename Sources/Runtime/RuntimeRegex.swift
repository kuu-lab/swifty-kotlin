import Foundation


final class RuntimeRegexBox {
    let regex: NSRegularExpression
    let pattern: String
    let canonEq: Bool
    let optionOrdinals: Set<Int>

    private let cacheLock = NSLock()
    private var cachedAnchoredRegex: NSRegularExpression??
    private var cachedNamedGroupNames: [String]?

    init(regex: NSRegularExpression, pattern: String, canonEq: Bool = false, optionOrdinals: Set<Int> = []) {
        self.regex = regex
        self.pattern = pattern
        self.canonEq = canonEq
        self.optionOrdinals = optionOrdinals
    }

    /// Wrapping the effective compiled pattern makes alternation backtrack when an
    /// earlier branch only matches a prefix (for example, `a|ab` against `ab`).
    /// `.anchorsMatchLines` and `.ignoreMetacharacters` are stripped so the
    /// `\A` / `\z` wrapper always binds to the full string and is parsed as
    /// regex syntax rather than literal text. nil when the wrapped pattern fails
    /// to compile.
    var anchoredRegex: NSRegularExpression? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedAnchoredRegex { return cached }
        // `regex.pattern` is ICU-domain and may hold unpaired surrogates;
        // string interpolation would repair them to U+FFFD, so the wrapper is
        // assembled at the UTF-16 level instead.
        var wrappedUnits = runtimeKotlinStringUTF16CodeUnits("\\A(?:")
        wrappedUnits.append(contentsOf: regexUTF16Units(ofICUString: regex.pattern))
        wrappedUnits.append(contentsOf: runtimeKotlinStringUTF16CodeUnits(")\\z"))
        let effectivePattern = regexICUString(wrappedUnits)
        let anchoredOptions = regex.options.subtracting([.anchorsMatchLines, .ignoreMetacharacters])
        let compiled = try? NSRegularExpression(pattern: effectivePattern, options: anchoredOptions)
        cachedAnchoredRegex = .some(compiled)
        return compiled
    }

    var namedGroupNames: [String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedNamedGroupNames { return cached }
        let names = extractNamedGroupNames(from: pattern)
        cachedNamedGroupNames = names
        return names
    }

    /// **Limitation**: When `canonEq` is true, operations that return substrings
    /// of the input (replace, split, find, findAll, matchEntire) will operate on
    /// the NFC-normalized form. This means the returned strings may differ from
    /// the original input's Unicode representation (e.g., a decomposed sequence
    /// like U+0065 U+0301 becomes the precomposed U+00E9). Kotlin/JVM's
    /// `CANON_EQ` uses the ICU regex engine which matches canonically equivalent
    /// sequences without altering the input. A fully faithful implementation
    /// would require mapping match ranges back to the original string.
    func normalizeIfNeeded(_ str: String) -> String {
        canonEq ? str.precomposedStringWithCanonicalMapping : str
    }
}

private let runtimeMatchResultTypeID = runtimeStableNominalTypeID(fqName: "kotlin.text.MatchResult")

private func registerRuntimeMatchResult(_ match: RuntimeMatchResultBox) -> Int {
    registerRuntimeObject(match, typeID: runtimeMatchResultTypeID)
}

final class RuntimeMatchResultBox {
    let value: String
    let groupValues: [String]
    let groups: [RuntimeMatchGroupBox?]
    let namedGroups: [String: Int]
    let namedGroupNames: Set<String>
    let inputString: String?
    let inputUTF16Count: Int
    let matchEndOffset: Int
    weak var regexBox: RuntimeRegexBox?

    init(
        value: String,
        groupValues: [String],
        groups: [RuntimeMatchGroupBox?] = [],
        namedGroups: [String: Int] = [:],
        namedGroupNames: Set<String> = [],
        inputString: String? = nil,
        inputUTF16Count: Int? = nil,
        matchEndOffset: Int = 0,
        regexBox: RuntimeRegexBox? = nil
    ) {
        self.value = value
        self.groupValues = groupValues
        self.groups = groups
        self.namedGroups = namedGroups
        self.namedGroupNames = namedGroupNames
        self.inputString = inputString
        self.inputUTF16Count = inputUTF16Count ?? inputString?.utf16.count ?? 0
        self.matchEndOffset = matchEndOffset
        self.regexBox = regexBox
    }
}

final class RuntimeMatchGroupBox {
    let value: String
    let rangeStart: Int
    let rangeEnd: Int

    init(value: String, rangeStart: Int, rangeEnd: Int) {
        self.value = value
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}


private enum RegexNeverMatch {
    static let expression: NSRegularExpression = {
        guard let expression = try? NSRegularExpression(pattern: "(?!)", options: []) else {
            preconditionFailure("KSwiftK: static never-match regex (?!) failed to compile — Foundation/ICU broken")
        }
        return expression
    }()
}

/// Returns the Kotlin marker-encoded string unchanged: regex matching decodes
/// surrogate markers itself so isolated surrogates reach ICU as real UTF-16
/// code units instead of being repaired to U+FFFD up front (KUU-4319).
private func regexStringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return extractString(from: pointer)
}

private func regexStringFromFlat(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> String {
    _ = (length, hash)
    return runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
}

private func regexICUString(_ units: [UInt16]) -> String {
    let icuUnits = regexEncodeICUUnits(units).icuUnits
    guard !icuUnits.isEmpty else { return "" }
    return icuUnits.withUnsafeBufferPointer { buffer in
        NSString(characters: buffer.baseAddress!, length: buffer.count) as String
    }
}

/// ICU-domain encoding (KUU-4590): on Linux every NSString/String
/// construction path repairs unpaired UTF-16 surrogates to U+FFFD, so the
/// ICU subject and pattern cannot carry real surrogate units at all. Each
/// source unit is emitted either as itself or as an escape pair:
///
///   isolated surrogate u    -> (E800, E000 + (u - 0xD800))
///   scalar u in E000...E801 -> (E801, u)
///
/// After encoding no *bare* scalar in E000...E801 exists in the ICU string:
/// escape E800 only opens surrogate-marker pairs and E801 only opens
/// private-use/escape pairs, so pattern constructs translated to these
/// sequences never confuse pair members with ordinary units. `unitToIcu`
/// and `icuToUnit` map boundary offsets between the two domains so match
/// ranges can be reported in Kotlin UTF-16 offsets.
struct RegexICUEncodedUnits {
    var icuUnits: [UInt16]
    var icuToUnit: [Int]
    var unitToIcu: [Int]
}

func regexEncodeICUUnits(_ units: [UInt16]) -> RegexICUEncodedUnits {
    var icuUnits: [UInt16] = []
    var icuToUnit: [Int] = []
    var unitToIcu: [Int] = []
    icuUnits.reserveCapacity(units.count)
    icuToUnit.reserveCapacity(units.count + 1)
    unitToIcu.reserveCapacity(units.count + 1)
    var i = 0
    while i < units.count {
        let u = Int(units[i])
        unitToIcu.append(icuUnits.count)
        if (0xD800 ... 0xDBFF).contains(u), i + 1 < units.count,
           (0xDC00 ... 0xDFFF).contains(Int(units[i + 1])) {
            icuToUnit.append(i)
            icuUnits.append(UInt16(u))
            i += 1
            unitToIcu.append(icuUnits.count)
            icuToUnit.append(i)
            icuUnits.append(units[i])
            i += 1
            continue
        }
        if (0xD800 ... 0xDFFF).contains(u) {
            icuToUnit.append(i)
            icuUnits.append(0xE800)
            icuToUnit.append(i)
            icuUnits.append(UInt16(0xE000 + u - 0xD800))
            i += 1
            continue
        }
        if (0xE000 ... 0xE801).contains(u) {
            icuToUnit.append(i)
            icuUnits.append(0xE801)
            icuToUnit.append(i)
            icuUnits.append(UInt16(u))
            i += 1
            continue
        }
        icuToUnit.append(i)
        icuUnits.append(UInt16(u))
        i += 1
    }
    unitToIcu.append(icuUnits.count)
    icuToUnit.append(units.count)
    return RegexICUEncodedUnits(icuUnits: icuUnits, icuToUnit: icuToUnit, unitToIcu: unitToIcu)
}

func regexDecodeICUUnits(_ icuUnits: [UInt16]) -> [UInt16] {
    var units: [UInt16] = []
    units.reserveCapacity(icuUnits.count)
    var i = 0
    while i < icuUnits.count {
        let u = Int(icuUnits[i])
        if u == 0xE800, i + 1 < icuUnits.count,
           (0xE000 ... 0xE7FF).contains(Int(icuUnits[i + 1])) {
            units.append(UInt16(0xD800 + Int(icuUnits[i + 1]) - 0xE000))
            i += 2
            continue
        }
        if u == 0xE801, i + 1 < icuUnits.count,
           (0xE000 ... 0xE801).contains(Int(icuUnits[i + 1])) {
            units.append(icuUnits[i + 1])
            i += 2
            continue
        }
        units.append(UInt16(u))
        i += 1
    }
    return units
}

func regexUTF16Units(ofICUString value: String) -> [UInt16] {
    let nsString = value as NSString
    var units = [unichar](repeating: 0, count: nsString.length)
    nsString.getCharacters(&units, range: NSRange(location: 0, length: nsString.length))
    return regexDecodeICUUnits(units)
}

struct RegexSubject {
    let icu: String
    let icuUnits: [UInt16]
    let units: [UInt16]
    let icuToUnit: [Int]
    let unitToIcu: [Int]

    init(units: [UInt16]) {
        let encoded = regexEncodeICUUnits(units)
        self.units = units
        icuUnits = encoded.icuUnits
        icuToUnit = encoded.icuToUnit
        unitToIcu = encoded.unitToIcu
        icu = encoded.icuUnits.isEmpty ? "" : encoded.icuUnits.withUnsafeBufferPointer { buffer in
            NSString(characters: buffer.baseAddress!, length: buffer.count) as String
        }
    }

    init(encoded: String) {
        self.init(units: runtimeKotlinStringUTF16CodeUnits(encoded))
    }

    init(icuSubject icu: String) {
        let nsString = icu as NSString
        var rawUnits = [unichar](repeating: 0, count: nsString.length)
        nsString.getCharacters(&rawUnits, range: NSRange(location: 0, length: nsString.length))
        let decoded = regexDecodeICUUnits(rawUnits)
        let encoded = regexEncodeICUUnits(decoded)
        units = decoded
        icuUnits = encoded.icuUnits
        icuToUnit = encoded.icuToUnit
        unitToIcu = encoded.unitToIcu
        self.icu = icuUnits.isEmpty ? "" : icuUnits.withUnsafeBufferPointer { buffer in
            NSString(characters: buffer.baseAddress!, length: buffer.count) as String
        }
    }

    func unitRange(_ icuRange: NSRange) -> Range<Int>? {
        guard icuRange.location != NSNotFound, icuRange.location >= 0, icuRange.length >= 0,
              icuRange.location + icuRange.length <= icuUnits.count else { return nil }
        let start = icuToUnit[icuRange.location]
        var end = icuToUnit[icuRange.location + icuRange.length]
        if end < start { end = start }
        return start ..< end
    }

    func icuLocation(forUnitOffset offset: Int) -> Int {
        unitToIcu[offset]
    }
}

private func regexMakeListRaw(_ values: [Int]) -> Int {
    let box = RuntimeListBox(elements: values)
    return registerRuntimeObject(box)
}

private func regexMakeStringListRaw(_ values: [String]) -> Int {
    regexMakeListRaw(values.map(runtimeMakeStringRaw))
}

private func regexBoxFromRaw(_ raw: Int) -> RuntimeRegexBox? {
    guard raw != runtimeNullSentinelInt, raw != 0,
          let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeRegexBox.self)
}

private func matchResultBoxFromRaw(_ raw: Int) -> RuntimeMatchResultBox? {
    guard raw != runtimeNullSentinelInt, raw != 0,
          let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeMatchResultBox.self)
}

private enum RuntimeRegexCompileError: Error {
    case invalidPattern(String)
}

/// Kotlin's `Regex("")` is a legal pattern that matches the empty string at
/// every position. `NSRegularExpression` rejects an empty pattern string, so
/// the equivalent non-capturing empty group `(?:)` is compiled instead.
private func compileRegexPattern(_ pattern: String, options: NSRegularExpression.Options) throws -> NSRegularExpression {
    let source = pattern.isEmpty ? "(?:)" : pattern
    // KUU-4169: reject \p{...} property names java.util.regex would reject.
    // ICU resolves names case-insensitively and knows aliases and property
    // keys the JVM does not (`\p{lower}`, `\p{gc=lu}`, `\p{scx=Latn}`, ...),
    // so without this check those patterns compile where the JVM throws
    // PatternSyntaxException. The scan mirrors Pattern's inline-flag, group,
    // character-class and \Q...\E tracking; the initial COMMENTS / UNIX_LINES
    // state comes from the RegexOption-derived NSRegularExpression options.
    if let propertyError = jvmRegexPropertyError(
        source,
        commentsInitially: options.contains(.allowCommentsAndWhitespace),
        unixLinesInitially: options.contains(.useUnixLineSeparators)
    ) {
        throw RuntimeRegexCompileError.invalidPattern(propertyError)
    }
    let translated = translateJavaPatternForICU(
        source,
        dotMatchesLineSeparatorsInitially: options.contains(.dotMatchesLineSeparators),
        unixLinesInitially: options.contains(.useUnixLineSeparators)
    )
    let effective = translated.isEmpty ? "(?:)" : translated
    return try NSRegularExpression(pattern: regexICUString(runtimeKotlinStringUTF16CodeUnits(effective)), options: options)
}

/// `\b` / `\B` spelled out as lookarounds over a word class `W`. ICU's `\b`
/// consults its own Unicode word tables and its `\B` is not the exact
/// complement of its `\b`, so an explicit `(?<=[W])/(?=[W])` transition test is
/// the only way to reproduce the JVM's boundary positions (`\b` matches where
/// exactly one side is a word character; `\B` everywhere else). Non-capturing
/// groups keep the user's capture-group numbering intact.
private let asciiWordBoundaryPattern =
    "(?:(?<![a-zA-Z0-9_])(?=[a-zA-Z0-9_])|(?<=[a-zA-Z0-9_])(?![a-zA-Z0-9_]))"
private let asciiNonWordBoundaryPattern =
    "(?:(?<![a-zA-Z0-9_])(?![a-zA-Z0-9_])|(?<=[a-zA-Z0-9_])(?=[a-zA-Z0-9_]))"
private let unicodeWordBoundaryPattern =
    "(?:(?<!\\w)(?=\\w)|(?<=\\w)(?!\\w))"
private let unicodeNonWordBoundaryPattern =
    "(?:(?<!\\w)(?!\\w)|(?<=\\w)(?=\\w))"

/// Wraps a translator-emitted class/escape so it cannot match half of an
/// escape pair (KUU-4590): a negated class like `\\D` or `\\P{L}` must match
/// an isolated surrogate as ONE unit — bare negations would match the
/// `\\uE800`/`\\uE801` lead and the marker scalar separately, producing two
/// matches and double replacements. The rewrite is
/// `(?:[emission \\uE000-\\uE801 removed]|pair alternatives)`: scalars can
/// never appear bare in the encoded domain, and which pair arms apply follows
/// the JVM meaning of the class (surrogates match every negated class whose
/// positive does not contain them; marker scalars are handled the same way).
private func regexMarkerSpaceWrapEmission(_ emitted: String, negated: Bool) -> String {
    if emitted.hasPrefix("(?:") || emitted.hasPrefix("\\uE800") || emitted.hasPrefix("\\uE801") || emitted == "\\P{C}" {
        return emitted
    }
    let pairs = "|\\uE800[\\uE000-\\uE7FF]|\\uE801[\\uE000-\\uE801]"
    if emitted == "\\p{Any}" || emitted == "\\p{Assigned}" {
        return "(?:[\(emitted)--[\\uE000-\\uE801]]\(pairs))"
    }
    guard negated else { return emitted }
    if emitted == "\\P{Any}" { return emitted }
    if emitted == "\\P{Assigned}" { return "[\\P{Assigned}--[\\uE000-\\uE801]]" }
    if emitted.hasPrefix("[^"), emitted.hasSuffix("]") {
        return "(?:[^\(emitted.dropFirst(2).dropLast())\\uE000-\\uE801]\(pairs))"
    }
    if emitted.hasPrefix("\\P{") || (emitted.hasPrefix("\\") && emitted.count <= 2) {
        return "(?:[\(emitted)--[\\uE000-\\uE801]]\(pairs))"
    }
    return emitted
}

/// Translates a `java.util.regex` pattern into the ICU dialect used by
/// `NSRegularExpression`.
///
/// Two JVM behaviours differ from ICU defaults and are emulated here:
///
/// 1. **Predefined classes are ASCII by default.** On the JVM `\w`, `\d`, `\s`
///    (and their negations `\W`, `\D`, `\S`) match US-ASCII characters only
///    unless `UNICODE_CHARACTER_CLASS` (`(?U)`) is in effect; `\b` / `\B` use the
///    same ASCII word class, and the POSIX `\p{Name}` classes
///    (`\p{Lower}` … `\p{Space}`) are US-ASCII as well. ICU's `\w` / `\d` /
///    `\s` / `\p{Name}` are always Unicode-aware, so while the ASCII mode is
///    active each predefined escape is rewritten to the equivalent explicit
///    class, `\b` / `\B` expand to lookaround assertions over
///    `[a-zA-Z0-9_]`, and `\p{Name}` escapes are resolved by
///    ``jvmRegexICUPropertyReplacement`` (KUU-4295), which applies the JVM's
///    `Pattern.family` dispatch — ASCII POSIX expansions outside `(?U)`,
///    `gc=`/`general_category=` and `Is*` rewrites — before falling back to
///    verbatim copy.
/// 2. **`(?U)` / `(?u)` inline flags are unknown to ICU.** The `u`
///    (UNICODE_CASE) flag is a no-op — ICU folds case over Unicode already —
///    and `U` toggles the translation mode: while Unicode character classes are
///    active the escapes are copied through so ICU applies its Unicode
///    semantics, which match the JVM's `UNICODE_CHARACTER_CLASS` definitions.
///    Bare `(?flags)` groups retarget the mode until the end of the enclosing
///    group, exactly like the JVM; `(?flags:...)` groups save the enclosing
///    mode and restore it at the matching `)`.
///
/// Inside character classes the ASCII expansions are emitted as nested classes
/// (`[...]` members) so they union correctly with neighbours and cannot merge
/// into unintended ranges (e.g. `[\w-y]` keeps `-`/`y` literal). ICU set
/// operators `[.`/`[=`/`[:` (collation elements, equivalence classes, POSIX
/// classes) have no `java.util.regex` counterpart — the inner `[` opens an
/// ordinary nested class of literal members on the JVM — so the operator's
/// second character is escaped in both modes (`[[:alpha:]]` becomes
/// `[[\:alpha:]]`, a nested class matching `:alpha:` literally).
/// Escapes, `\Q...\E` quotes and character-class structure are otherwise copied
/// verbatim.
func translateJavaPatternForICU(_ pattern: String, unicodeCharacterClassesInitially: Bool = false, dotMatchesLineSeparatorsInitially: Bool = false, unixLinesInitially: Bool = false) -> String {
    var unicodeClasses = unicodeCharacterClassesInitially
    var dotAll = dotMatchesLineSeparatorsInitially
    var unixLines = unixLinesInitially
    var savedModes: [(Bool, Bool, Bool)] = []
    let chars = Array(pattern)
    var out = ""
    out.reserveCapacity(chars.count)
    var index = 0
    var classDepth = 0
    var outerClassStart: Int?
    func isFlag(_ c: Character) -> Bool { "idmsuxU".contains(c) }
    while index < chars.count {
        let c = chars[index]
        if c == "\\" {
            if index + 1 < chars.count, chars[index + 1] == "Q" {
                var end = index + 2
                while end < chars.count, !(chars[end] == "\\" && end + 1 < chars.count && chars[end + 1] == "E") {
                    end += 1
                }
                end = min(end + 2, chars.count)
                out.append(contentsOf: chars[index..<end])
                index = end
                continue
            }
            guard index + 1 < chars.count else {
                out.append(c)
                index += 1
                continue
            }
            let escape = chars[index + 1]
            if escape == "p" || escape == "P" {
                if index + 2 < chars.count, chars[index + 2] == "{" {
                    var end = index + 3
                    while end < chars.count, chars[end] != "}" { end += 1 }
                    if end < chars.count {
                        let name = String(chars[(index + 3)..<end])
                        let negated = escape == "P"
                        if classDepth > 0 {
                            if let replacement = jvmRegexICUPropertyReplacement(
                                name, negated: negated, unicodeClasses: unicodeClasses
                            ), replacement.hasPrefix("[") || replacement.hasPrefix("\\p{") || replacement.hasPrefix("\\P{") {
                                out.append(replacement)
                            } else {
                                out.append(contentsOf: chars[index...end])
                            }
                        } else {
                            let emitted = jvmRegexICUPropertyReplacement(
                                name, negated: negated, unicodeClasses: unicodeClasses
                            ) ?? String(chars[index...end])
                            out.append(regexMarkerSpaceWrapEmission(emitted, negated: negated))
                        }
                        index = end + 1
                        continue
                    }
                } else if index + 2 < chars.count, "LMNPSZC".contains(chars[index + 2]) {
                    let letter = String(chars[index + 2])
                    let negated = escape == "P"
                    if classDepth > 0 {
                        if let replacement = jvmRegexICUPropertyReplacement(
                            letter, negated: negated, unicodeClasses: unicodeClasses
                        ), replacement.hasPrefix("[") || replacement.hasPrefix("\\p{") || replacement.hasPrefix("\\P{") {
                            out.append(replacement)
                        } else {
                            out.append("\\\(escape){\(letter)}")
                        }
                    } else {
                        let emitted = jvmRegexICUPropertyReplacement(
                            letter, negated: negated, unicodeClasses: unicodeClasses
                        ) ?? "\\\(escape){\(letter)}"
                        out.append(regexMarkerSpaceWrapEmission(emitted, negated: negated))
                    }
                    index += 3
                    continue
                }
                out.append(contentsOf: chars[index...index + 1])
                index += 2
                continue
            }
            if classDepth > 0 {
                switch escape {
                case "w": out.append(unicodeClasses ? "\\w" : "[a-zA-Z0-9_]")
                case "W": out.append(unicodeClasses ? "[^\\w]" : "[^a-zA-Z0-9_]")
                case "d": out.append(unicodeClasses ? "\\d" : "[0-9]")
                case "D": out.append(unicodeClasses ? "[^\\d]" : "[^0-9]")
                case "s": out.append(unicodeClasses ? "\\s" : "[\\t\\n\\x0B\\f\\r ]")
                case "S": out.append(unicodeClasses ? "[^\\s]" : "[^ \\t\\n\\x0B\\f\\r]")
                default: out.append(contentsOf: chars[index...index + 1])
                }
            } else {
                switch escape {
                case "w": out.append(unicodeClasses ? "\\w" : "[a-zA-Z0-9_]")
                case "W": out.append(regexMarkerSpaceWrapEmission(unicodeClasses ? "\\W" : "[^a-zA-Z0-9_]", negated: true))
                case "d": out.append(unicodeClasses ? "\\d" : "[0-9]")
                case "D": out.append(regexMarkerSpaceWrapEmission(unicodeClasses ? "\\D" : "[^0-9]", negated: true))
                case "s": out.append(unicodeClasses ? "\\s" : "[ \\t\\n\\x0B\\f\\r]")
                case "S": out.append(regexMarkerSpaceWrapEmission(unicodeClasses ? "\\S" : "[^ \\t\\n\\x0B\\f\\r]", negated: true))
                case "H": out.append(regexMarkerSpaceWrapEmission("\\H", negated: true))
                case "V": out.append(regexMarkerSpaceWrapEmission("\\V", negated: true))
                case "b": out.append(unicodeClasses ? unicodeWordBoundaryPattern : asciiWordBoundaryPattern)
                case "B": out.append(unicodeClasses ? unicodeNonWordBoundaryPattern : asciiNonWordBoundaryPattern)
                case "u":
                    var end = index + 2
                    var value = 0
                    var digits = 0
                    while end < chars.count, digits < 4, let d = chars[end].hexDigitValue {
                        value = value * 16 + d
                        digits += 1
                        end += 1
                    }
                    if digits == 4, let rewritten = regexMarkerSpaceScalarReplacement(value) {
                        out.append(rewritten)
                        index = end
                        continue
                    }
                    out.append(contentsOf: chars[index...index + 1])
                case "x":
                    if index + 2 < chars.count, chars[index + 2] == "{" {
                        var end = index + 3
                        var value = 0
                        var overflow = false
                        while end < chars.count, chars[end] != "}", let d = chars[end].hexDigitValue {
                            let (shifted, mulOverflow) = value.multipliedReportingOverflow(by: 16)
                            let (next, addOverflow) = shifted.addingReportingOverflow(d)
                            overflow = overflow || mulOverflow || addOverflow
                            value = next
                            end += 1
                        }
                        if !overflow, end < chars.count, chars[end] == "}",
                           let rewritten = regexMarkerSpaceScalarReplacement(value) {
                            out.append(rewritten)
                            index = end + 1
                            continue
                        }
                    }
                    out.append(contentsOf: chars[index...index + 1])
                default: out.append(contentsOf: chars[index...index + 1])
                }
            }
            index += 2
            continue
        }
        if classDepth > 0 {
            if c == "[" {
                classDepth += 1
                out.append(c)
                index += 1
                // `[:`, `[.`, `[=` open ICU POSIX-class / collating-element /
                // equivalence operators inside a set. `java.util.regex` has
                // no such operators — the inner `[` opens an ordinary nested
                // class and the rest are literal members — so the operator's
                // second character is escaped (`[[:alpha:]]` becomes
                // `[[\:alpha:]]`, matching the literal characters `:alpha:`).
                // Applies in both modes: the JVM treats them as literals even
                // under (?U).
                if index < chars.count, chars[index] == ":" || chars[index] == "." || chars[index] == "=" {
                    out.append("\\")
                }
                continue
            }
            if c == "]" {
                classDepth -= 1
                out.append(c)
                index += 1
                if classDepth == 0, let start = outerClassStart {
                    let emitted = String(out[out.index(out.startIndex, offsetBy: start)...])
                    if let rewritten = regexMarkerSpaceClassReplacement(emitted) {
                        out = String(out.prefix(start)) + rewritten
                    }
                    outerClassStart = nil
                }
                continue
            }
            out.append(c)
            index += 1
            continue
        }
        if c == "[" {
            classDepth = 1
            outerClassStart = out.count
            out.append(c)
            index += 1
            if index < chars.count, chars[index] == "^" { out.append("^"); index += 1 }
            if index < chars.count, chars[index] == "]" { out.append("]"); index += 1 }
            continue
        }
        if c == "." {
            if dotAll {
                out.append("(?:[^\\uE000-\\uE801]|\\uE800[\\uE000-\\uE7FF]|\\uE801[\\uE000-\\uE801])")
            } else if unixLines {
                out.append("(?:[^\\n\\uE000-\\uE801]|\\uE800[\\uE000-\\uE7FF]|\\uE801[\\uE000-\\uE801])")
            } else {
                out.append("(?:[^\\uE000-\\uE801\\n\\r\\u0085\\u2028\\u2029]|\\uE800[\\uE000-\\uE7FF]|\\uE801[\\uE000-\\uE801])")
            }
            index += 1
            continue
        }
        if c == ")" {
            if let saved = savedModes.popLast() {
                (unicodeClasses, dotAll, unixLines) = saved
            }
            out.append(c)
            index += 1
            continue
        }
        if c == "(", index + 1 < chars.count, chars[index + 1] == "?" {
            var cursor = index + 2
            var on = ""
            var off = ""
            var onUnicode = false
            var offUnicode = false
            var onDotAll = false
            var offDotAll = false
            var onUnixLines = false
            var offUnixLines = false
            var seenMinus = false
            while cursor < chars.count {
                let f = chars[cursor]
                if f == "-", !seenMinus { seenMinus = true; cursor += 1; continue }
                guard isFlag(f) else { break }
                if f == "U" {
                    if seenMinus { offUnicode = true } else { onUnicode = true }
                } else if f != "u" {
                    if seenMinus { off.append(f) } else { on.append(f) }
                    if f == "s" { if seenMinus { offDotAll = true } else { onDotAll = true } }
                    if f == "d" { if seenMinus { offUnixLines = true } else { onUnixLines = true } }
                }
                cursor += 1
            }
            let isFlagGroup = cursor > index + 2
                && cursor < chars.count
                && (chars[cursor] == ")" || chars[cursor] == ":")
            if isFlagGroup {
                let terminator = chars[cursor]
                if terminator == ":" { savedModes.append((unicodeClasses, dotAll, unixLines)) }
                if onUnicode { unicodeClasses = true }
                if offUnicode { unicodeClasses = false }
                if onDotAll { dotAll = true }
                if offDotAll { dotAll = false }
                if onUnixLines { unixLines = true }
                if offUnixLines { unixLines = false }
                if on.isEmpty && off.isEmpty {
                    if terminator == ":" { out.append("(?:") }
                } else {
                    out.append("(?")
                    out.append(on)
                    if !off.isEmpty { out.append("-"); out.append(off) }
                    out.append(terminator)
                }
                index = cursor + 1
                continue
            }
            savedModes.append((unicodeClasses, dotAll, unixLines))
            out.append(c)
            index += 1
            continue
        }
        if c == "(" {
            savedModes.append((unicodeClasses, dotAll, unixLines))
            out.append(c)
            index += 1
            continue
        }
        out.append(c)
        index += 1
    }
    return out
}

func stripJavaOnlyInlineFlags(_ pattern: String) -> String {
    translateJavaPatternForICU(pattern, unicodeCharacterClassesInitially: true)
}

/// Defense-in-depth bounds for regex evaluation.
///
/// The runtime applies these caps on top of ICU / `NSRegularExpression` to keep
/// catastrophic-backtracking inputs from hanging the calling thread
/// indefinitely. Kotlin/JVM does not impose these bounds; they are a KSwiftK
/// runtime safety measure.
///
/// - `KSWIFTK_REGEX_TIMEOUT_MS`: per-operation wall-clock timeout in
///   milliseconds. The default is 30000ms (30s) — generous enough that
///   legitimate matches over large inputs complete well within it, while still
///   bounding catastrophic backtracking that would otherwise never return. A
///   value `<= 0` disables the timeout entirely and restores unbounded behavior.
/// - `KSWIFTK_REGEX_MAX_INPUT_LENGTH`: optional maximum input length in UTF-16
///   units. The default is `0`, which disables the cap. Any positive value
///   enables a fail-closed precheck that treats oversized inputs as no match.
///
/// When a timeout or size cap trips, bulk operations such as replace and split
/// fail closed and return the original input unchanged rather than hanging or
/// producing partial output. Tune or disable the limits with the environment
/// variables above.
private enum RegexEvaluationLimits {
    static let matchTimeout: TimeInterval = {
        let environment = ProcessInfo.processInfo.environment
        guard let rawValue = environment["KSWIFTK_REGEX_TIMEOUT_MS"] else {
            return 30.0
        }
        guard let timeoutMs = Double(rawValue), timeoutMs > 0 else { return 0.0 }
        return timeoutMs / 1000.0
    }()

    static let maxInputLength: Int = {
        let environment = ProcessInfo.processInfo.environment
        guard let rawValue = environment["KSWIFTK_REGEX_MAX_INPUT_LENGTH"],
              let inputLength = Int(rawValue),
              inputLength > 0 else {
            return 0
        }
        return inputLength
    }()

    static var isTimeoutEnabled: Bool {
        matchTimeout > 0
    }
}

private enum RegexNamedGroupDetector {
    static let expression: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\(\\?<([a-zA-Z_][a-zA-Z0-9_]*)>",
        options: []
    )
}

private func extractNamedGroupNames(from pattern: String) -> [String] {
    guard let detector = RegexNamedGroupDetector.expression else {
        return []
    }
    let nsRange = NSRange(pattern.startIndex..., in: pattern)
    let matches = detector.matches(in: pattern, options: [], range: nsRange)
    return matches.compactMap { match -> String? in
        guard match.numberOfRanges >= 2 else { return nil }
        let nameRange = match.range(at: 1)
        guard nameRange.location != NSNotFound, let range = Range(nameRange, in: pattern) else { return nil }
        return String(pattern[range])
    }
}

private enum RegexReplacementTemplateError: Error {
    case missingGroup(Int)
    case illegalArgument(String)
}

private func asciiDecimalDigit(_ character: Character) -> Int? {
    guard character.unicodeScalars.count == 1,
          let scalar = character.unicodeScalars.first,
          scalar.value >= 48,
          scalar.value <= 57
    else {
        return nil
    }
    return Int(scalar.value - 48)
}

/// Validates the replacement-template grammar used by java.util.regex.Matcher.
/// Foundation treats invalid references as literals or empty strings, so this
/// check must run before handing the template to NSRegularExpression.
private func validateRegexReplacementTemplate(
    _ template: String,
    match: NSTextCheckingResult,
    namedGroupNames: Set<String>
) throws {
    let groupCount = max(0, match.numberOfRanges - 1)
    var index = template.startIndex

    while index < template.endIndex {
        switch template[index] {
        case "\\":
            let escapedIndex = template.index(after: index)
            guard escapedIndex < template.endIndex else {
                throw RegexReplacementTemplateError.illegalArgument(
                    "character to be escaped is missing"
                )
            }
            index = template.index(after: escapedIndex)
        case "$":
            let referenceIndex = template.index(after: index)
            guard referenceIndex < template.endIndex else {
                throw RegexReplacementTemplateError.illegalArgument(
                    "Illegal group reference: group index is missing"
                )
            }

            if template[referenceIndex] == "{" {
                let nameStart = template.index(after: referenceIndex)
                guard let closingIndex = template[nameStart...].firstIndex(of: "}") else {
                    throw RegexReplacementTemplateError.illegalArgument(
                        "named capturing group is missing trailing '}'"
                    )
                }
                let name = String(template[nameStart ..< closingIndex])
                guard !name.isEmpty else {
                    throw RegexReplacementTemplateError.illegalArgument(
                        "named capturing group has 0 length name"
                    )
                }
                guard namedGroupNames.contains(name) else {
                    throw RegexReplacementTemplateError.illegalArgument(
                        "No group with name {\(name)}"
                    )
                }
                index = template.index(after: closingIndex)
                continue
            }

            guard let firstDigit = asciiDecimalDigit(template[referenceIndex]) else {
                throw RegexReplacementTemplateError.illegalArgument("Illegal group reference")
            }

            var reference = firstDigit
            var digitIndex = template.index(after: referenceIndex)
            while digitIndex < template.endIndex,
                  let digit = asciiDecimalDigit(template[digitIndex]),
                  groupCount >= digit,
                  reference <= (groupCount - digit) / 10
            {
                reference = reference * 10 + digit
                digitIndex = template.index(after: digitIndex)
            }

            guard reference <= groupCount else {
                throw RegexReplacementTemplateError.missingGroup(reference)
            }
            index = digitIndex
        default:
            index = template.index(after: index)
        }
    }
}

private func propagateRegexReplacementTemplateError(
    _ error: RegexReplacementTemplateError,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let thrown: Int
    switch error {
    case .missingGroup(let index):
        thrown = runtimeAllocateIndexOutOfBoundsException(message: "No group \(index)")
    case .illegalArgument(let message):
        thrown = runtimeAllocateIllegalArgumentException(message: message)
    }
    runtimePropagateThrownOrTrap(
        thrown,
        outThrown: outThrown,
        context: "Regex replacement template"
    )
    return 0
}

private func namedCaptureGroupIndexMap(
    from result: NSTextCheckingResult,
    regexBox: RuntimeRegexBox
) -> [String: Int] {
    var namedGroups: [String: Int] = [:]
    for name in regexBox.namedGroupNames {
        let namedRange = result.range(withName: regexICUString(runtimeKotlinStringUTF16CodeUnits(name)))
        guard namedRange.location != NSNotFound else { continue }
        for groupIndex in 1 ..< result.numberOfRanges where result.range(at: groupIndex) == namedRange {
            namedGroups[name] = groupIndex
            break
        }
    }
    return namedGroups
}

private func expandNamedGroupReferences(in template: String, namedGroups: [String: Int]) -> String {
    var result = ""
    var index = template.startIndex
    while index < template.endIndex {
        let character = template[index]
        if character == "\\" {
            result.append(character)
            let next = template.index(after: index)
            guard next < template.endIndex else { break }
            result.append(template[next])
            index = template.index(after: next)
            continue
        }
        if character == "$" {
            let afterDollar = template.index(after: index)
            if afterDollar < template.endIndex, template[afterDollar] == "{" {
                let nameStart = template.index(after: afterDollar)
                if let closing = template[nameStart...].firstIndex(of: "}") {
                    let name = String(template[nameStart..<closing])
                    if let groupIndex = replacementGroupIndex(name, namedGroups: namedGroups) {
                        result.append("$\(groupIndex)")
                        index = template.index(after: closing)
                        continue
                    }
                }
            }
        }
        result.append(character)
        index = template.index(after: index)
    }
    return result
}

private func replacementGroupIndex(_ name: String, namedGroups: [String: Int]) -> Int? {
    if let number = Int(name), number >= 0 {
        return number
    }
    return namedGroups[name]
}

private func applyRegexReplacementTemplate(
    _ regex: NSRegularExpression,
    match: NSTextCheckingResult,
    in subject: RegexSubject,
    template: String,
    regexBox: RuntimeRegexBox
) -> String {
    let namedGroups = namedCaptureGroupIndexMap(from: match, regexBox: regexBox)
    let expanded = expandNamedGroupReferences(in: template, namedGroups: namedGroups)
    let icuTemplate = regexICUString(runtimeKotlinStringUTF16CodeUnits(expanded))
    return regex.replacementString(for: match, in: subject.icu, offset: 0, template: icuTemplate)
}

private func makeMatchResult(from result: NSTextCheckingResult, in subject: RegexSubject, regexBox: RuntimeRegexBox? = nil, inputUTF16Count: Int? = nil) -> RuntimeMatchResultBox {
    func groupString(_ range: NSRange) -> String? {
        guard let unitRange = subject.unitRange(range) else { return nil }
        return runtimeKotlinStringFromUTF16CodeUnits(
            Array(subject.units[unitRange])
        )
    }
    guard let value = groupString(result.range) else {
        return RuntimeMatchResultBox(value: "", groupValues: [])
    }
    let utf16Count = inputUTF16Count ?? subject.units.count

    var groupValues: [String] = []
    var groups: [RuntimeMatchGroupBox?] = []
    for i in 0 ..< result.numberOfRanges {
        let groupRange = result.range(at: i)
        if let groupValue = groupString(groupRange), let unitRange = subject.unitRange(groupRange) {
            groupValues.append(groupValue)
            let startIndex = unitRange.lowerBound
            let endIndex = unitRange.upperBound - 1
            groups.append(RuntimeMatchGroupBox(value: groupValue, rangeStart: startIndex, rangeEnd: endIndex))
        } else {
            groupValues.append("")
            groups.append(nil)
        }
    }

    var namedGroups: [String: Int] = [:]
    var namedGroupNames: Set<String> = []
    if let regexBox = regexBox {
        namedGroupNames = Set(regexBox.namedGroupNames)
        namedGroups = namedCaptureGroupIndexMap(from: result, regexBox: regexBox)
    }

    let matchEnd = subject.unitRange(result.range)?.upperBound ?? 0

    return RuntimeMatchResultBox(
        value: value,
        groupValues: groupValues,
        groups: groups,
        namedGroups: namedGroups,
        namedGroupNames: namedGroupNames,
        inputString: subject.icu,
        inputUTF16Count: utf16Count,
        matchEndOffset: matchEnd,
        regexBox: regexBox
    )
}

private func boundedFirstMatch(
    _ regex: NSRegularExpression,
    in str: String,
    options: NSRegularExpression.MatchingOptions,
    range: NSRange
) -> NSTextCheckingResult? {
    if RegexEvaluationLimits.maxInputLength > 0, range.length > RegexEvaluationLimits.maxInputLength {
        return nil
    }
    guard RegexEvaluationLimits.isTimeoutEnabled else {
        return regex.firstMatch(in: str, options: options, range: range)
    }

    let deadline = Date().addingTimeInterval(RegexEvaluationLimits.matchTimeout)
    let matchingOptions = options.union(.reportProgress)
    var firstMatch: NSTextCheckingResult?
    regex.enumerateMatches(in: str, options: matchingOptions, range: range) { result, flags, stop in
        if flags.contains(.progress) {
            if Date() >= deadline {
                stop.pointee = true
            }
            return
        }

        if let result {
            firstMatch = result
            stop.pointee = true
        }
    }
    return firstMatch
}

private func boundedMatches(
    _ regex: NSRegularExpression,
    in str: String,
    options: NSRegularExpression.MatchingOptions,
    range: NSRange
) -> [NSTextCheckingResult]? {
    if RegexEvaluationLimits.maxInputLength > 0, range.length > RegexEvaluationLimits.maxInputLength {
        return nil
    }
    guard RegexEvaluationLimits.isTimeoutEnabled else {
        return regex.matches(in: str, options: options, range: range)
    }

    let deadline = Date().addingTimeInterval(RegexEvaluationLimits.matchTimeout)
    let matchingOptions = options.union(.reportProgress)
    var matches: [NSTextCheckingResult] = []
    var timedOut = false
    regex.enumerateMatches(in: str, options: matchingOptions, range: range) { result, flags, stop in
        if flags.contains(.progress) {
            if Date() >= deadline {
                timedOut = true
                stop.pointee = true
            }
            return
        }

        if let result {
            matches.append(result)
        }
    }
    return timedOut ? nil : matches
}


@_cdecl("__kk_regex_create_flat")
public func kk_regex_create_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        runtimeRegexCreate(
            pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
            outThrown: outThrown
        )
    }
}


private func runtimeRegexCreate(pattern: String, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let regex = try? compileRegexPattern(pattern, options: []) else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(
                message: "Illegal pattern: \(pattern)"
            ))
        }
        return registerRuntimeObject(RuntimeRegexBox(regex: regex, pattern: pattern))
    }
}

@_cdecl("__kk_string_matches_regex_flat")
public func kk_string_matches_regex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ regexRaw: Int
) -> Int {
    runtimeStringMatchesRegex(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        regexRaw
    )
}

private func runtimeStringMatchesRegex(_ rawStr: String, _ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let subject = RegexSubject(encoded: regexBox.normalizeIfNeeded(rawStr))
    guard let anchoredRegex = regexBox.anchoredRegex else {
        return kk_box_bool(0)
    }
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    let match = boundedFirstMatch(anchoredRegex, in: subject.icu, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}

@_cdecl("__kk_string_contains_regex_flat")
public func kk_string_contains_regex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ regexRaw: Int
) -> Int {
    runtimeStringContainsRegex(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        regexRaw
    )
}

private func runtimeStringContainsRegex(_ rawStr: String, _ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let subject = RegexSubject(encoded: regexBox.normalizeIfNeeded(rawStr))
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    let match = boundedFirstMatch(regexBox.regex, in: subject.icu, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}


@_cdecl("__kk_regex_find_flat")
public func kk_regex_find_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexFind(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}


private func runtimeRegexFind(_ regexRaw: Int, input rawStr: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeNullSentinelInt }
    let subject = RegexSubject(encoded: regexBox.normalizeIfNeeded(rawStr))
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    guard let result = boundedFirstMatch(regexBox.regex, in: subject.icu, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    let matchResult = makeMatchResult(from: result, in: subject, regexBox: regexBox)
    return registerRuntimeMatchResult(matchResult)
}

@_cdecl("__kk_regex_findAll_flat")
public func kk_regex_findAll_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexFindAll(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexFindAll(_ regexRaw: Int, input rawStr: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeListRaw([]) }
    let subject = RegexSubject(encoded: regexBox.normalizeIfNeeded(rawStr))
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    let results = boundedMatches(regexBox.regex, in: subject.icu, options: [], range: range)
    guard let results else { return regexMakeListRaw([]) }
    let utf16Count = subject.units.count
    let matchResults = results.map { result -> Int in
        let matchResult = makeMatchResult(from: result, in: subject, regexBox: regexBox, inputUTF16Count: utf16Count)
        return registerRuntimeMatchResult(matchResult)
    }
    return regexMakeListRaw(matchResults)
}


@_cdecl("__kk_string_replace_regex")
public func kk_string_replace_regex(
    _ strRaw: Int,
    _ regexRaw: Int,
    _ replacementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        let rawStr = regexStringFromRaw(strRaw) ?? ""
        let replacement = regexStringFromRaw(replacementRaw) ?? ""
        guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeMakeStringRaw(rawStr) }
        let normalized = regexBox.normalizeIfNeeded(rawStr)
        let subject = RegexSubject(encoded: normalized)
        let range = NSRange(location: 0, length: subject.icuUnits.count)
        let matches = boundedMatches(regexBox.regex, in: subject.icu, options: [], range: range)
        guard let matches else {
            return runtimeMakeStringRaw(rawStr)
        }
        if matches.isEmpty {
            return runtimeMakeStringRaw(normalized)
        }
        do {
            try validateRegexReplacementTemplate(
                replacement,
                match: matches[0],
                namedGroupNames: Set(regexBox.namedGroupNames)
            )
        } catch let error as RegexReplacementTemplateError {
            return propagateRegexReplacementTemplateError(error, outThrown: outThrown)
        } catch {
            return propagateRegexReplacementTemplateError(
                .illegalArgument("Invalid replacement template"),
                outThrown: outThrown
            )
        }
        var resultUnits: [UInt16] = []
        resultUnits.reserveCapacity(subject.units.count)
        var cursor = 0
        for match in matches {
            guard let unitRange = subject.unitRange(match.range),
                  unitRange.lowerBound >= cursor else { continue }
            let location = unitRange.lowerBound
            let length = unitRange.count
            resultUnits.append(contentsOf: subject.units[cursor ..< location])
            let templateResult = applyRegexReplacementTemplate(
                regexBox.regex,
                match: match,
                in: subject,
                template: replacement,
                regexBox: regexBox
            )
            resultUnits.append(contentsOf: regexUTF16Units(ofICUString: templateResult))
            cursor = location + length
        }
        resultUnits.append(contentsOf: subject.units[cursor...])
        return runtimeMakeStringRaw(runtimeKotlinStringFromUTF16CodeUnits(resultUnits))
    }
}

@_cdecl("__kk_string_split_regex_flat")
public func kk_string_split_regex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ regexRaw: Int
) -> Int {
    runtimeStringSplitRegex(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        regexRaw
    )
}


private func runtimeStringSplitRegex(_ rawStr: String, _ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringListRaw([rawStr]) }
    let normalized = regexBox.normalizeIfNeeded(rawStr)
    let subject = RegexSubject(encoded: normalized)
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    let matches = boundedMatches(regexBox.regex, in: subject.icu, options: [], range: range)
    guard let matches else {
        return regexMakeStringListRaw([rawStr])
    }
    if matches.isEmpty {
        return regexMakeStringListRaw([normalized])
    }
    var parts: [String] = []
    var cursor = 0
    for match in matches {
            guard let unitRange = subject.unitRange(match.range),
                  unitRange.lowerBound >= cursor else { continue }
            let location = unitRange.lowerBound
            let length = unitRange.count
            parts.append(runtimeKotlinStringFromUTF16CodeUnits(Array(subject.units[cursor ..< location])))
        cursor = location + length
    }
    parts.append(runtimeKotlinStringFromUTF16CodeUnits(Array(subject.units[cursor...])))
    return regexMakeStringListRaw(parts)
}


@_cdecl("__kk_regex_replace_lambda")
public func kk_regex_replace_lambda(
    _ regexRaw: Int,
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        let rawStr = regexStringFromRaw(strRaw) ?? ""
        guard let regexBox = regexBoxFromRaw(regexRaw) else { return strRaw }
        let normalized = regexBox.normalizeIfNeeded(rawStr)
        let subject = RegexSubject(encoded: normalized)
        let range = NSRange(location: 0, length: subject.icuUnits.count)
        let matches = boundedMatches(regexBox.regex, in: subject.icu, options: [], range: range)
        guard let matches else { return strRaw }
        if matches.isEmpty { return strRaw }
        var resultUnits: [UInt16] = []
        resultUnits.reserveCapacity(subject.units.count)
        var cursor = 0
        let utf16Count = subject.units.count
        for match in matches {
            guard let unitRange = subject.unitRange(match.range),
                  unitRange.lowerBound >= cursor else { continue }
            let location = unitRange.lowerBound
            let length = unitRange.count
            resultUnits.append(contentsOf: subject.units[cursor ..< location])
            let matchResult = makeMatchResult(from: match, in: subject, regexBox: regexBox, inputUTF16Count: utf16Count)
            let matchResultRaw = registerRuntimeMatchResult(matchResult)
            var thrown = 0
            let replacementRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: matchResultRaw, outThrown: &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return runtimeMakeUTF8StringRaw("")
            }
            let replacement = regexStringFromRaw(replacementRaw) ?? ""
            resultUnits.append(contentsOf: runtimeKotlinStringUTF16CodeUnits(replacement))
            cursor = location + length
        }
        resultUnits.append(contentsOf: subject.units[cursor...])
        return runtimeMakeStringRaw(runtimeKotlinStringFromUTF16CodeUnits(resultUnits))
    }
}


@_cdecl("__kk_regex_matchEntire_flat")
public func kk_regex_matchEntire_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexMatchEntire(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}


private func runtimeRegexMatchEntire(_ regexRaw: Int, input rawStr: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeNullSentinelInt }
    let subject = RegexSubject(encoded: regexBox.normalizeIfNeeded(rawStr))
    guard let anchoredRegex = regexBox.anchoredRegex else {
        return runtimeNullSentinelInt
    }
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    guard let result = boundedFirstMatch(anchoredRegex, in: subject.icu, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    guard result.range.location == 0, result.range.length == subject.icuUnits.count else {
        return runtimeNullSentinelInt
    }
    let matchResult = makeMatchResult(from: result, in: subject, regexBox: regexBox)
    return registerRuntimeMatchResult(matchResult)
}


// Named constants for Kotlin `RegexOption` enum ordinals.
// These must stay in sync with the enum entry declaration order in
// `Sources/CompilerCore/Stdlib/kotlin/text/Regex.kt`.
private let kRegexOptionOrdinalLiteral  = 2
private let kRegexOptionOrdinalCanonEq  = 6

/// **Coupling note**: The ordinal values here must stay in sync with the
/// enum entry declaration order in
/// `Sources/CompilerCore/Stdlib/kotlin/text/Regex.kt`.
/// The canonical order is defined by Kotlin's `kotlin.text.RegexOption`:
///   0 = IGNORE_CASE, 1 = MULTILINE, 2 = LITERAL, 3 = UNIX_LINES,
///   4 = COMMENTS, 5 = DOT_MATCHES_ALL, 6 = CANON_EQ
/// If the compiler-side entry order changes, these ordinals must be updated
/// to match.
private func nsRegexOption(fromOrdinal ordinal: Int) -> NSRegularExpression.Options {
    switch ordinal {
    case 0: return .caseInsensitive
    case 1: return .anchorsMatchLines
    case kRegexOptionOrdinalLiteral: return []
    case 3: return .useUnixLineSeparators
    case 4: return .allowCommentsAndWhitespace
    case 5: return .dotMatchesLineSeparators
    case kRegexOptionOrdinalCanonEq: return []
    default:
        assertionFailure("KSwiftK: unknown RegexOption ordinal \(ordinal) – compiler/runtime enum mismatch?")
        return []
    }
}

private func createRegexBox(
    pattern: String,
    isLiteral: Bool,
    options: NSRegularExpression.Options,
    optionOrdinals: Set<Int>,
    outThrown: UnsafeMutablePointer<Int>?
) -> RuntimeRegexBox? {
    let canonEq = optionOrdinals.contains(kRegexOptionOrdinalCanonEq)
    let normalizedPattern = canonEq ? pattern.precomposedStringWithCanonicalMapping : pattern
    let effectivePattern = isLiteral ? NSRegularExpression.escapedPattern(for: normalizedPattern) : normalizedPattern
    guard let regex = try? compileRegexPattern(effectivePattern, options: options) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Illegal pattern: \(pattern)"
        )
        return nil
    }
    return RuntimeRegexBox(regex: regex, pattern: pattern, canonEq: canonEq, optionOrdinals: optionOrdinals)
}



@_cdecl("__kk_regex_create_with_option_flat")
public func kk_regex_create_with_option_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        runtimeRegexCreateWithOption(
            pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
            optionRaw: optionRaw,
            outThrown: outThrown
        )
    }
}

@_cdecl("__kk_string_toRegex_with_option_flat")
public func kk_string_toRegex_with_option_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        runtimeRegexCreateWithOption(
            pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
            optionRaw: optionRaw,
            outThrown: outThrown
        )
    }
}

private func runtimeRegexCreateWithOption(pattern: String, optionRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return runtimeThrowingBridge(outThrown) {
        let ordinal = Int(kk_unbox_int(optionRaw))
        guard let box = createRegexBox(
            pattern: pattern,
            isLiteral: ordinal == kRegexOptionOrdinalLiteral,
            options: nsRegexOption(fromOrdinal: ordinal),
            optionOrdinals: [ordinal],
            outThrown: outThrown
        ) else {
            return 0
        }
        return registerRuntimeObject(box)
    }
}


@_cdecl("__kk_regex_create_with_options_flat")
public func kk_regex_create_with_options_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionsSetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        runtimeRegexCreateWithOptions(
            pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
            optionsSetRaw: optionsSetRaw,
            outThrown: outThrown
        )
    }
}

@_cdecl("__kk_string_toRegex_with_options_flat")
public func kk_string_toRegex_with_options_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionsSetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        runtimeRegexCreateWithOptions(
            pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
            optionsSetRaw: optionsSetRaw,
            outThrown: outThrown
        )
    }
}

private func runtimeRegexCreateWithOptions(pattern: String, optionsSetRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return runtimeThrowingBridge(outThrown) {
        var combined: NSRegularExpression.Options = []
        var isLiteral = false
        var storedOrdinals: Set<Int> = []
        if let setBox = runtimeSetBox(from: optionsSetRaw) {
            for element in setBox.elements {
                let ordinal = Int(kk_unbox_int(element))
                storedOrdinals.insert(ordinal)
                if ordinal == kRegexOptionOrdinalLiteral { isLiteral = true }
                combined.insert(nsRegexOption(fromOrdinal: ordinal))
            }
        }
        guard let box = createRegexBox(
            pattern: pattern, isLiteral: isLiteral, options: combined, optionOrdinals: storedOrdinals, outThrown: outThrown
        ) else {
            return 0
        }
        return registerRuntimeObject(box)
    }
}

@_cdecl("__kk_regex_containsMatchIn_flat")
public func kk_regex_containsMatchIn_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexContainsMatchIn(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexContainsMatchIn(_ regexRaw: Int, input rawInput: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let subject = RegexSubject(encoded: regexBox.normalizeIfNeeded(rawInput))
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    let match = boundedFirstMatch(regexBox.regex, in: subject.icu, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}


@_cdecl("__kk_string_toRegex_flat")
public func kk_string_toRegex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        kk_regex_create_flat(data, length, byteCount, hash, outThrown)
    }
}


@_cdecl("__kk_regex_pattern")
public func __kk_regex_pattern(_ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeMakeUTF8StringRaw("") }
    return runtimeMakeStringRaw(regexBox.pattern)
}

/// Bit mask of the Kotlin `RegexOption` ordinals this regex was created with
/// (bit `n` set means the option with ordinal `n` is present).
@_cdecl("__kk_regex_option_mask")
public func __kk_regex_option_mask(_ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return 0 }
    var mask = 0
    for ordinal in regexBox.optionOrdinals where ordinal >= 0 && ordinal < Int.bitWidth - 1 {
        mask |= 1 << ordinal
    }
    return mask
}


@_cdecl("__kk_match_result_group_count")
public func __kk_match_result_group_count(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return 0 }
    return matchResult.groupValues.count
}

@_cdecl("__kk_match_result_group_value")
public func __kk_match_result_group_value(_ matchRaw: Int, _ index: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          index >= 0, index < matchResult.groupValues.count else {
        return runtimeMakeUTF8StringRaw("")
    }
    return runtimeMakeStringRaw(matchResult.groupValues[index])
}

@_cdecl("__kk_match_result_group_start")
public func __kk_match_result_group_start(_ matchRaw: Int, _ index: Int) -> Int {
    guard let group = matchResultGroup(matchRaw, index) else { return -1 }
    return group.rangeStart
}

@_cdecl("__kk_match_result_group_end")
public func __kk_match_result_group_end(_ matchRaw: Int, _ index: Int) -> Int {
    guard let group = matchResultGroup(matchRaw, index) else { return -1 }
    return group.rangeEnd
}

@_cdecl("__kk_match_result_group_index_of_name")
public func __kk_match_result_group_index_of_name(_ matchRaw: Int, _ nameRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let name = regexStringFromRaw(nameRaw),
          let index = matchResult.namedGroups[name] else {
        return -1
    }
    return index
}

@_cdecl("__kk_match_result_has_named_group")
public func __kk_match_result_has_named_group(_ matchRaw: Int, _ nameRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let name = regexStringFromRaw(nameRaw) else {
        return 0
    }
    return matchResult.namedGroupNames.contains(name) ? 1 : 0
}

@_cdecl("__kk_match_result_group_index_of_name_flat")
public func __kk_match_result_group_index_of_name_flat(
    _ matchRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return -1 }
    let name = regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    return matchResult.namedGroups[name] ?? -1
}

private func matchResultGroup(_ matchRaw: Int, _ index: Int) -> RuntimeMatchGroupBox? {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          index >= 0, index < matchResult.groups.count else {
        return nil
    }
    return matchResult.groups[index]
}

/// Continues on the original input from the previous match's exclusive UTF-16
/// end (one unit later after a zero-length match), including a zero-width
/// search at end of string so `$` and empty patterns can still match there.
/// `NSRegularExpression` treats the search-range start as `^` / `$` and hides
/// lookbehind / `\b` unless `.withoutAnchoringBounds` and `.withTransparentBounds`
/// are set.
@_cdecl("__kk_match_result_next")
public func __kk_match_result_next(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let inputString = matchResult.inputString,
          let regexBox = matchResult.regexBox else {
        return runtimeNullSentinelInt
    }
    let offset = matchResult.matchEndOffset + (matchResult.value.isEmpty ? 1 : 0)
    let utf16Count = matchResult.inputUTF16Count
    guard offset <= utf16Count else { return runtimeNullSentinelInt }
    let subject = RegexSubject(icuSubject: inputString)
    let icuOffset = subject.icuLocation(forUnitOffset: offset)
    let range = NSRange(location: icuOffset, length: subject.icuUnits.count - icuOffset)
    guard let result = boundedFirstMatch(
        regexBox.regex,
        in: subject.icu,
        options: [.withoutAnchoringBounds, .withTransparentBounds],
        range: range
    ) else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeMatchResult(makeMatchResult(from: result, in: subject, regexBox: regexBox, inputUTF16Count: utf16Count))
}


@_cdecl("__kk_regex_from_literal_flat")
public func kk_regex_from_literal_flat(
    _ companionRef: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    _ = companionRef
    return runtimeRegexFromLiteral(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexFromLiteral(_ literal: String) -> Int {
    let optionOrdinals: Set<Int> = [kRegexOptionOrdinalLiteral]
    let box = createRegexBox(
        pattern: literal,
        isLiteral: true,
        options: [],
        optionOrdinals: optionOrdinals,
        outThrown: nil
    ) ?? RuntimeRegexBox(
        regex: RegexNeverMatch.expression,
        pattern: literal,
        optionOrdinals: optionOrdinals
    )
    return registerRuntimeObject(box)
}

@_cdecl("__kk_string_replaceFirst_regex")
public func kk_string_replaceFirst_regex(
    _ strRaw: Int,
    _ regexRaw: Int,
    _ replacementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        let rawStr = regexStringFromRaw(strRaw) ?? ""
        let replacement = regexStringFromRaw(replacementRaw) ?? ""
        guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeMakeStringRaw(rawStr) }
        let normalized = regexBox.normalizeIfNeeded(rawStr)
        let subject = RegexSubject(encoded: normalized)
        let range = NSRange(location: 0, length: subject.icuUnits.count)
        guard let match = boundedFirstMatch(regexBox.regex, in: subject.icu, options: [], range: range),
              let matchUnitRange = subject.unitRange(match.range) else {
            return runtimeMakeStringRaw(normalized)
        }
        do {
            try validateRegexReplacementTemplate(
                replacement,
                match: match,
                namedGroupNames: Set(regexBox.namedGroupNames)
            )
        } catch let error as RegexReplacementTemplateError {
            return propagateRegexReplacementTemplateError(error, outThrown: outThrown)
        } catch {
            return propagateRegexReplacementTemplateError(
                .illegalArgument("Invalid replacement template"),
                outThrown: outThrown
            )
        }
        let templateResult = applyRegexReplacementTemplate(
            regexBox.regex,
            match: match,
            in: subject,
            template: replacement,
            regexBox: regexBox
        )
        var resultUnits = subject.units
        resultUnits.replaceSubrange(matchUnitRange, with: regexUTF16Units(ofICUString: templateResult))
        return runtimeMakeStringRaw(runtimeKotlinStringFromUTF16CodeUnits(resultUnits))
    }
}


@_cdecl("__kk_regex_matches_flat")
public func kk_regex_matches_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexMatches(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexMatches(_ regexRaw: Int, input rawInput: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let subject = RegexSubject(encoded: regexBox.normalizeIfNeeded(rawInput))
    guard let anchoredRegex = regexBox.anchoredRegex else { return kk_box_bool(0) }
    let range = NSRange(location: 0, length: subject.icuUnits.count)
    let matched = boundedFirstMatch(anchoredRegex, in: subject.icu, options: [], range: range) != nil
    return kk_box_bool(matched ? 1 : 0)
}


@_cdecl("__kk_match_result_destructured")
public func __kk_match_result_destructured(_ matchRaw: Int) -> Int {
    guard matchResultBoxFromRaw(matchRaw) != nil else { return runtimeNullSentinelInt }
    return matchRaw
}

@_cdecl("__kk_match_result_destructured_match")
public func __kk_match_result_destructured_match(_ destructuredRaw: Int) -> Int {
    guard matchResultBoxFromRaw(destructuredRaw) != nil else { return runtimeNullSentinelInt }
    return destructuredRaw
}

private func regexMarkerScalarEscape(_ value: Int) -> String {
    String(format: "\\u%04X", value)
}

private func regexMarkerSpaceScalarReplacement(_ value: Int) -> String? {
    if (0xD800 ... 0xDFFF).contains(value) {
        return "\\uE800" + regexMarkerScalarEscape(0xE000 + value - 0xD800)
    }
    if (0xE000 ... 0xE801).contains(value) {
        return "\\uE801" + regexMarkerScalarEscape(value)
    }
    return nil
}

private func regexMarkerRangeEscape(_ lo: Int, _ hi: Int) -> String {
    lo == hi ? regexMarkerScalarEscape(lo) : regexMarkerScalarEscape(lo) + "-" + regexMarkerScalarEscape(hi)
}

private func regexMergeScalarRanges(_ ranges: [(Int, Int)]) -> [(Int, Int)] {
    var result: [(Int, Int)] = []
    for r in ranges.sorted(by: { $0.0 < $1.0 }) {
        if let last = result.last, r.0 <= last.1 + 1 {
            result[result.count - 1].1 = max(last.1, r.1)
        } else {
            result.append(r)
        }
    }
    return result
}

private func regexIntersectMarkerSpace(_ ranges: [(Int, Int)], _ space: (Int, Int)) -> [(Int, Int)] {
    ranges.compactMap { r in
        let lo = max(r.0, space.0), hi = min(r.1, space.1)
        return lo <= hi ? (lo, hi) : nil
    }
}

private func regexSubtractMarkerSpace(_ ranges: [(Int, Int)], _ space: (Int, Int)) -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    for r in ranges {
        if r.1 < space.0 || r.0 > space.1 { out.append(r); continue }
        if r.0 < space.0 { out.append((r.0, space.0 - 1)) }
        if r.1 > space.1 { out.append((space.1 + 1, r.1)) }
    }
    return out
}

func regexMarkerSpaceClassReplacement(_ emitted: String) -> String? {
    let chars = Array(emitted)
    guard chars.count >= 2, chars.first == "[", chars.last == "]" else { return nil }
    var i = 1
    var negated = false
    if i < chars.count - 1, chars[i] == "^" { negated = true; i += 1 }
    var scalarRanges: [(Int, Int)] = []
    enum Member { case scalar(Int, String); case rangeSet; case nested; }
    var members: [(kind: Member, text: String, scalarRanges: [(Int, Int)])] = []
    var pendingScalar: (value: Int, text: String)?

    func flushScalar() {
        if let s = pendingScalar {
            members.append((kind: .scalar(s.value, s.text), text: s.text, scalarRanges: [(s.value, s.value)]))
            pendingScalar = nil
        }
    }

    func parseAtom() -> (Int, String)? {
        guard i < chars.count - 1 else { return nil }
        let start = i
        let c = chars[i]
        if c == "\\" {
            guard i + 1 < chars.count else { return nil }
            let e = chars[i + 1]
            if e == "u" {
                var j = i + 2, value = 0, digits = 0
                while j < chars.count - 1, digits < 4, let d = chars[j].hexDigitValue {
                    value = value * 16 + d; digits += 1; j += 1
                }
                guard digits == 4 else { return nil }
                i = j
                return (value, String(chars[start..<j]))
            }
            if e == "x" {
                var j = i + 2, value = 0
                if j < chars.count, chars[j] == "{" {
                    j += 1
                    var overflow = false
                    while j < chars.count - 1, chars[j] != "}", let d = chars[j].hexDigitValue {
                        let (shifted, mulOverflow) = value.multipliedReportingOverflow(by: 16)
                        let (next, addOverflow) = shifted.addingReportingOverflow(d)
                        overflow = overflow || mulOverflow || addOverflow
                        value = next; j += 1
                    }
                    if overflow { return nil }
                    guard j < chars.count - 1, chars[j] == "}" else { return nil }
                    i = j + 1
                    return (value, String(chars[start..<j + 1]))
                }
                var digits = 0
                while j < chars.count - 1, digits < 2, let d = chars[j].hexDigitValue {
                    value = value * 16 + d; digits += 1; j += 1
                }
                guard digits > 0 else { return nil }
                i = j
                return (value, String(chars[start..<j]))
            }
            switch e {
            case "n": i += 2; return (0x0A, "\\n")
            case "t": i += 2; return (0x09, "\\t")
            case "r": i += 2; return (0x0D, "\\r")
            case "f": i += 2; return (0x0C, "\\f")
            case "a": i += 2; return (0x07, "\\a")
            case "e": i += 2; return (0x1B, "\\e")
            default:
                if e.isLetter || e.isNumber || e == "p" || e == "P" || e == "w" || e == "d" || e == "s" || e == "W" || e == "D" || e == "S" { return nil }
                i += 2
                return (e.unicodeScalars.first.map { Int($0.value) } ?? -1, String(chars[start..<i]))
            }
        }
        if c == "[" || c == "]" { return nil }
        i += 1
        return (c.unicodeScalars.first.map { Int($0.value) } ?? -1, String(c))
    }

    if i < chars.count - 1, chars[i] == "]" {
        members.append((kind: .scalar(0x5D, "]"), text: "]", scalarRanges: [(0x5D, 0x5D)]))
        i += 1
    }
    while i < chars.count - 1 {
        if chars[i] == "[", i + 1 < chars.count - 1, chars[i + 1] == "^" {
            var j = i + 2
            var bail = false
            while j < chars.count - 1, chars[j] != "]" {
                if chars[j] == "\\", j + 1 < chars.count - 1, chars[j + 1] == "]" { bail = true; break }
                j += 1
            }
            if bail || j >= chars.count - 1 { return nil }
            flushScalar()
            let inner = String(chars[(i + 2)..<j])
            members.append((kind: .nested, text: "[^" + inner + "\\uE000-\\uE801]", scalarRanges: [(0, 0x10FFFF)]))
            i = j + 1
            continue
        }
        if chars[i] == "\\", i + 1 < chars.count - 1, chars[i + 1] == "p" || chars[i + 1] == "P" {
            let memberNegated = chars[i + 1] == "P"
            var j = i + 2
            var name = ""
            if j < chars.count - 1, chars[j] == "{" {
                j += 1
                var end = j
                while end < chars.count - 1, chars[end] != "}" { end += 1 }
                guard end < chars.count - 1 else { return nil }
                name = String(chars[j..<end])
                j = end + 1
            } else if j < chars.count - 1, "LMNPSZC".contains(chars[j]) {
                name = String(chars[j])
                j += 1
            } else {
                return nil
            }
            flushScalar()
            if let coverage = jvmRegexMemberSpaceCoverage(name, negated: memberNegated) {
                members.append((kind: .nested, text: coverage.text, scalarRanges: coverage.ranges))
            } else if memberNegated {
                members.append((kind: .nested,
                                text: negated ? "\\P{\(name)}" : "[\\P{\(name)}--[\\uE000-\\uE801]]",
                                scalarRanges: [(0xD800, 0xDFFF), (0xE000, 0xE801)]))
            } else {
                members.append((kind: .nested, text: "\\p{\(name)}", scalarRanges: []))
            }
            i = j
            continue
        }
        if chars[i] == "-" {
            if pendingScalar != nil, i + 1 < chars.count - 1 {
                let prev = pendingScalar!
                let dashStart = i
                i += 1
                if let next = parseAtom() {
                    members.append((kind: .rangeSet, text: prev.1 + "-" + next.1,
                                    scalarRanges: [(min(prev.0, next.0), max(prev.0, next.0))]))
                    pendingScalar = nil
                    continue
                }
                i = dashStart
            }
            flushScalar()
            pendingScalar = (0x2D, "-")
            i += 1
            continue
        }
        if let atom = parseAtom() {
            flushScalar()
            pendingScalar = (value: atom.0, text: atom.1)
            continue
        }
        return nil
    }
    flushScalar()

    for m in members { scalarRanges.append(contentsOf: m.scalarRanges) }
    let covered = regexMergeScalarRanges(scalarRanges)
    let surrogateSpace = (0xD800, 0xDFFF)
    let markerSpace = (0xE000, 0xE801)
    let coveredSurrogates = negated
        ? regexSubtractAllMarkerSpace([surrogateSpace], covered)
        : regexIntersectMarkerSpace(covered, surrogateSpace)
    let coveredPrivate = negated
        ? regexSubtractAllMarkerSpace([markerSpace], covered)
        : regexIntersectMarkerSpace(covered, markerSpace)

    let hasMarkerMembers = covered.contains { $0.0 <= markerSpace.1 && $0.1 >= markerSpace.0 }
    if !negated, coveredSurrogates.isEmpty, coveredPrivate.isEmpty, !hasMarkerMembers {
        return nil
    }

    var plain = negated ? "^" : ""
    for m in members {
        switch m.kind {
        case .rangeSet:
            for r in regexSubtractMarkerSpace(m.scalarRanges, markerSpace) {
                plain += regexMarkerRangeEscape(r.0, r.1)
            }
        case .scalar(let v, let text):
            if (markerSpace.0 ... markerSpace.1).contains(v) { continue }
            plain += text
        case .nested:
            plain += m.text
        }
    }
    if negated {
        plain += "\\uE000-\\uE801"
    }
    var alts: [String] = []
    for r in regexMergeScalarRanges(coveredSurrogates) {
        alts.append("\\uE800[\(regexMarkerRangeEscape(0xE000 + r.0 - 0xD800, 0xE000 + r.1 - 0xD800))]")
    }
    if !coveredPrivate.isEmpty {
        let merged = regexMergeScalarRanges(coveredPrivate)
        let inner = merged.map { regexMarkerRangeEscape($0.0, $0.1) }.joined()
        alts.append("\\uE801[\(inner)]")
    }
    if alts.isEmpty {
        return "[\(plain)]"
    }
    // `plain` can be empty when every member moved into pair alternatives
    // (e.g. `[\uE005]`); an empty `[]` is a syntax error in ICU.
    let plainPart = plain.isEmpty ? "" : "[\(plain)]|"
    return "(?:\(plainPart)\(alts.joined(separator: "|")))"
}

func regexSubtractAllMarkerSpace(_ spaces: [(Int, Int)], _ covered: [(Int, Int)]) -> [(Int, Int)] {
    var remaining = spaces
    for c in covered {
        var next: [(Int, Int)] = []
        for r in remaining {
            if r.1 < c.0 || r.0 > c.1 { next.append(r); continue }
            if r.0 < c.0 { next.append((r.0, c.0 - 1)) }
            if r.1 > c.1 { next.append((c.1 + 1, r.1)) }
        }
        remaining = next
    }
    return remaining
}
