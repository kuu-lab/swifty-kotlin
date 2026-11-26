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
        guard hasMain else { return [] }

        while let name = worklist.popLast() {
            guard let candidates = candidatesByName.removeValue(forKey: name) else { continue }
            for candidate in candidates {
                enqueue(text: sourceManager.slice(candidate.range))
            }
        }
        return Set(candidatesByName.values.flatMap { $0.map(\.declID) })
    }

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
