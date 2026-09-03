import Foundation

public struct ASTArenaSnapshot: Codable {
    public let declarations: [Decl]
    public let expressions: [Expr]
    public let typeRefs: [TypeRef]
    public let loopLabels: [ExprID: InternedString]
    public let whenSubjectVarNames: [ExprID: InternedString]
    public let lambdaParamTypeRefs: [ExprID: [TypeRefID?]]
    public let explicitCallExpressions: Set<ExprID>

    public init(
        declarations: [Decl],
        expressions: [Expr],
        typeRefs: [TypeRef],
        loopLabels: [ExprID: InternedString],
        whenSubjectVarNames: [ExprID: InternedString],
        lambdaParamTypeRefs: [ExprID: [TypeRefID?]] = [:],
        explicitCallExpressions: Set<ExprID> = []
    ) {
        self.declarations = declarations
        self.expressions = expressions
        self.typeRefs = typeRefs
        self.loopLabels = loopLabels
        self.whenSubjectVarNames = whenSubjectVarNames
        self.lambdaParamTypeRefs = lambdaParamTypeRefs
        self.explicitCallExpressions = explicitCallExpressions
    }
}

/// Provides a read-only, file-local index of expression source ranges.
fileprivate struct ASTExpressionRangeIndex: Sendable {
    fileprivate struct Entry: Sendable {
        let startOffset: Int
        let endOffset: Int
        let exprID: ExprID
    }

    private let entriesByFile: [FileID: [Entry]]

    fileprivate init(entriesByFile: [FileID: [Entry]]) {
        self.entriesByFile = entriesByFile
    }

    /// Returns the narrowest expression containing `offset` in `fileID`.
    ///
    /// The upper bound is found by binary-searching the position-sorted
    /// entries. The remaining scan is limited to the requested file and
    /// compares expression IDs explicitly so equal-width ties retain the
    /// arena insertion-order behavior of the linear resolver.
    fileprivate func innermostExpr(at offset: Int, in fileID: FileID) -> ExprID? {
        guard let entries = entriesByFile[fileID], !entries.isEmpty else {
            return nil
        }

        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) >> 1
            if entries[middle].startOffset <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }

        var best: ExprID?
        var bestWidth = Int.max
        for entry in entries[..<low].reversed() {
            guard offset <= entry.endOffset else { continue }
            let width = entry.endOffset - entry.startOffset
            guard width <= bestWidth else { continue }
            if width < bestWidth || best == nil || entry.exprID.rawValue < best!.rawValue {
                bestWidth = width
                best = entry.exprID
            }
        }
        return best
    }
}

public final class ASTArena: @unchecked Sendable {
    private let lock = NSLock()
    private var _decls: [Decl] = []
    private var _exprs: [Expr] = []
    private var _typeRefs: [TypeRef] = []
    private var _expressionRangeIndex: ASTExpressionRangeIndex?
    /// Maps loop expression IDs (forExpr/whileExpr/doWhileExpr) to their user-defined label.
    private var _loopLabels: [ExprID: InternedString] = [:]
    /// Maps whenExpr IDs to their subject variable name for `when (val x = expr)` syntax.
    private var _whenSubjectVarNames: [ExprID: InternedString] = [:]
    /// Maps lambdaLiteral expression IDs to their explicit parameter type
    /// annotations (`{ a: Int, b: Int -> ... }`); nil entries are unannotated.
    private var _lambdaParamTypeRefs: [ExprID: [TypeRefID?]] = [:]
    /// Tracks member-call expressions written with parentheses so zero-argument
    /// function calls remain distinct from bare property access in the AST.
    private var _explicitCallExpressions: Set<ExprID> = []

    public var decls: [Decl] {
        lock.lock()
        defer { lock.unlock() }
        return _decls
    }

    public var exprs: [Expr] {
        lock.lock()
        defer { lock.unlock() }
        return _exprs
    }

    public init() {}

    public init(snapshot: ASTArenaSnapshot) {
        _decls = snapshot.declarations
        _exprs = snapshot.expressions
        _typeRefs = snapshot.typeRefs
        _loopLabels = snapshot.loopLabels
        _whenSubjectVarNames = snapshot.whenSubjectVarNames
        _lambdaParamTypeRefs = snapshot.lambdaParamTypeRefs
        _explicitCallExpressions = snapshot.explicitCallExpressions
    }

