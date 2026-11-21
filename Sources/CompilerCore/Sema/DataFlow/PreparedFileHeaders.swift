struct UnresolvedHeader: @unchecked Sendable {
    let declarationID: DeclID
    let declaration: Decl
}

struct PreparedFileHeaders: Sendable {
    let aliases: [UnresolvedHeader]
    let remaining: [UnresolvedHeader]

    init(file: ASTFile, arena: ASTArena) {
        var aliases: [UnresolvedHeader] = []
        var remaining: [UnresolvedHeader] = []
        for declarationID in file.topLevelDecls {
            guard let declaration = arena.decl(declarationID) else { continue }
            let header = UnresolvedHeader(declarationID: declarationID, declaration: declaration)
            if case .typeAliasDecl = declaration {
                aliases.append(header)
            } else {
                remaining.append(header)
            }
        }
        self.aliases = aliases
        self.remaining = remaining
    }
}

private final class HeaderPreparationWork: @unchecked Sendable {
    let files: [ASTFile]
    let arena: ASTArena

    init(files: [ASTFile], arena: ASTArena) {
        self.files = files
        self.arena = arena
    }

    func prepare(_ index: Int) -> PreparedFileHeaders {
        PreparedFileHeaders(file: files[index], arena: arena)
    }
}

extension DataFlowSemaPhase {
    func prepareFileHeaders(files: [ASTFile], arena: ASTArena, jobs: Int) -> [PreparedFileHeaders] {
        guard jobs > 1, files.count > 1 else {
            return files.map { PreparedFileHeaders(file: $0, arena: arena) }
        }
        let work = HeaderPreparationWork(files: files, arena: arena)
        // The task cannot throw. LargeStackExecutor propagates only task errors.
        return try! SemaPerFileExecutor.collect(count: files.count, jobs: jobs) { index in
            work.prepare(index)
        }
    }
}
