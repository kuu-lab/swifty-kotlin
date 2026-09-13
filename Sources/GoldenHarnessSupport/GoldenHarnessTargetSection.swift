@testable import CompilerCore
import Foundation

/// Resolves a case spec's `target=` directives against the Sema symbol table
/// and renders the dedicated `section stdlib-targets` block (RF-GOLDEN-011).
///
/// Unlike the ordinary `symbol`/`expr` body — which only covers what the
/// fixture itself declares and references — this section deliberately dumps
/// the *library-owned* declarations a case claims responsibility for: full
/// signatures, declared variance, supertypes, typealias underlying types,
/// annotations, and origin classification. Selection is explicit: a `target`
/// that matches zero or several symbols fails the case instead of silently
/// losing coverage, and the render never expands transitively, so the
/// section's size is bounded by the spec rather than by how much of the
/// bundled surface the fixture happens to touch.
enum GoldenHarnessTargetSection {
    static let sectionHeader = "section stdlib-targets"

    /// Origins a `target=` is allowed to pin. Fixture-owned and unresolved
    /// symbols are rejected: a case must not claim responsibility for its own
    /// declarations (that is what ordinary `symbol`/`decl` output is for) nor
    /// for symbols whose origin the classifier could not establish.
    private static let allowedOrigins: Set<GoldenSymbolOrigin> = [
        .bundledSource,
        .stdlibStub,
        .sourceBackedAlias,
        .importedLibrary,
    ]

    static func render(
        targets: [String],
        ctx: StableRenderContext,
        sema: SemaModule,
        sourceManager: SourceManager,
        interner: StringInterner
    ) throws -> [String] {
        let classifier = GoldenSymbolOriginClassifier(
            sema: sema,
            sourceManager: sourceManager,
            interner: interner
        )

        // Index every symbol by its meaning-derived stable key and by the
        // key's FQName component, so both full-key and bare-FQName targets
        // resolve against the same namespace `call=`/`ref=` lines print.
        // Keys always start their bracketed descriptor with `kind=`, so
        // splitting on "[kind=" keeps bracketed-identifier edge cases in the
        // FQName component intact.
        var symbolsByKey: [String: [SemanticSymbol]] = [:]
        var keysByFQName: [String: [String]] = [:]
        for symbol in sema.symbols.allSymbols() {
            let key = ctx.stableKey(for: symbol.id)
            guard key != "_" else { continue }
            symbolsByKey[key, default: []].append(symbol)
            if let bracket = key.range(of: "[kind=") {
                keysByFQName[String(key[key.startIndex ..< bracket.lowerBound]), default: []].append(key)
            }
        }

        var rendered: [(key: String, line: String)] = []
        for target in targets {
            let symbol = try resolve(target, symbolsByKey: symbolsByKey, keysByFQName: keysByFQName)
            let origin = classifier.origin(of: symbol.id)
            let key = ctx.stableKey(for: symbol.id)
            guard allowedOrigins.contains(origin) else {
                throw GoldenHarnessTargetError.nonLibraryTarget(
                    target: target,
                    key: key,
                    origin: origin
                )
            }
            rendered.append((key, renderTarget(symbol, key: key, origin: origin, ctx: ctx, sema: sema, interner: interner)))
        }

        return rendered
            .sorted { $0.key.compare($1.key, options: .numeric) == .orderedAscending }
            .map(\.line)
    }

    // MARK: - Resolution

    /// `target` is either a complete meaning key (`fq[kind=…;…]`, the exact
    /// string a `call=`/`ref=`/`symbol fq=` field prints) or a bare FQName
    /// (`kotlin.Any`). The bare form must resolve to exactly one symbol —
    /// overloaded FQNames require the full key.
    private static func resolve(
        _ target: String,
        symbolsByKey: [String: [SemanticSymbol]],
        keysByFQName: [String: [String]]
    ) throws -> SemanticSymbol {
        let matchKeys: [String]
        if target.contains("[") {
            matchKeys = symbolsByKey.keys.contains(target) ? [target] : []
        } else {
            matchKeys = keysByFQName[target] ?? []
        }
        let matches = matchKeys.flatMap { symbolsByKey[$0] ?? [] }
        guard !matches.isEmpty else {
            throw GoldenHarnessTargetError.unresolvedTarget(
                target: target,
                candidates: candidateKeys(for: target, keysByFQName: keysByFQName)
            )
        }
        guard matches.count == 1, let symbol = matches.first else {
            throw GoldenHarnessTargetError.ambiguousTarget(
                target: target,
                matches: matchKeys.sorted()
            )
        }
        return symbol
    }

    /// Best-effort near-miss list for the error message so a misspelled or
    /// under-specified target points the author at real keys.
    private static func candidateKeys(
        for target: String,
        keysByFQName: [String: [String]]
    ) -> [String] {
        let fqPart = target.split(separator: "[", maxSplits: 1).first.map(String.init) ?? target
        var candidates = keysByFQName[fqPart] ?? []
        if candidates.isEmpty {
            let prefix = fqPart + "."
            candidates = keysByFQName.keys.filter { $0.hasPrefix(prefix) }.sorted().flatMap { keysByFQName[$0] ?? [] }
        }
        if candidates.isEmpty {
            let lastComponent = fqPart.split(separator: ".").last.map(String.init) ?? fqPart
            candidates = keysByFQName.keys
                .filter { $0.split(separator: ".").last == Substring(lastComponent[...]) }
                .sorted()
                .flatMap { keysByFQName[$0] ?? [] }
        }
        return candidates.sorted()
    }

    // MARK: - Rendering