    public func snapshot() -> ASTArenaSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ASTArenaSnapshot(
            declarations: _decls,
            expressions: _exprs,
            typeRefs: _typeRefs,
            loopLabels: _loopLabels,
            whenSubjectVarNames: _whenSubjectVarNames,
            lambdaParamTypeRefs: _lambdaParamTypeRefs,
            explicitCallExpressions: _explicitCallExpressions
        )
    }

    public func appendDecl(_ decl: Decl) -> DeclID {
        lock.lock()
        defer { lock.unlock() }
        let id = Int32(_decls.count)
        _decls.append(decl)
        return DeclID(rawValue: id)
    }

    public func decl(_ id: DeclID) -> Decl? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard _decls.indices.contains(index) else { return nil }
        return _decls[index]
    }

    public func declarations() -> [Decl] {
        lock.lock()
        defer { lock.unlock() }
        return _decls
    }

    /// The number of declarations in the arena (thread-safe).
    public var declCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _decls.count
    }

    public func appendExpr(_ expr: Expr) -> ExprID {
        lock.lock()
        defer { lock.unlock() }
        let id = ExprID(rawValue: Int32(_exprs.count))
        _exprs.append(expr)
        _expressionRangeIndex = nil
        return id
    }

    public func expr(_ id: ExprID) -> Expr? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard _exprs.indices.contains(index) else { return nil }
        return _exprs[index]
    }

    public func exprRange(_ id: ExprID) -> SourceRange? {
        guard let expr = expr(id) else {
            return nil
        }
        return Self.expressionRange(of: expr)
    }

    /// Resolves a position through the cached range index while holding the
    /// same lock that protects expression storage and index invalidation.
    public func indexedInnermostExpr(at offset: Int, in fileID: FileID) -> ExprID? {
        lock.lock()
        defer { lock.unlock() }
        return expressionRangeIndexLocked().innermostExpr(at: offset, in: fileID)
    }

    fileprivate func prepareExpressionRangeIndex() {
        lock.lock()
        defer { lock.unlock() }
        _ = expressionRangeIndexLocked()
    }

    private func expressionRangeIndexLocked() -> ASTExpressionRangeIndex {
        if let _expressionRangeIndex {
            return _expressionRangeIndex
        }
        var entriesByFile: [FileID: [ASTExpressionRangeIndex.Entry]] = [:]
        for (index, expr) in _exprs.enumerated() {
            guard let range = Self.expressionRange(of: expr) else { continue }
            entriesByFile[range.start.file, default: []].append(
                ASTExpressionRangeIndex.Entry(
                    startOffset: range.start.offset,
                    endOffset: range.end.offset,
                    exprID: ExprID(rawValue: Int32(index))
                )
            )
        }

        for fileID in entriesByFile.keys {
            entriesByFile[fileID]?.sort {
                if $0.startOffset != $1.startOffset {
                    return $0.startOffset < $1.startOffset
                }
                if $0.endOffset != $1.endOffset {
                    return $0.endOffset < $1.endOffset
                }
                return $0.exprID.rawValue < $1.exprID.rawValue
            }
        }

        let index = ASTExpressionRangeIndex(entriesByFile: entriesByFile)
        _expressionRangeIndex = index
        return index
    }

    private static func expressionRange(of expr: Expr) -> SourceRange? {
        switch expr {
        case let .intLiteral(_, range),
             let .longLiteral(_, range),
             let .uintLiteral(_, range),
             let .ulongLiteral(_, range),
             let .floatLiteral(_, range),
             let .doubleLiteral(_, range),
             let .charLiteral(_, range),
             let .boolLiteral(_, range),
             let .stringLiteral(_, range),
             let .nameRef(_, range),
             let .forExpr(_, _, _, _, range),
             let .whileExpr(_, _, _, range),
             let .doWhileExpr(_, _, _, range),
             let .breakExpr(_, range),
             let .continueExpr(_, range),
             let .localDecl(_, _, _, _, _, range),
             let .localAssign(_, _, range),
             let .memberAssign(_, _, _, range),
             let .indexedAssign(_, _, _, range),
             let .call(_, _, _, range),
             let .memberCall(_, _, _, _, range),
             let .indexedAccess(_, _, range),
             let .indexedCompoundAssign(_, _, _, _, range),
             let .memberCompoundAssign(_, _, _, _, range),
             let .binary(_, _, _, range),
             let .whenExpr(_, _, _, range),
             let .returnExpr(_, _, range),
             let .ifExpr(_, _, _, range),
             let .tryExpr(_, _, _, range),
             let .unaryExpr(_, _, range),
             let .isCheck(_, _, _, range),
             let .asCast(_, _, _, range),
             let .nullAssert(_, range),
             let .safeMemberCall(_, _, _, _, range),
             let .compoundAssign(_, _, _, range),
             let .stringTemplate(_, range),
             let .throwExpr(_, range),
             let .lambdaLiteral(_, _, _, range),
             let .objectLiteral(_, _, range),
             let .callableRef(_, _, range),
             let .localFunDecl(_, _, _, _, _, range),
             let .blockExpr(_, _, range),
             let .superRef(_, range),
             let .thisRef(_, range),
             let .inExpr(_, _, range),
             let .notInExpr(_, _, range),
             let .destructuringDecl(_, _, _, range),
             let .forDestructuringExpr(_, _, _, range):
            return range
        }
    }

    public func setLoopLabel(_ label: InternedString, for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _loopLabels[exprID] = label
    }

    public func loopLabel(for exprID: ExprID) -> InternedString? {
        lock.lock()
        defer { lock.unlock() }
        return _loopLabels[exprID]
    }

    public func setWhenSubjectVarName(_ name: InternedString, for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _whenSubjectVarNames[exprID] = name
    }

    public func whenSubjectVarName(for exprID: ExprID) -> InternedString? {
        lock.lock()
        defer { lock.unlock() }
        return _whenSubjectVarNames[exprID]
    }

    public func setLambdaParamTypeRefs(_ typeRefs: [TypeRefID?], for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _lambdaParamTypeRefs[exprID] = typeRefs
    }

    public func lambdaParamTypeRefs(for exprID: ExprID) -> [TypeRefID?]? {
        lock.lock()
        defer { lock.unlock() }
        return _lambdaParamTypeRefs[exprID]
    }

    public func markExplicitCall(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _explicitCallExpressions.insert(exprID)
    }

    public func isExplicitCall(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _explicitCallExpressions.contains(exprID)
    }

    public func appendTypeRef(_ typeRef: TypeRef) -> TypeRefID {
        lock.lock()
        defer { lock.unlock() }
        let id = TypeRefID(rawValue: Int32(_typeRefs.count))
        _typeRefs.append(typeRef)
        return id
    }

    public func typeRef(_ id: TypeRefID) -> TypeRef? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard _typeRefs.indices.contains(index) else { return nil }
        return _typeRefs[index]
    }
}

