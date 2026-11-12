import Foundation
import RuntimeABI


final class RuntimeRegexBox {
    let regex: NSRegularExpression
    let pattern: String
    /// When true, input strings are NFC-normalized before matching to emulate
    /// Kotlin's `RegexOption.CANON_EQ` (Unicode canonical equivalence).
    /// The pattern itself is also NFC-normalized at creation time.
    let canonEq: Bool
    /// The Kotlin `RegexOption` ordinals this regex was created with.
    /// Used by the `Regex.options` property to reconstruct the original
    /// `Set<RegexOption>`.
    let optionOrdinals: Set<Int>

    /// Guards the lazily-initialized caches below. `regex`/`pattern`/`optionOrdinals`
    /// are immutable, so each cached value is computed once and stays stable.
    private let cacheLock = NSLock()
    /// Outer optional tracks whether computation ran; the inner value is the
    /// compiled anchored regex or nil when wrapping the pattern fails to compile.
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

    /// Named capture-group declarations in `pattern`, extracted once on first use
    /// instead of rescanning the pattern for every produced MatchResult.
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
    /// Per-group MatchGroup data (index 0 = entire match, 1.. = capture groups).
    let groups: [RuntimeMatchGroupBox?]
    /// Named capture group name -> group index mapping.
    let namedGroups: [String: Int]
    /// Names declared by the pattern, including groups that did not participate.
    let namedGroupNames: Set<String>
    /// The original input string (for next() iteration).
    let inputString: String?
    /// UTF-16 length of `inputString`, cached so the next() chain does not
    /// recompute it on every step. Unused when `inputString` is nil.
    let inputUTF16Count: Int
    /// The end position in the input string where this match ended (UTF-16 offset, for next() iteration).
    let matchEndOffset: Int
    /// The regex box used to produce this match (for next() iteration).
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

/// Stores the matched value and the range as (start, endInclusive) indices.
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


/// Fixed ICU/NSRegularExpression pattern that never matches any input.
///
/// Used when a user-supplied pattern fails to compile: Kotlin's `Regex` constructor
/// throws `PatternSyntaxException` on invalid syntax; this runtime substitutes a
/// never-match regex so subsequent `find`/`matches` calls return empty results
/// instead of crashing.
///
/// `(?!)` is a negative lookahead with an empty sub-expression — always
/// unsatisfiable. It is independent of user input and is valid POSIX/ICU regex
/// syntax, so `NSRegularExpression` compilation cannot fail for this literal.
private enum RegexNeverMatch {
    static let expression: NSRegularExpression = {
        // "(?!)" is a static literal independent of user input — provably valid
        // ICU/POSIX syntax. If this fails, Foundation itself is broken.
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

/// NSString-backed string that keeps isolated surrogates as real UTF-16 code
/// units for ICU — `String(decoding:as:)` would repair them to U+FFFD, which
/// is why property matches like `\p{Cs}` used to miss them (KUU-4319). Its
/// UTF-16 layout is identical to the `units` it was built from.
private func regexICUString(_ units: [UInt16]) -> String {
    guard !units.isEmpty else { return "" }
    return units.withUnsafeBufferPointer { buffer in
        NSString(characters: buffer.baseAddress!, length: buffer.count) as String
    }
}

/// UTF-16 code units of an ICU-domain string. `String.utf16` reports U+FFFD
/// for unpaired surrogates, so the units are recovered through NSString,
/// which preserves them.
private func regexUTF16Units(ofICUString value: String) -> [UInt16] {
    let nsString = value as NSString
    var units = [unichar](repeating: 0, count: nsString.length)
    nsString.getCharacters(&units, range: NSRange(location: 0, length: nsString.length))
    return units
}

/// A regex match subject: `icu` is the string handed to
/// `NSRegularExpression` (surrogate-preserving), and `units` holds the Kotlin
/// UTF-16 code units that ICU match ranges index into 1:1.
private struct RegexSubject {
    let icu: String
    let units: [UInt16]

    init(encoded: String) {
        let units = runtimeKotlinStringUTF16CodeUnits(encoded)
        self.units = units
        icu = regexICUString(units)
    }

    init(icu: String, units: [UInt16]) {
        self.icu = icu
        self.units = units
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
    // `NSRegularExpression` rejects an empty pattern, and a `(?U)`-only pattern
    // translates to empty as well, so fall back to the equivalent
    // non-capturing empty group `(?:)` in both cases.
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
    let translated = translateJavaPatternForICU(source)
    let effective = translated.isEmpty ? "(?:)" : translated
    // The translated pattern is still Kotlin marker-encoded; hand ICU the
    // UTF-16 form so literal surrogate characters in the pattern survive.
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
func translateJavaPatternForICU(_ pattern: String, unicodeCharacterClassesInitially: Bool = false) -> String {
    var unicodeClasses = unicodeCharacterClassesInitially
    var savedModes: [Bool] = []
    let chars = Array(pattern)
    var out = ""
    out.reserveCapacity(chars.count)
    var index = 0
    var classDepth = 0
    func isFlag(_ c: Character) -> Bool { "idmsuxU".contains(c) }
    while index < chars.count {
        let c = chars[index]
        if c == "\\" {
            if index + 1 < chars.count, chars[index + 1] == "Q" {
                // \Q ... \E literal quote (an unterminated quote runs to the end).
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
                // `\p{Name}` / `\P{Name}`: `jvmRegexICUPropertyReplacement`
                // mirrors `java.util.regex.Pattern#family` — POSIX names get
                // their ASCII expansions outside `(?U)`, `gc=`/`general_category=`
                // values resolve through `forProperty`, `Is*` names follow the
                // JVM's three-stage dispatch, and names ICU cannot express
                // (`LD`, `L1`, `all`, `javaAlphabetic`, `javaLowerCase`,
                // `InSurrogates_Area`, ...) are rewritten to the ICU
                // expression with the same match set (KUU-4295). Emitted as
                // `[...]` classes the expansions are safe in both contexts:
                // nested class inside `[...]`, plain class outside.
                if index + 2 < chars.count, chars[index + 2] == "{" {
                    var end = index + 3
                    while end < chars.count, chars[end] != "}" { end += 1 }
                    if end < chars.count {
                        let name = String(chars[(index + 3)..<end])
                        if let replacement = jvmRegexICUPropertyReplacement(
                            name, negated: escape == "P", unicodeClasses: unicodeClasses
                        ) {
                            out.append(replacement)
                        } else {
                            out.append(contentsOf: chars[index...end])
                        }
                        index = end + 1
                        continue
                    }
                } else if index + 2 < chars.count, "LMNPSZC".contains(chars[index + 2]) {
                    // Unbraced single-letter categories `\pL` / `\PL`: the JVM
                    // accepts exactly one of L M N P S Z C (the major
                    // general-category codes) without braces; ICU requires
                    // them, so the letter is wrapped. Other letters (`\pU`,
                    // `\pl`) are invalid on the JVM too and pass through to
                    // fail compilation the same way.
                    out.append("\\")
                    out.append(escape)
                    out.append("{")
                    out.append(chars[index + 2])
                    out.append("}")
                    index += 3
                    continue
                }
                // Not a `\p{...}` construct (unterminated or missing braces):
                // copy the two-character escape verbatim.
                out.append(contentsOf: chars[index...index + 1])
                index += 2
                continue
            }
            if classDepth > 0 {
                switch escape {
                case "w": out.append(unicodeClasses ? "\\w" : "[a-zA-Z0-9_]")
                case "W": out.append(unicodeClasses ? "\\W" : "[^a-zA-Z0-9_]")
                case "d": out.append(unicodeClasses ? "\\d" : "[0-9]")
                case "D": out.append(unicodeClasses ? "\\D" : "[^0-9]")
                case "s": out.append(unicodeClasses ? "\\s" : "[\\t\\n\\x0B\\f\\r ]")
                case "S": out.append(unicodeClasses ? "\\S" : "[^\\t\\n\\x0B\\f\\r ]")
                default: out.append(contentsOf: chars[index...index + 1])
                }
            } else {
                switch escape {
                case "w": out.append(unicodeClasses ? "\\w" : "[a-zA-Z0-9_]")
                case "W": out.append(unicodeClasses ? "\\W" : "[^a-zA-Z0-9_]")
                case "d": out.append(unicodeClasses ? "\\d" : "[0-9]")
                case "D": out.append(unicodeClasses ? "\\D" : "[^0-9]")
                case "s": out.append(unicodeClasses ? "\\s" : "[ \\t\\n\\x0B\\f\\r]")
                case "S": out.append(unicodeClasses ? "\\S" : "[^ \\t\\n\\x0B\\f\\r]")
                case "b": out.append(unicodeClasses ? unicodeWordBoundaryPattern : asciiWordBoundaryPattern)
                case "B": out.append(unicodeClasses ? unicodeNonWordBoundaryPattern : asciiNonWordBoundaryPattern)
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
            if c == "]" { classDepth -= 1 }
            out.append(c)
            index += 1
            continue
        }
        if c == "[" {
            classDepth = 1
            out.append(c)
            index += 1
            // A leading `^` and a leading `]` are literal members of the class.
            if index < chars.count, chars[index] == "^" { out.append("^"); index += 1 }
            if index < chars.count, chars[index] == "]" { out.append("]"); index += 1 }
            continue
        }
        if c == ")" {
            // Closing a group restores the character-class mode saved when the
            // group opened; bare (?flags) directives set the mode only until
            // this point on the JVM.
            if let saved = savedModes.popLast() {
                unicodeClasses = saved
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
            var seenMinus = false
            while cursor < chars.count {
                let f = chars[cursor]
                if f == "-", !seenMinus { seenMinus = true; cursor += 1; continue }
                guard isFlag(f) else { break }
                if f == "U" {
                    if seenMinus { offUnicode = true } else { onUnicode = true }
                } else if f != "u" {
                    if seenMinus { off.append(f) } else { on.append(f) }
                }
                cursor += 1
            }
            let isFlagGroup = cursor > index + 2
                && cursor < chars.count
                && (chars[cursor] == ")" || chars[cursor] == ":")
            if isFlagGroup {
                let terminator = chars[cursor]
                // `(?flags:` opens a scoped group: save the enclosing mode, then
                // apply this group's own flags. A bare `(?flags)` retargets the
                // mode in place (the enclosing `)` restores it via savedModes).
                if terminator == ":" { savedModes.append(unicodeClasses) }
                if onUnicode { unicodeClasses = true }
                if offUnicode { unicodeClasses = false }
                if on.isEmpty && off.isEmpty {
                    // `(?U)` vanishes entirely; `(?U:...)` becomes a plain non-capturing group.
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
            // Some other `(?...)` construct (lookaround, named group, atomic
            // group, ...): it still opens a group on the JVM, so flag
            // directives inside it end at its `)`.
            savedModes.append(unicodeClasses)
            out.append(c)
            index += 1
            continue
        }
        if c == "(" {
            savedModes.append(unicodeClasses)
            out.append(c)
            index += 1
            continue
        }
        out.append(c)
        index += 1
    }
    return out
}

/// Removes the `java.util.regex` inline flags that ICU does not know about.
///
/// Kept for existing callers/tests as a narrow wrapper around
/// ``translateJavaPatternForICU`` with Unicode character classes enabled
/// initially: predefined class escapes pass through verbatim, so for patterns
/// without `\b` / `\B` / `(?-U)` this reduces to the historical flag-stripping
/// behaviour.
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

/// Detector for `(?<name>...)` named-group declarations, compiled once
/// process-wide — ICU compilation dwarfs the cost of the pattern scan itself.
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

/// Kotlin/Java replacement strings expand `${name}` (and `${n}`) to capture
/// groups. `NSRegularExpression.replacementString` only understands `$n`, so
/// rewrite the Kotlin form before handing the template to Foundation.
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

/// `template` is the Kotlin-encoded replacement text; the result is the
/// ICU-domain string `NSRegularExpression` produces (recover its UTF-16 units
/// with `regexUTF16Units(ofICUString:)` before storing or returning it).
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

/// `inputUTF16Count` may carry the caller's already-computed UTF-16 length of
/// the subject; omitting it recomputes it once here.
private func makeMatchResult(from result: NSTextCheckingResult, in subject: RegexSubject, regexBox: RuntimeRegexBox? = nil, inputUTF16Count: Int? = nil) -> RuntimeMatchResultBox {
    // NSRegularExpression only returns matches whose ranges are within the matched string,
    // so this conversion should never fail in practice.
    func groupString(_ range: NSRange) -> String? {
        guard range.location != NSNotFound, range.length >= 0,
              range.location >= 0, range.location + range.length <= subject.units.count
        else { return nil }
        return runtimeKotlinStringFromUTF16CodeUnits(
            Array(subject.units[range.location ..< range.location + range.length])
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
        if let groupValue = groupString(groupRange) {
            groupValues.append(groupValue)
            // NSTextCheckingResult locations/lengths are UTF-16 offsets into
            // the subject, matching Kotlin's String indexing.
            let startIndex = groupRange.location
            let endIndex = groupRange.location + groupRange.length - 1
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

    let matchEnd = result.range.location + result.range.length

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
    runtimeRegexCreate(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        outThrown: outThrown
    )
}


private func runtimeRegexCreate(pattern: String, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let regex = try? compileRegexPattern(pattern, options: []) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Illegal pattern: \(pattern)"
        )
        return 0
    }
    return registerRuntimeObject(RuntimeRegexBox(regex: regex, pattern: pattern))
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
    let range = NSRange(location: 0, length: subject.units.count)
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
    let range = NSRange(location: 0, length: subject.units.count)
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
    let range = NSRange(location: 0, length: subject.units.count)
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
    let range = NSRange(location: 0, length: subject.units.count)
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
    outThrown?.pointee = 0
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    let replacement = regexStringFromRaw(replacementRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeMakeStringRaw(rawStr) }
    let normalized = regexBox.normalizeIfNeeded(rawStr)
    let subject = RegexSubject(encoded: normalized)
    let range = NSRange(location: 0, length: subject.units.count)
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
        let location = match.range.location
        let length = match.range.length
        guard location >= cursor, location >= 0, length >= 0,
              location + length <= subject.units.count else { continue }
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
    let range = NSRange(location: 0, length: subject.units.count)
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
        let location = match.range.location
        let length = match.range.length
        guard location >= cursor, location >= 0, length >= 0,
              location + length <= subject.units.count else { continue }
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
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return strRaw }
    let normalized = regexBox.normalizeIfNeeded(rawStr)
    let subject = RegexSubject(encoded: normalized)
    let range = NSRange(location: 0, length: subject.units.count)
    let matches = boundedMatches(regexBox.regex, in: subject.icu, options: [], range: range)
    guard let matches else { return strRaw }
    if matches.isEmpty { return strRaw }
    var resultUnits: [UInt16] = []
    resultUnits.reserveCapacity(subject.units.count)
    var cursor = 0
    let utf16Count = subject.units.count
    for match in matches {
        let location = match.range.location
        let length = match.range.length
        guard location >= cursor, location >= 0, length >= 0,
              location + length <= subject.units.count else { continue }
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
    let range = NSRange(location: 0, length: subject.units.count)
    guard let result = boundedFirstMatch(anchoredRegex, in: subject.icu, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    guard result.range.location == 0, result.range.length == subject.units.count else {
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
    case 0: return .caseInsensitive          // IGNORE_CASE
    case 1: return .anchorsMatchLines        // MULTILINE
    case kRegexOptionOrdinalLiteral: return []  // LITERAL (handled via escapedPattern)
    case 3: return .useUnixLineSeparators        // UNIX_LINES
    case 4: return .allowCommentsAndWhitespace   // COMMENTS
    case 5: return .dotMatchesLineSeparators     // DOT_MATCHES_ALL
    case kRegexOptionOrdinalCanonEq: return []   // CANON_EQ (handled via NFC normalization)
    default:
        assertionFailure("KSwiftK: unknown RegexOption ordinal \(ordinal) – compiler/runtime enum mismatch?")
        return []
    }
}

/// Returns `nil` and sets `outThrown` to an `IllegalArgumentException` on compile failure.
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
    runtimeRegexCreateWithOption(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionRaw: optionRaw,
        outThrown: outThrown
    )
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
    runtimeRegexCreateWithOption(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionRaw: optionRaw,
        outThrown: outThrown
    )
}

private func runtimeRegexCreateWithOption(pattern: String, optionRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
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


/// Creates a Regex from a pattern and a `Set<RegexOption>`.
@_cdecl("__kk_regex_create_with_options_flat")
public func kk_regex_create_with_options_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionsSetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRegexCreateWithOptions(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionsSetRaw: optionsSetRaw,
        outThrown: outThrown
    )
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
    runtimeRegexCreateWithOptions(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionsSetRaw: optionsSetRaw,
        outThrown: outThrown
    )
}

private func runtimeRegexCreateWithOptions(pattern: String, optionsSetRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
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
    let range = NSRange(location: 0, length: subject.units.count)
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
    kk_regex_create_flat(data, length, byteCount, hash, outThrown)
}


//
// The public `Regex.pattern` / `Regex.options` / `Regex.groupNames` accessors and
// the whole MatchResult / MatchGroup / MatchGroupCollection / Destructured API
// live in `Sources/CompilerCore/Stdlib/kotlin/text/MatchResult.kt`. Only the raw
// data that the Foundation match engine owns is exposed here.

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


/// Number of groups in the match, including group 0 (the entire match).
@_cdecl("__kk_match_result_group_count")
public func __kk_match_result_group_count(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return 0 }
    return matchResult.groupValues.count
}

/// Text of group [index], or the empty string when the group is absent.
@_cdecl("__kk_match_result_group_value")
public func __kk_match_result_group_value(_ matchRaw: Int, _ index: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          index >= 0, index < matchResult.groupValues.count else {
        return runtimeMakeUTF8StringRaw("")
    }
    return runtimeMakeStringRaw(matchResult.groupValues[index])
}

/// UTF-16 start offset of group [index], or -1 when the group did not participate.
@_cdecl("__kk_match_result_group_start")
public func __kk_match_result_group_start(_ matchRaw: Int, _ index: Int) -> Int {
    guard let group = matchResultGroup(matchRaw, index) else { return -1 }
    return group.rangeStart
}

/// UTF-16 end offset (inclusive) of group [index], or -1 when the group did not participate.
@_cdecl("__kk_match_result_group_end")
public func __kk_match_result_group_end(_ matchRaw: Int, _ index: Int) -> Int {
    guard let group = matchResultGroup(matchRaw, index) else { return -1 }
    return group.rangeEnd
}

/// Index of the capture group named [nameRaw], or -1 when there is no such group.
@_cdecl("__kk_match_result_group_index_of_name")
public func __kk_match_result_group_index_of_name(_ matchRaw: Int, _ nameRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let name = regexStringFromRaw(nameRaw),
          let index = matchResult.namedGroups[name] else {
        return -1
    }
    return index
}

/// Whether the regex pattern declares a capture group named [nameRaw].
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
    let range = NSRange(location: offset, length: utf16Count - offset)
    guard let result = boundedFirstMatch(
        regexBox.regex,
        in: inputString,
        options: [.withoutAnchoringBounds, .withTransparentBounds],
        range: range
    ) else {
        return runtimeNullSentinelInt
    }
    // `inputString` is the ICU-domain subject; recover the Kotlin UTF-16
    // units its match ranges index into.
    let subject = RegexSubject(
        icu: inputString,
        units: regexUTF16Units(ofICUString: inputString)
    )
    return registerRuntimeMatchResult(makeMatchResult(from: result, in: subject, regexBox: regexBox, inputUTF16Count: utf16Count))
}


/// Kotlin's `fromLiteral` is `Regex(literal, RegexOption.LITERAL)`: keep the
/// original literal as `.pattern` / `toString()`, and escape only when compiling
/// the Foundation matcher. The first argument is the Companion receiver
/// (ignored; companion singleton).
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
    outThrown?.pointee = 0
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    let replacement = regexStringFromRaw(replacementRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeMakeStringRaw(rawStr) }
    let normalized = regexBox.normalizeIfNeeded(rawStr)
    let subject = RegexSubject(encoded: normalized)
    let range = NSRange(location: 0, length: subject.units.count)
    guard let match = boundedFirstMatch(regexBox.regex, in: subject.icu, options: [], range: range),
          match.range.location >= 0, match.range.length >= 0,
          match.range.location + match.range.length <= subject.units.count else {
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
    let location = match.range.location
    let length = match.range.length
    var resultUnits = subject.units
    resultUnits.replaceSubrange(location ..< location + length, with: regexUTF16Units(ofICUString: templateResult))
    return runtimeMakeStringRaw(runtimeKotlinStringFromUTF16CodeUnits(resultUnits))
}


/// Uses the compiled effective pattern from `regexBox.regex.pattern` (which is
/// already escaped for LITERAL regexes) wrapped in `\A(?:...)\z` to force a
/// full-string match. This correctly handles:
///
/// - **Alternation**: `firstMatch` may find only the first alternative (e.g. "a"
///   for pattern `a|ab`), returning a partial match. Wrapping with `\A...\z`
///   forces the engine to match the entire input.
/// - **MULTILINE**: `.anchorsMatchLines` makes `^`/`$` match line boundaries,
///   not string boundaries. Using `\A`/`\z` avoids this. The option is stripped
///   from the anchored regex so `\A`/`\z` bind to the full string.
/// - **LITERAL**: LITERAL regexes in this runtime are compiled by passing the
///   pre-escaped pattern (via `NSRegularExpression.escapedPattern`) to
///   `NSRegularExpression` without `.ignoreMetacharacters`. Therefore
///   `regexBox.regex.pattern` already holds the escaped form and can be embedded
///   directly. `.ignoreMetacharacters` is stripped from the anchored options
///   (it is never set in practice, but removing it defensively ensures the
///   `\A(?:...)\z` wrapper is always parsed as regex syntax, not literal text.
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
    let range = NSRange(location: 0, length: subject.units.count)
    let matched = boundedFirstMatch(anchoredRegex, in: subject.icu, options: [], range: range) != nil
    return kk_box_bool(matched ? 1 : 0)
}


// `MatchResult.Destructured` carries no state beyond the match it destructures,
// so it is represented by the MatchResult object itself. `component1()`..
// `component9()` are derived in Kotlin from the raw group values above.

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
