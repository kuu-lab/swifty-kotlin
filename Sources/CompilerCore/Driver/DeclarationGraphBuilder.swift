import Foundation

/// Builds a `DeclarationDependencyGraph` from parsed sources.
///
/// Hashes are taken from the *source text* of each top-level declaration, never
/// from arena indices or `SymbolID`s, so they are identical across runs and
/// across unrelated edits elsewhere in the project. Everything here errs on
/// the side of over-invalidation:
///
/// * a unit's text starts where the previous declaration ended, so leading
///   modifiers, annotations, comments and (for the first unit) the package and
///   import header are part of its signature hash;
/// * only top-level `fun` declarations get separate signature/body hashes.
///   Classes, interfaces, objects, properties and aliases hash their whole text
///   as both;
/// * a function's body counts as part of its signature when callers can observe
///   it: `inline`, expression bodies without a declared return type (inferred
///   type), and the synthesized script entry point;
/// * references are every declared simple name that appears as an identifier in
///   the unit's text, plus every declaration with an operator-convention name
///   (call sites like `a + b` never spell `plus`).
public enum DeclarationGraphBuilder {
    /// Names the language resolves implicitly from syntax (operators,
    /// destructuring, delegation, iteration, indexing, invocation).
    static let conventionNames: Set<String> = [
        "plus", "minus", "times", "div", "rem", "mod", "rangeTo", "rangeUntil",
        "unaryPlus", "unaryMinus", "not", "inc", "dec", "contains", "get", "set",
        "invoke", "iterator", "next", "hasNext", "compareTo", "equals",
        "plusAssign", "minusAssign", "timesAssign", "divAssign", "remAssign",
        "getValue", "setValue", "provideDelegate", "toString", "hashCode",
    ]

    public static func build(ast: ASTModule, sourceManager: SourceManager, interner: StringInterner) -> DeclarationDependencyGraph {
        struct Draft {
            let id: String
            let name: String
            let signatureHash: String
            let bodyHash: String
            let identifiers: Set<String>
        }
        var drafts: [Draft] = []

        for file in ast.files {
            if sourceManager.origin(of: file.fileID)?.isBundledStdlib == true { continue }
            let path = sourceManager.path(of: file.fileID)
            let contents = sourceManager.contents(of: file.fileID)
            let package = file.packageFQName.map(interner.resolve).joined(separator: ".")

            struct Entry {
                let name: String
                let range: SourceRange
                let fun: FunDecl?
            }
            var entries: [Entry] = []
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID) else { continue }
                switch decl {
                case let .funDecl(d): entries.append(Entry(name: interner.resolve(d.name), range: d.range, fun: d))
                case let .classDecl(d): entries.append(Entry(name: interner.resolve(d.name), range: d.range, fun: nil))
                case let .interfaceDecl(d): entries.append(Entry(name: interner.resolve(d.name), range: d.range, fun: nil))
                case let .objectDecl(d): entries.append(Entry(name: interner.resolve(d.name), range: d.range, fun: nil))
                case let .propertyDecl(d): entries.append(Entry(name: interner.resolve(d.name), range: d.range, fun: nil))
                case let .typeAliasDecl(d): entries.append(Entry(name: interner.resolve(d.name), range: d.range, fun: nil))
                case let .enumEntryDecl(d): entries.append(Entry(name: interner.resolve(d.name), range: d.range, fun: nil))
                }
            }
            entries.sort { $0.range.start.offset < $1.range.start.offset }

            func text(_ lower: Int, _ upper: Int) -> Data {
                let lo = max(0, min(lower, contents.count))
                let hi = max(lo, min(upper, contents.count))
                return contents.subdata(in: lo ..< hi)
            }

            var previousEnd = 0
            var ordinals: [String: Int] = [:]
            for entry in entries {
                let start = entry.range.start.offset
                let end = entry.range.end.offset
                // Overlapping/nested ranges (should not happen at top level)
                // fall back to hashing from the declaration's own start.
                let gapStart = previousEnd <= start ? previousEnd : start
                previousEnd = max(previousEnd, end)

                let qualified = package.isEmpty ? entry.name : "\(package).\(entry.name)"
                let ordinal = ordinals[qualified, default: 0]
                ordinals[qualified] = ordinal + 1
                let id = "\(path)::\(qualified)#\(ordinal)"

                let whole = text(gapStart, end)
                var signature = whole
                var body = whole
                if let fun = entry.fun, !fun.isScriptEntryPoint {
                    var bodyRange: SourceRange?
                    switch fun.body {
                    case let .block(_, range), let .expr(_, range): bodyRange = range
                    case .unit: bodyRange = nil
                    }
                    if let bodyRange, bodyRange.start.offset >= gapStart, bodyRange.end.offset <= end {
                        signature = text(gapStart, bodyRange.start.offset)
                        body = text(bodyRange.start.offset, bodyRange.end.offset)
                        // Trailing text after the body (rare) belongs to the signature.
                        if bodyRange.end.offset < end {
                            signature.append(text(bodyRange.end.offset, end))
                        }
                        let inferred = fun.returnType == nil && fun.body.isExpressionBody
                        if fun.isInline || inferred {
                            signature.append(body)
                        }
                    }
                }
                drafts.append(Draft(
                    id: id,
                    name: entry.name,
                    signatureHash: FileFingerprint.sha256Hex(signature),
                    bodyHash: FileFingerprint.sha256Hex(body),
                    identifiers: identifiers(in: whole)
                ))
            }

            // Top-level script statements have no declaration boundary: one
            // unit hashes the whole file.
            if !file.scriptBody.isEmpty {
                let hash = FileFingerprint.sha256Hex(contents)
                drafts.append(Draft(
                    id: "\(path)::<script>", name: "<script>",
                    signatureHash: hash, bodyHash: hash, identifiers: identifiers(in: contents)
                ))
            }
        }

        var idsByName: [String: [String]] = [:]
        for draft in drafts { idsByName[draft.name, default: []].append(draft.id) }
        let conventionIDs = Set(conventionNames.flatMap { idsByName[$0] ?? [] })

        let units = drafts.map { draft -> DeclarationUnit in
            var references = conventionIDs
            for identifier in draft.identifiers {
                references.formUnion(idsByName[identifier] ?? [])
            }
            references.remove(draft.id)
            return DeclarationUnit(
                id: draft.id,
                signatureHash: draft.signatureHash,
                bodyHash: draft.bodyHash,
                references: references
            )
        }
        return DeclarationDependencyGraph(units: units)
    }

    /// Identifier-shaped tokens plus whole backtick-quoted names.
    static func identifiers(in data: Data) -> Set<String> {
        var result = Set<String>()
        var index = data.startIndex
        let end = data.endIndex
        func isStart(_ b: UInt8) -> Bool { (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b >= 0x80 }
        func isPart(_ b: UInt8) -> Bool { isStart(b) || (b >= 0x30 && b <= 0x39) }
        while index < end {
            let byte = data[index]
            if byte == 0x60 { // backtick
                var close = index + 1
                while close < end, data[close] != 0x60, data[close] != 0x0A { close += 1 }
                if close < end, data[close] == 0x60 {
                    result.insert(String(decoding: data[(index + 1) ..< close], as: UTF8.self))
                    index = close + 1
                    continue
                }
                index += 1
            } else if isStart(byte) {
                var close = index + 1
                while close < end, isPart(data[close]) { close += 1 }
                result.insert(String(decoding: data[index ..< close], as: UTF8.self))
                index = close
            } else {
                index += 1
            }
        }
        return result
    }
}