    private static func renderTarget(
        _ symbol: SemanticSymbol,
        key: String,
        origin: GoldenSymbolOrigin,
        ctx: StableRenderContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> String {
        var parts = [
            "target fq=\(key)",
            "origin=\(origin.rawValue)",
            "kind=\(symbol.kind)",
            "vis=\(symbol.visibility)",
            "flags=\(GoldenHarnessSemaFormat.renderSymbolFlags(symbol.flags))",
        ]

        if let signature = sema.symbols.functionSignature(for: symbol.id) {
            parts.append("sig=\(ctx.renderSignature(signature))")
            if !signature.typeParameterSymbols.isEmpty {
                // T<declarationIndex> — the same normalization the meaning
                // keys use. Imported-library type parameters are virtual IDs
                // with no registered name, so positional tokens are the only
                // profile-independent spelling.
                let names = signature.typeParameterSymbols.indices.map { "T\($0)" }
                parts.append("tparams=[\(names.joined(separator: ","))]")
            }
            if !signature.reifiedTypeParameterIndices.isEmpty {
                parts.append("reified=[\(signature.reifiedTypeParameterIndices.sorted().map(String.init).joined(separator: ","))]")
            }
            if signature.valueParameterAllowsNonLocalReturn.contains(false) {
                let marks = signature.valueParameterAllowsNonLocalReturn.map { $0 ? "1" : "0" }
                parts.append("nonlocal=[\(marks.joined(separator: ","))]")
            }
        }

        switch symbol.kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol.id)
            if !typeParams.isEmpty {
                let variances = sema.types.nominalTypeParameterVariances(for: symbol.id)
                let rendered = typeParams.indices.map { index -> String in
                    switch index < variances.count ? variances[index] : .invariant {
                    case .out: return "T\(index)(out)"
                    case .in: return "T\(index)(in)"
                    case .invariant: return "T\(index)"
                    }
                }
                parts.append("tparams=[\(rendered.joined(separator: ","))]")
                let bounds = typeParams.map { typeParam -> String in
                    let boundTypes = sema.symbols.typeParameterUpperBounds(for: typeParam)
                    return boundTypes.isEmpty ? "_" : boundTypes.map { ctx.renderType($0) }.joined(separator: "&")
                }
                if bounds.contains(where: { $0 != "_" }) {
                    parts.append("bounds=[\(bounds.joined(separator: ","))]")
                }
            }
            let supertypes = sema.symbols.directSupertypes(for: symbol.id)
            if !supertypes.isEmpty {
                let rendered = supertypes.map { supertype -> String in
                    let args = sema.types.nominalSupertypeTypeArgs(for: symbol.id, supertype: supertype)
                    let typeID = sema.types.make(.classType(ClassType(classSymbol: supertype, args: args)))
                    return ctx.renderType(typeID)
                }
                parts.append("supertypes=[\(rendered.joined(separator: ","))]")
            }
            if symbol.kind == .typeAlias {
                if let underlying = sema.symbols.typeAliasUnderlyingType(for: symbol.id) {
                    parts.append("underlying=\(ctx.renderType(underlying))")
                }
            } else if let underlying = sema.symbols.effectiveValueClassUnderlyingType(for: symbol.id) {
                parts.append("underlying=\(ctx.renderType(underlying))")
            }
        case .typeParameter:
            let bounds = sema.symbols.typeParameterUpperBounds(for: symbol.id)
            if !bounds.isEmpty {
                parts.append("bounds=[\(bounds.map { ctx.renderType($0) }.joined(separator: "&"))]")
            }
        default:
            break
        }

        if let propertyType = sema.symbols.propertyType(for: symbol.id) {
            parts.append("type=\(ctx.renderType(propertyType))")
        }

        // `@kotlin.Metadata` is the `.kklib` storage encoding blob attached to
        // every imported declaration — multi-line, embeds positional type IDs,
        // and is compiler bookkeeping rather than API surface. User-facing
        // annotations (Deprecated, KsSymbolName link names, …) stay.
        let annotations = sema.symbols.annotations(for: symbol.id)
            .filter { $0.annotationFQName != "kotlin.Metadata" }
        if !annotations.isEmpty {
            let rendered = annotations.map { annotation -> String in
                let prefix = annotation.useSiteTarget.map { "@\($0):" } ?? "@"
                let arguments = annotation.arguments.isEmpty
                    ? ""
                    : "(\(annotation.arguments.map(GoldenHarnessSemaFormat.renderAnnotationArgument).joined(separator: ",")))"
                return "\(prefix)\(annotation.annotationFQName)\(arguments)"
            }
            parts.append("annotations=[\(rendered.joined(separator: ","))]")
        }

        return parts.joined(separator: " ")
    }
}

enum GoldenHarnessTargetError: Error, CustomStringConvertible {
    case unresolvedTarget(target: String, candidates: [String])
    case ambiguousTarget(target: String, matches: [String])
    case nonLibraryTarget(target: String, key: String, origin: GoldenSymbolOrigin)

    var description: String {
        switch self {
        case let .unresolvedTarget(target, candidates):
            let hint = candidates.isEmpty
                ? "no same-name symbols exist"
                : "candidates: \(candidates.joined(separator: ", "))"
            return "target '\(target)' matched no symbol (\(hint)). Check the meaning key printed by call=/ref=/symbol fq= fields."
        case let .ambiguousTarget(target, matches):
            return "target '\(target)' matched \(matches.count) symbols: \(matches.joined(separator: ", ")). Use the full meaning key (fq[kind=…;…]) to disambiguate."
        case let .nonLibraryTarget(target, key, origin):
            return "target '\(target)' resolved to \(key) with origin '\(origin.rawValue)', which is not a stdlib/library-owned symbol. Remove it from the spec's targets or fix the fixture."
        }
    }
}
