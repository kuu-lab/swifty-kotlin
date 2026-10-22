/// KUU-2813: reachability-limited body analysis for top-level functions.
///
/// Reachability has to be known *before* type checking, when call targets are
/// not resolved yet. This analysis is therefore purely lexical and
/// over-approximating: a function counts as referenced when its simple name
/// occurs as an identifier token anywhere in a reachable declaration's source
/// text (comments and string literals included). Every overload, extension and
/// generic instantiation sharing that name stays reachable, so overload
/// resolution can never pick a declaration whose body was skipped.
///
/// Roots are everything the compiler or a runtime may enter without a textual
/// call: `main`, every non-function top-level declaration (classes, objects,
/// properties and type aliases carry initializers, members and implicit
/// conventions), `operator` functions (convention calls), annotated functions
/// (`@JvmStatic`, `@JsExport`, ... and reflection hooks), `external` / `expect`
/// / `actual` functions, and the last segment of every import (aliases).
///
/// Only top-level functions in user files are ever skipped; bundled stdlib
/// files and script files are never touched.
enum TopLevelFunctionReachability {
    static func unreachableFunctionDecls(
        ast: ASTModule,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> Set<DeclID> {
        let userFiles = ast.sortedFiles.filter {
            sourceManager.origin(of: $0.fileID)?.isBundledStdlib != true
        }
        if userFiles.contains(where: { !$0.scriptBody.isEmpty }) { return [] }

        struct Candidate {
            let declID: DeclID
            let range: SourceRange
        }
        var candidatesByName: [String: [Candidate]] = [:]
        var worklist: [String] = []
        var seenNames: Set<String> = []
        var hasMain = false

        func enqueue(text: Substring) {
            forEachIdentifier(in: text) { name in
                if seenNames.insert(name).inserted { worklist.append(name) }
            }
        }

        for file in userFiles {
            for importDecl in file.imports {
                if let last = importDecl.path.last {
                    let name = interner.resolve(last)
                    if seenNames.insert(name).inserted { worklist.append(name) }
                }
            }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID) else { continue }
                guard case let .funDecl(function) = decl else {
                    enqueue(text: sourceManager.slice(declRange(of: decl)))
                    continue
                }
                let name = interner.resolve(function.name)
                let isRoot = name == "main"
                    || function.isScriptEntryPoint
                    || !function.annotations.isEmpty
                    || !function.modifiers.isDisjoint(with: [.operator, .external, .expect, .actual])
                if name == "main" { hasMain = true }
                if isRoot {
                    enqueue(text: sourceManager.slice(function.range))
                } else {
                    candidatesByName[name, default: []].append(Candidate(declID: declID, range: function.range))
                }
            }
        }
        // Without an entry point (library-like input) nothing is provably dead.
        guard hasMain else { return [] }

        while let name = worklist.popLast() {
            guard let candidates = candidatesByName.removeValue(forKey: name) else { continue }
            for candidate in candidates {
                enqueue(text: sourceManager.slice(candidate.range))
            }
        }
        // Whatever is left in `candidatesByName` was never referenced.
        return Set(candidatesByName.values.flatMap { $0.map(\.declID) })
    }

    /// Calls `body` for each maximal identifier-like run (letters, digits, `_`
    /// and any non-ASCII byte). Backticks and every other character separate
    /// runs, which only over-approximates the referenced name set.
    private static func forEachIdentifier(in text: Substring, _ body: (String) -> Void) {
        var current: [UInt8] = []
        func flush() {
            if !current.isEmpty {
                body(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            }
        }
        for byte in text.utf8 {
            let isIdentifierByte = (byte >= 0x30 && byte <= 0x39)
                || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x5F
                || byte >= 0x80
            if isIdentifierByte { current.append(byte) } else { flush() }
        }
        flush()
    }

    private static func declRange(of decl: Decl) -> SourceRange {
        switch decl {
        case let .classDecl(decl): decl.range
        case let .interfaceDecl(decl): decl.range
        case let .funDecl(decl): decl.range
        case let .propertyDecl(decl): decl.range
        case let .typeAliasDecl(decl): decl.range
        case let .objectDecl(decl): decl.range
        case let .enumEntryDecl(decl): decl.range
        }
    }
}
