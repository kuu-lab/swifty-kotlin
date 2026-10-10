import Foundation

public enum AnnotationRetentionKind: String {
    case source = "SOURCE"
    case binary = "BINARY"
    case runtime = "RUNTIME"
}

/// Header collection resolves names and retention-entry aliases in the producer,
/// so imported declarations can be classified without the producer's AST.
func resolvedAnnotationRetention(
    _ annotation: MetadataAnnotationRecord,
    symbols: SymbolTable,
    interner: StringInterner
) -> AnnotationRetentionKind {
    if let retention = annotation.retention { return retention }
    guard let annotationSymbol = symbols.lookup(
        fqName: annotation.annotationFQName.split(separator: ".").map { interner.intern(String($0)) }
    ), let retention = symbols.annotations(for: annotationSymbol).first(where: {
        $0.annotationFQName == "kotlin.annotation.Retention"
    }), let argument = retention.arguments.first else {
        return .runtime
    }
    switch retentionArgumentValue(argument).split(separator: ".").last {
    case "SOURCE": return .source
    case "BINARY": return .binary
    default: return .runtime
    }
}

/// Retention is an enum constant, which Kotlin permits inside parentheses.
/// Strip only parentheses enclosing the entire value, rather than arbitrary
/// leading/trailing punctuation on a different expression.
private func retentionArgumentValue(_ argument: String) -> String {
    var value = (argument.split(separator: "=", maxSplits: 1).last.map(String.init) ?? argument)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    while value.first == "(", value.last == ")" {
        var depth = 0
        var wrapsWholeValue = true
        for character in value.dropLast() {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if depth <= 0 { wrapsWholeValue = false; break }
        }
        guard wrapsWholeValue, depth == 1 else { break }
        value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return value
}

func canonicalRetentionArguments(
    _ arguments: [String], file: ASTFile?, interner: StringInterner
) -> [String] {
    arguments.map { argument in
        let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let value = retentionArgumentValue(argument)
        // An entry import only changes a bare identifier. A qualified enum
        // entry keeps its meaning even if an import alias shadows its last part.
        guard !value.contains("."), let imported = file?.imports.first(where: {
            ($0.alias.map(interner.resolve) ?? $0.path.last.map(interner.resolve)) == value
                && $0.path.dropLast().map(interner.resolve) == ["kotlin", "annotation", "AnnotationRetention"]
        }), let importedEntry = imported.path.last else { return argument }
        let entry = interner.resolve(importedEntry)
        guard entry != value, ["SOURCE", "BINARY", "RUNTIME"].contains(entry) else { return argument }
        let canonical = "kotlin.annotation.AnnotationRetention." + entry
        return parts.count == 2 ? String(parts[0]) + "=" + canonical : canonical
    }
}

extension DataFlowSemaPhase {
    /// Run after every header exists, including forward declarations and aliases.
    func canonicalizeDeclarationAnnotations(
        ast: ASTModule, bindings: BindingTable, symbols: SymbolTable, types: TypeSystem, interner: StringInterner
    ) {
        var declarations: [SymbolID: DeclID] = [:]
        for (declID, symbolID) in bindings.declSymbols { declarations[symbolID] = declID }
        for symbol in symbols.allSymbols() {
            guard let fileID = symbols.sourceFileID(for: symbol.id) ?? symbol.declSite?.start.file,
                  let file = ast.file(for: fileID) else { continue }
            let annotations = symbols.annotations(for: symbol.id)
            guard !annotations.isEmpty else { continue }
            let sourceAnnotations = declarations[symbol.id].flatMap { ast.arena.decl($0) }
                .map { metadataAnnotations(for: $0) } ?? []
            let canonical = annotations.enumerated().map { index, annotation in
                // Re-resolve the original AST spelling after all headers exist.
                // An early name match must not override a later nested declaration.
                let rawName = index < sourceAnnotations.count ? sourceAnnotations[index].name : annotation.annotationFQName
                let resolved = resolveAnnotationSymbol(
                    named: rawName, in: file, symbols: symbols,
                    interner: interner, types: types, enclosingFQName: Array(symbol.fqName.dropLast())
                )
                let name = resolved.flatMap { symbols.symbol($0)?.fqName.map(interner.resolve).joined(separator: ".") }
                    ?? annotation.annotationFQName
                return MetadataAnnotationRecord(
                    annotationFQName: name,
                    arguments: name == "kotlin.annotation.Retention"
                        ? canonicalRetentionArguments(
                            index < sourceAnnotations.count ? sourceAnnotations[index].arguments : annotation.arguments,
                            file: file, interner: interner
                        )
                        : annotation.arguments,
                    useSiteTarget: annotation.useSiteTarget, retention: annotation.retention
                )
            }
            symbols.setAnnotations(canonical, for: symbol.id)
        }
    }
}
