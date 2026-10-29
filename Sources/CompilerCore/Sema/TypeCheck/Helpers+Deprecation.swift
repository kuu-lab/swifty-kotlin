import Foundation

private struct KotlinCompilerVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    static func < (lhs: KotlinCompilerVersion, rhs: KotlinCompilerVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            return nil
        }
        let patch = components.count == 3 ? Int(components[2]) : 0
        guard let patch, major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}

// @SinceKotlin availability and @DeprecatedSinceKotlin thresholds use the
// compiler's default -api-version, not its build version. kotlinc 2.4.20 (the
// reference compiler pinned by CI) defaults to apiVersion 2.4: it rejects
// `Number.toChar()` (errorSince = "2.3") at the call site. Keep in sync if
// the pinned kotlinc's default api-version changes.
private let kotlinApiVersion = KotlinCompilerVersion(major: 2, minor: 4, patch: 0)

extension TypeCheckHelpers {
    private enum DeprecatedLevel {
        case warning
        case error
        case hidden
    }

    private struct DeprecatedArguments {
        let message: String
        let level: DeprecatedLevel
        let replaceWith: String?
    }

    private struct DeprecatedSinceKotlinArguments {
        let warningSince: KotlinCompilerVersion?
        let errorSince: KotlinCompilerVersion?
        let hiddenSince: KotlinCompilerVersion?
    }

    /// `@Deprecated("msg", level = HIDDEN)` -> error; the declaration still
    /// resolves (lookup hiding is not modelled), so the deprecated diagnostic
    /// stands in for kotlinc's "unresolved reference".
    func checkDeprecation(
        for symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        checkDeprecation(
            for: symbolID,
            symbols: sema.symbols,
            interner: interner,
            range: range,
            diagnostics: diagnostics
        )
    }

    func checkDeprecation(
        for symbolID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let directAnnotations = symbols.annotations(for: symbolID)
        let owner = symbols.symbol(symbolID)?.kind == .constructor
            ? symbols.parentSymbol(for: symbolID)
            : nil
        let ownerAnnotations = owner.map { symbols.annotations(for: $0) } ?? []
        let annotations = directAnnotations + ownerAnnotations
        func controlsSourceAvailability(_ annotation: MetadataAnnotationRecord) -> Bool {
            KnownCompilerAnnotation.deprecated.matches(annotation.annotationFQName)
                || KnownCompilerAnnotation.deprecatedSinceKotlin.matches(annotation.annotationFQName)
                || KnownCompilerAnnotation.sinceKotlin.matches(annotation.annotationFQName)
        }
        guard annotations.contains(where: controlsSourceAvailability) else {
            return
        }
        let annotationSymbolID: SymbolID = {
            if directAnnotations.contains(where: {
                KnownCompilerAnnotation.deprecated.matches($0.annotationFQName)
            }) {
                return symbolID
            }
            if let owner,
               ownerAnnotations.contains(where: {
                   KnownCompilerAnnotation.deprecated.matches($0.annotationFQName)
               })
            {
                return owner
            }
            if directAnnotations.contains(where: controlsSourceAvailability) {
                return symbolID
            }
            return owner ?? symbolID
        }()

        let symbolName = if let sym = symbols.symbol(annotationSymbolID) {
            sym.fqName.map { interner.resolve($0) }.joined(separator: ".")
        } else {
            "<unknown>"
        }
        let stringValue = { (raw: String) in
            normalizeAnnotationStringArgument(
                raw,
                annotatedSymbol: annotationSymbolID,
                symbols: symbols,
                interner: interner
            )
        }
        if let sinceKotlin = annotations.first(where: {
            KnownCompilerAnnotation.sinceKotlin.matches($0.annotationFQName)
        }), let sinceVersion = parseSinceKotlinVersion(sinceKotlin.arguments, stringValue: stringValue),
           kotlinApiVersion < sinceVersion
        {
            diagnostics.error(
                "KSWIFTK-SEMA-API-VERSION",
                "'\(symbolName)' is only available since Kotlin \(sinceVersion.description).",
                range: range
            )
            return
        }

        let deprecatedAnnotation = annotations.first(where: {
            KnownCompilerAnnotation.deprecated.matches($0.annotationFQName)
        })
        let deprecatedSinceAnnotation = annotations.first(where: {
            KnownCompilerAnnotation.deprecatedSinceKotlin.matches($0.annotationFQName)
        })
        guard let deprecatedAnnotation else {
            return
        }
        let parsed = parseDeprecatedArguments(deprecatedAnnotation.arguments, stringValue: stringValue)
        let sinceArguments = deprecatedSinceAnnotation.map {
            parseDeprecatedSinceKotlinArguments($0.arguments, stringValue: stringValue)
        }

        // An explicit @Deprecated(level = ERROR/HIDDEN) remains authoritative.
        // The SinceKotlin metadata only refines the default warning level used
        // by the stdlib as the target compiler version advances.
        let severity: DeprecatedSeverity
        switch parsed.level {
        case .error:
            severity = .error
        case .hidden:
            severity = .hidden
        case .warning:
            if let sinceArguments {
                severity = deprecatedSeverity(for: sinceArguments)
            } else {
                severity = .warning
            }
        }
        guard severity != .none else {
            return
        }

        var deprecationMessage = parsed.message.isEmpty
            ? "'\(symbolName)' is deprecated."
            : "'\(symbolName)' is deprecated. \(parsed.message)"
        let codeActions: [DiagnosticCodeAction]
        if let replaceWith = parsed.replaceWith, !replaceWith.isEmpty {
            deprecationMessage += " Replace with: \(replaceWith)"
            codeActions = [DiagnosticCodeAction(title: "Replace with '\(replaceWith)'")]
        } else {
            codeActions = []
        }

        if severity == .error || severity == .hidden {
            diagnostics.error(
                "KSWIFTK-SEMA-DEPRECATED",
                deprecationMessage,
                range: range,
                codeActions: codeActions
            )
        } else {
            diagnostics.warning(
                "KSWIFTK-SEMA-DEPRECATED",
                deprecationMessage,
                range: range,
                codeActions: codeActions
            )
        }
        return // Only emit one deprecation diagnostic per symbol reference.
    }