public final class ASTModule {
    public let files: [ASTFile]
    public let arena: ASTArena
    public let declarationCount: Int
    public let tokenCount: Int
    public let activeDeclsByFileRawID: [Int32: [DeclID]]

    /// Files pre-sorted by fileID for stable iteration order.
    /// All callers that previously used `sortedFiles` now use this directly.
    public let sortedFiles: [ASTFile]

    public init(
        files: [ASTFile],
        arena: ASTArena,
        declarationCount: Int,
        tokenCount: Int,
        activeDeclsByFileRawID: [Int32: [DeclID]] = [:]
    ) {
        self.files = files
        self.arena = arena
        self.declarationCount = declarationCount
        self.tokenCount = tokenCount
        self.activeDeclsByFileRawID = activeDeclsByFileRawID
        sortedFiles = files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue })

        // ASTModule is finalized after all expressions have been appended, so
        // build the index before the first position-based query pays for it.
        arena.prepareExpressionRangeIndex()
    }

    public var activeDeclarationIDs: Set<DeclID> {
        let activeDecls = activeDeclsByFileRawID.values.flatMap { $0 }
        if !activeDecls.isEmpty {
            return Set(activeDecls)
        }
        return Set((0 ..< arena.declCount).map { DeclID(rawValue: Int32($0)) })
    }

    public convenience init(declarationCount: Int, tokenCount: Int) {
        self.init(files: [], arena: ASTArena(), declarationCount: declarationCount, tokenCount: tokenCount)
    }
}