    /// Emits the deprecation diagnostic for the built-in `toChar()` on the
    /// given receiver and returns the metadata-carrying declaration it was
    /// checked against, so callers that bind no callee through ordinary
    /// overload resolution can still bind the call (KUU-3763).
    @discardableResult
    func checkBuiltinDeprecation(
        calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) -> SymbolID? {
        let callee = interner.resolve(calleeName)
        guard callee == "toChar" else {
            return nil
        }

        let receiver = sema.types.makeNonNullable(receiverType)
        // No unsigned type has a real `toChar()` member. Int's decl is not
        // deprecated upstream, so the lookup no-ops on it; Byte/Short carry
        // the same error-level deprecation metadata as Long (KUU-3763).
        let deprecatedReceiverTypes: Set<TypeID> = [
            sema.types.intType,
            sema.types.longType,
            sema.types.byteType,
            sema.types.shortType,
        ]
        guard deprecatedReceiverTypes.contains(receiver) else {
            return nil
        }

        let toCharFQName: [InternedString] = [interner.intern("kotlin"), calleeName]
        guard let symbolID = sema.symbols.lookupAll(fqName: toCharFQName).first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == receiver
        }) else {
            return nil
        }

        checkDeprecation(
            for: symbolID,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: diagnostics
        )
        return symbolID
    }

    private func parseDeprecatedArguments(
        _ arguments: [String],
        stringValue: (String) -> String
    ) -> DeprecatedArguments {
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []

        for raw in arguments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if let (name, value) = splitNamedArgument(trimmed) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(trimmed)
            }
        }

        let messageCandidate = namedArgs["message"] ?? positionalArgs.first
        let message = messageCandidate.map(stringValue) ?? ""

        let levelCandidate = namedArgs["level"] ?? positionalArgs.first(where: { parseDeprecatedLevel($0) != nil })
        let level = parseDeprecatedLevel(levelCandidate) ?? .warning
        let replaceWithCandidate = namedArgs["replacewith"]
            ?? positionalArgs.first(where: { isReplaceWithExpression($0) })
        let replaceWith = parseReplaceWithExpression(replaceWithCandidate, stringValue: stringValue)

        return DeprecatedArguments(message: message, level: level, replaceWith: replaceWith)
    }

    private enum DeprecatedSeverity {
        case none
        case warning
        case error
        case hidden
    }

    private func parseDeprecatedSinceKotlinArguments(
        _ arguments: [String],
        stringValue: (String) -> String
    ) -> DeprecatedSinceKotlinArguments {
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []

        for raw in arguments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if let (name, value) = splitNamedArgument(trimmed) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(trimmed)
            }
        }

        func parseVersion(_ raw: String?) -> KotlinCompilerVersion? {
            guard let raw else {
                return nil
            }
            let normalized = stringValue(raw)
            guard !normalized.isEmpty else {
                return nil
            }
            return KotlinCompilerVersion(rawValue: normalized)
        }

        func positional(_ index: Int) -> String? {
            positionalArgs.indices.contains(index) ? positionalArgs[index] : nil
        }

        return DeprecatedSinceKotlinArguments(
            warningSince: parseVersion(namedArgs["warningsince"] ?? positional(0)),
            errorSince: parseVersion(namedArgs["errorsince"] ?? positional(1)),
            hiddenSince: parseVersion(namedArgs["hiddensince"] ?? positional(2))
        )
    }

    private func parseSinceKotlinVersion(
        _ arguments: [String],
        stringValue: (String) -> String
    ) -> KotlinCompilerVersion? {
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []

        for raw in arguments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if let (name, value) = splitNamedArgument(trimmed) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(trimmed)
            }
        }

        guard let raw = namedArgs["version"] ?? positionalArgs.first else {
            return nil
        }
        return KotlinCompilerVersion(rawValue: stringValue(raw))
    }

    private func deprecatedSeverity(for arguments: DeprecatedSinceKotlinArguments) -> DeprecatedSeverity {
        if let hiddenSince = arguments.hiddenSince, kotlinApiVersion >= hiddenSince {
            return .hidden
        }
        if let errorSince = arguments.errorSince, kotlinApiVersion >= errorSince {
            return .error
        }
        if let warningSince = arguments.warningSince, kotlinApiVersion >= warningSince {
            return .warning
        }
        // A SinceKotlin annotation keeps the declaration available without a
        // deprecation diagnostic until its first visible threshold is reached.
        if arguments.warningSince != nil || arguments.errorSince != nil || arguments.hiddenSince != nil {
            return .none
        }
        return .warning
    }

    private func splitNamedArgument(_ argument: String) -> (String, String)? {
        guard let equalIndex = firstTopLevelIndex(of: "=", in: argument) else {
            return nil
        }
        let name = argument[..<equalIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = argument[argument.index(after: equalIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else {
            return nil
        }
        return (name, value)
    }

    private func parseDeprecatedLevel(_ raw: String?) -> DeprecatedLevel? {
        guard var raw else {
            return nil
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = normalizeAnnotationStringLiteral(raw)
        let normalized = raw.replacingOccurrences(of: " ", with: "")
        let levelName = normalized.split(separator: ".").last.map(String.init)?.uppercased() ?? normalized.uppercased()
        return switch levelName {
        case "WARNING":
            .warning
        case "ERROR":
            .error
        case "HIDDEN":
            .hidden
        default:
            nil
        }
    }

    private func isReplaceWithExpression(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix(KnownCompilerAnnotation.replaceWith.simpleName + "(")
            || normalized.hasPrefix(KnownCompilerAnnotation.replaceWith.qualifiedName + "(")
    }

    private func parseReplaceWithExpression(
        _ raw: String?,
        stringValue: (String) -> String
    ) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReplaceWithExpression(trimmed),
              let lParen = trimmed.firstIndex(of: "("),
              let rParen = trimmed.lastIndex(of: ")"),
              lParen < rParen
        else {
            return nil
        }

        let innerStart = trimmed.index(after: lParen)
        let inner = String(trimmed[innerStart..<rParen])
        let arguments = splitAnnotationArguments(inner)
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []
        for argument in arguments {
            if let (name, value) = splitNamedArgument(argument) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(argument)
            }
        }

        let expressionCandidate = namedArgs["expression"] ?? positionalArgs.first
        let expression = expressionCandidate.map(stringValue) ?? ""
        return expression.isEmpty ? nil : expression
    }

    private func splitAnnotationArguments(_ raw: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var inString = false
        var stringDelimiter: Character?
        var previousWasEscape = false

        for character in raw {
            current.append(character)
            if inString {
                if character == "\\" && !previousWasEscape {
                    previousWasEscape = true
                    continue
                }
                if character == stringDelimiter && !previousWasEscape {
                    inString = false
                    stringDelimiter = nil
                }
                previousWasEscape = false
                continue
            }

            switch character {
            case "\"", "'":
                inString = true
                stringDelimiter = character
                previousWasEscape = false
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            case "," where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                current.removeLast()
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    arguments.append(trimmed)
                }
                current = ""
            default:
                break
            }
        }

        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            arguments.append(trailing)
        }
        return arguments
    }

    private func firstTopLevelIndex(of character: Character, in raw: String) -> String.Index? {
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var inString = false
        var stringDelimiter: Character?
        var previousWasEscape = false

        for index in raw.indices {
            let current = raw[index]
            if inString {
                if current == "\\" && !previousWasEscape {
                    previousWasEscape = true
                    continue
                }
                if current == stringDelimiter && !previousWasEscape {
                    inString = false
                    stringDelimiter = nil
                }
                previousWasEscape = false
                continue
            }

            switch current {
            case "\"", "'":
                inString = true
                stringDelimiter = current
                previousWasEscape = false
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if current == character,
               parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0
            {
                return index
            }
        }
        return nil
    }

    /// Annotation arguments reach here as raw source text, so a `const val`
    /// reference like `@Deprecated(MSG)` arrives unevaluated as the bare
    /// identifier.
    private func normalizeAnnotationStringArgument(
        _ raw: String,
        annotatedSymbol symbolID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        if let resolved = resolveStringConstantReference(
            raw,
            annotatedSymbol: symbolID,
            symbols: symbols,
            interner: interner
        ) {
            return resolved
        }
        return normalizeAnnotationStringLiteral(raw)
    }

    /// The argument is looked up in the lexical scope of the annotated
    /// declaration: the declaration's innermost container first, then outward
    /// through its package to the root.
    private func resolveStringConstantReference(
        _ raw: String,
        annotatedSymbol symbolID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // String literals are handled by normalizeAnnotationStringLiteral.
        guard extractKotlinStringLiteralContent(value) == nil else {
            return nil
        }
        let components = value.split(separator: ".").map(String.init)
        guard !components.isEmpty,
              components.joined(separator: ".") == value,
              components.allSatisfy(isSimpleKotlinIdentifier),
              let annotated = symbols.symbol(symbolID)
        else {
            return nil
        }

        let annotatedFileID = symbols.sourceFileID(for: symbolID)
        let path = components.map { interner.intern($0) }
        var container = Array(annotated.fqName.dropLast())
        while true {
            if let resolved = lookupStringConstant(
                fqName: container + path,
                annotatedFileID: annotatedFileID,
                symbols: symbols,
                interner: interner
            ) {
                return resolved
            }
            if container.isEmpty {
                return nil
            }
            container.removeLast()
        }
    }

    private func lookupStringConstant(
        fqName: [InternedString],
        annotatedFileID: FileID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String? {
        var fallback: String?
        for candidateID in symbols.lookupAll(fqName: fqName) {
            guard let candidate = symbols.symbol(candidateID),
                  case let .stringLiteral(literal)? = symbols.constValueExprKind(for: candidateID)
            else {
                continue
            }
            // A `private` top-level const is file-scoped, so it can only be
            // referenced from the same file as the annotated declaration;
            // same-file candidates are also preferred when the FQName is
            // shared by declarations in several files.
            let sameFile = symbols.sourceFileID(for: candidateID) == annotatedFileID
            if candidate.visibility == .private && !sameFile {
                continue
            }
            if sameFile {
                return interner.resolve(literal)
            }
            if fallback == nil {
                fallback = interner.resolve(literal)
            }
        }
        return fallback
    }

    private func isSimpleKotlinIdentifier(_ component: String) -> Bool {
        guard let first = component.first, first.isLetter || first == "_" else {
            return false
        }
        return component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    func normalizeAnnotationStringLiteral(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Annotation arguments are rebuilt from raw tokens. Raw strings must
        // not be escape-decoded; regular strings are decoded like any other
        // Kotlin string literal.
        if let extraction = extractKotlinStringLiteralContent(value) {
            return extraction.isRaw ? extraction.content : decodeKotlinStringEscapes(extraction.content)
        }

        return decodeKotlinStringEscapes(value)
    }
}

/// Hidden declarations remain in metadata for binary compatibility, while
/// APIs newer than the selected Kotlin API version stay out of source lookup.
/// This also keeps factory/constructor pairs with the same signature unambiguous.
func isHiddenByDeprecationOrVersionAnnotation(_ symbol: SymbolID, symbols: SymbolTable) -> Bool {
    let directAnnotations = symbols.annotations(for: symbol)
    let owner = symbols.symbol(symbol)?.kind == .constructor
        ? symbols.parentSymbol(for: symbol)
        : nil
    let annotations = directAnnotations + (owner.map { symbols.annotations(for: $0) } ?? [])

    if let sinceKotlin = annotations.first(where: {
        KnownCompilerAnnotation.sinceKotlin.matches($0.annotationFQName)
    }), let version = parseMetadataVersionArgument(sinceKotlin.arguments, parameterName: "version"),
       version > kotlinApiVersion
    {
        return true
    }

    guard annotations.contains(where: {
        KnownCompilerAnnotation.deprecated.matches($0.annotationFQName)
    }) else {
        return false
    }

    if let since = annotations.first(where: {
        KnownCompilerAnnotation.deprecatedSinceKotlin.matches($0.annotationFQName)
    }) {
        for (index, argument) in since.arguments.enumerated() {
            let pieces = argument.split(separator: "=", maxSplits: 1).map(String.init)
            let value: String
            if pieces.count == 2 {
                guard pieces[0].trimmingCharacters(in: .whitespacesAndNewlines) == "hiddenSince" else { continue }
                value = pieces[1]
            } else {
                guard index == 2 else { continue }
                value = argument
            }
            if let parsed = parseMetadataVersion(value), parsed <= kotlinApiVersion {
                return true
            }
        }
    }
    guard let annotation = annotations.first(where: {
        KnownCompilerAnnotation.deprecated.matches($0.annotationFQName)
    }) else {
        return false
    }
    for (index, argument) in annotation.arguments.enumerated() {
        let pieces = argument.split(separator: "=", maxSplits: 1).map(String.init)
        let value: String
        if pieces.count == 2 {
            guard pieces[0].trimmingCharacters(in: .whitespacesAndNewlines) == "level" else { continue }
            value = pieces[1]
        } else {
            guard index == 2 else { continue }
            value = argument
        }
        let level = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".").last.map(String.init)
        if level == "HIDDEN" { return true }
    }
    return false
}

private func parseMetadataVersionArgument(
    _ arguments: [String],
    parameterName: String
) -> KotlinCompilerVersion? {
    var positionalIndex = 0
    for argument in arguments {
        let pieces = argument.split(separator: "=", maxSplits: 1).map(String.init)
        if pieces.count == 2 {
            guard pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == parameterName.lowercased() else {
                continue
            }
            return parseMetadataVersion(pieces[1])
        }
        if positionalIndex == 0 {
            return parseMetadataVersion(argument)
        }
        positionalIndex += 1
    }
    return nil
}

private func parseMetadataVersion(_ rawValue: String) -> KotlinCompilerVersion? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let version: String
    if trimmed.count >= 2,
       let first = trimmed.first,
       let last = trimmed.last,
       (first == "\"" || first == "'"), first == last
    {
        version = String(trimmed.dropFirst().dropLast())
    } else {
        version = trimmed
    }
    return KotlinCompilerVersion(rawValue: version)
}
