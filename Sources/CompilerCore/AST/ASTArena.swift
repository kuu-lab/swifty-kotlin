import Foundation

public struct ASTArenaSnapshot: Codable {
    public let declarations: [Decl]
    public let expressions: [Expr]
    public let typeRefs: [TypeRef]
    public let loopLabels: [ExprID: InternedString]
    public let whenSubjectVarNames: [ExprID: InternedString]
    public let whenSubjectTypeRefs: [ExprID: TypeRefID]
    public let lambdaParamTypeRefs: [ExprID: [TypeRefID?]]
    public let callableRefReceiverTypeRefs: [ExprID: TypeRefID]
    public let infixCallExpressions: Set<ExprID>
    public let infixFunctionExpressions: Set<ExprID>
    public let operatorFunctionExpressions: Set<ExprID>
    public let explicitCallExpressions: Set<ExprID>
    public let receiverExpressionArgsCallExpressions: Set<ExprID>
    public let incrementDecrementExpressions: Set<ExprID>
    public let incrementDecrementValueExpressions: Set<ExprID>
    public let callResultCompoundAssignmentBlocks: Set<ExprID>
    public let nonFunctionLambdaLabels: Set<ExprID>
    public let incrementDecrementCachedValues: [ExprID: ExprID]
    public let expressionAnnotations: [ExprID: [AnnotationNode]]
    public let anonymousFunctionExpressions: Set<ExprID>
    public let localFunContextReceivers: [ExprID: [ContextReceiverDecl]]
    public let destructuringDeclLayouts: [ExprID: DestructuringDeclLayout]

    private enum CodingKeys: String, CodingKey {
        case declarations
        case expressions
        case typeRefs
        case loopLabels
        case whenSubjectVarNames
        case whenSubjectTypeRefs
        case lambdaParamTypeRefs
        case callableRefReceiverTypeRefs
        case infixCallExpressions
        case infixFunctionExpressions
        case operatorFunctionExpressions
        case explicitCallExpressions
        case receiverExpressionArgsCallExpressions
        case incrementDecrementExpressions
        case incrementDecrementValueExpressions
        case callResultCompoundAssignmentBlocks
        case nonFunctionLambdaLabels
        case incrementDecrementCachedValues
        case expressionAnnotations
        case anonymousFunctionExpressions
        case localFunContextReceivers
        case destructuringDeclLayouts
    }

    public init(
        declarations: [Decl],
        expressions: [Expr],
        typeRefs: [TypeRef],
        loopLabels: [ExprID: InternedString],
        whenSubjectVarNames: [ExprID: InternedString],
        whenSubjectTypeRefs: [ExprID: TypeRefID] = [:],
        lambdaParamTypeRefs: [ExprID: [TypeRefID?]] = [:],
        callableRefReceiverTypeRefs: [ExprID: TypeRefID] = [:],
        infixCallExpressions: Set<ExprID> = [],
        infixFunctionExpressions: Set<ExprID> = [],
        operatorFunctionExpressions: Set<ExprID> = [],
        explicitCallExpressions: Set<ExprID> = [],
        receiverExpressionArgsCallExpressions: Set<ExprID> = [],
        incrementDecrementExpressions: Set<ExprID> = [],
        incrementDecrementValueExpressions: Set<ExprID> = [],
        callResultCompoundAssignmentBlocks: Set<ExprID> = [],
        nonFunctionLambdaLabels: Set<ExprID> = [],
        incrementDecrementCachedValues: [ExprID: ExprID] = [:],
        expressionAnnotations: [ExprID: [AnnotationNode]] = [:],
        anonymousFunctionExpressions: Set<ExprID> = [],
        localFunContextReceivers: [ExprID: [ContextReceiverDecl]] = [:],
        destructuringDeclLayouts: [ExprID: DestructuringDeclLayout] = [:]
    ) {
        self.declarations = declarations
        self.expressions = expressions
        self.typeRefs = typeRefs
        self.loopLabels = loopLabels
        self.whenSubjectVarNames = whenSubjectVarNames
        self.whenSubjectTypeRefs = whenSubjectTypeRefs
        self.lambdaParamTypeRefs = lambdaParamTypeRefs
        self.callableRefReceiverTypeRefs = callableRefReceiverTypeRefs
        self.infixCallExpressions = infixCallExpressions
        self.infixFunctionExpressions = infixFunctionExpressions
        self.operatorFunctionExpressions = operatorFunctionExpressions
        self.explicitCallExpressions = explicitCallExpressions
        self.receiverExpressionArgsCallExpressions = receiverExpressionArgsCallExpressions
        self.incrementDecrementExpressions = incrementDecrementExpressions
        self.incrementDecrementValueExpressions = incrementDecrementValueExpressions
        self.callResultCompoundAssignmentBlocks = callResultCompoundAssignmentBlocks
        self.nonFunctionLambdaLabels = nonFunctionLambdaLabels
        self.incrementDecrementCachedValues = incrementDecrementCachedValues
        self.expressionAnnotations = expressionAnnotations
        self.anonymousFunctionExpressions = anonymousFunctionExpressions
        self.localFunContextReceivers = localFunContextReceivers
        self.destructuringDeclLayouts = destructuringDeclLayouts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        declarations = try container.decode([Decl].self, forKey: .declarations)
        expressions = try container.decode([Expr].self, forKey: .expressions)
        typeRefs = try container.decode([TypeRef].self, forKey: .typeRefs)
        loopLabels = try container.decode([ExprID: InternedString].self, forKey: .loopLabels)
        whenSubjectVarNames = try container.decode([ExprID: InternedString].self, forKey: .whenSubjectVarNames)
        whenSubjectTypeRefs = try container.decodeIfPresent(
            [ExprID: TypeRefID].self, forKey: .whenSubjectTypeRefs
        ) ?? [:]
        lambdaParamTypeRefs = try container.decode([ExprID: [TypeRefID?]].self, forKey: .lambdaParamTypeRefs)
        callableRefReceiverTypeRefs = try container.decodeIfPresent(
            [ExprID: TypeRefID].self,
            forKey: .callableRefReceiverTypeRefs
        ) ?? [:]
        infixCallExpressions = try container.decodeIfPresent(Set<ExprID>.self, forKey: .infixCallExpressions) ?? []
        infixFunctionExpressions = try container.decodeIfPresent(Set<ExprID>.self, forKey: .infixFunctionExpressions) ?? []
        operatorFunctionExpressions = try container.decodeIfPresent(Set<ExprID>.self, forKey: .operatorFunctionExpressions) ?? []
        explicitCallExpressions = try container.decode(Set<ExprID>.self, forKey: .explicitCallExpressions)
        receiverExpressionArgsCallExpressions = try container.decodeIfPresent(
            Set<ExprID>.self,
            forKey: .receiverExpressionArgsCallExpressions
        ) ?? []
        incrementDecrementExpressions = try container.decodeIfPresent(
            Set<ExprID>.self,
            forKey: .incrementDecrementExpressions
        ) ?? []
        incrementDecrementValueExpressions = try container.decodeIfPresent(
            Set<ExprID>.self,
            forKey: .incrementDecrementValueExpressions
        ) ?? []
        callResultCompoundAssignmentBlocks = try container.decodeIfPresent(
            Set<ExprID>.self, forKey: .callResultCompoundAssignmentBlocks
        ) ?? []
        nonFunctionLambdaLabels = try container.decodeIfPresent(
            Set<ExprID>.self,
            forKey: .nonFunctionLambdaLabels
        ) ?? []
        incrementDecrementCachedValues = try container.decodeIfPresent(
            [ExprID: ExprID].self,
            forKey: .incrementDecrementCachedValues
        ) ?? [:]
        expressionAnnotations = try container.decodeIfPresent(
            [ExprID: [AnnotationNode]].self, forKey: .expressionAnnotations
        ) ?? [:]
        anonymousFunctionExpressions = try container.decodeIfPresent(
            Set<ExprID>.self, forKey: .anonymousFunctionExpressions
        ) ?? []
        localFunContextReceivers = try container.decodeIfPresent(
            [ExprID: [ContextReceiverDecl]].self, forKey: .localFunContextReceivers
        ) ?? [:]
        destructuringDeclLayouts = try container.decodeIfPresent(
            [ExprID: DestructuringDeclLayout].self, forKey: .destructuringDeclLayouts
        ) ?? [:]
    }
}

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

    /// The scan is limited to the requested file and
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
    private var _loopLabels: [ExprID: InternedString] = [:]
    private var _whenSubjectVarNames: [ExprID: InternedString] = [:]
    private var _whenSubjectTypeRefs: [ExprID: TypeRefID] = [:]
    private var _lambdaParamTypeRefs: [ExprID: [TypeRefID?]] = [:]
    private var _callableRefReceiverTypeRefs: [ExprID: TypeRefID] = [:]
    /// Tracks member-call expressions written with parentheses so zero-argument
    /// function calls remain distinct from bare property access in the AST.
    private var _explicitCallExpressions: Set<ExprID> = []
    /// Preserves infix syntax independently of ordinary member calls.
    private var _infixCallExpressions: Set<ExprID> = []
    private var _infixFunctionExpressions: Set<ExprID> = []
    private var _operatorFunctionExpressions: Set<ExprID> = []
    /// Marks `receiver.(expression)(args)` calls, which require a function type
    /// with an explicit extension receiver.
    private var _receiverExpressionArgsCallExpressions: Set<ExprID> = []
    /// Tracks compound-assignment nodes synthesized from `++` / `--` so Sema and
    /// KIR can apply inc/dec semantics without changing the public AST shape.
    private var _incrementDecrementExpressions: Set<ExprID> = []
    /// Tracks prefix increment/decrement nodes whose value is the updated value.
    private var _incrementDecrementValueExpressions: Set<ExprID> = []
    /// Synthetic call-result assignment blocks preserve outer data flow while
    /// keeping their receiver temporary in a separate lexical scope.
    private var _callResultCompoundAssignmentBlocks: Set<ExprID> = []
    /// Tracks lambda literals whose leading `label@` is bound to a following
    /// postfix expression. In Kotlin a label prefixes the whole postfix-unary
    /// expression, so `foo@{ ... }()` labels the invocation rather than the
    /// lambda — `return@foo` inside then targets a label that does not denote
    /// a function and must be rejected.
    private var _nonFunctionLambdaLabels: Set<ExprID> = []
    private var _incrementDecrementCachedValues: [ExprID: ExprID] = [:]
    // Prefix annotations belong to the operand without changing its AST shape.
    private var _expressionAnnotations: [ExprID: [AnnotationNode]] = [:]
    private var _anonymousFunctionExpressions: Set<ExprID> = []
    private var _localFunContextReceivers: [ExprID: [ContextReceiverDecl]] = [:]
    private var _destructuringDeclLayouts: [ExprID: DestructuringDeclLayout] = [:]

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
        _whenSubjectTypeRefs = snapshot.whenSubjectTypeRefs
        _lambdaParamTypeRefs = snapshot.lambdaParamTypeRefs
        _callableRefReceiverTypeRefs = snapshot.callableRefReceiverTypeRefs
        _infixCallExpressions = snapshot.infixCallExpressions
        _infixFunctionExpressions = snapshot.infixFunctionExpressions
        _operatorFunctionExpressions = snapshot.operatorFunctionExpressions
        _explicitCallExpressions = snapshot.explicitCallExpressions
        _receiverExpressionArgsCallExpressions = snapshot.receiverExpressionArgsCallExpressions
        _incrementDecrementExpressions = snapshot.incrementDecrementExpressions
        _incrementDecrementValueExpressions = snapshot.incrementDecrementValueExpressions
        _callResultCompoundAssignmentBlocks = snapshot.callResultCompoundAssignmentBlocks
        _nonFunctionLambdaLabels = snapshot.nonFunctionLambdaLabels
        _incrementDecrementCachedValues = snapshot.incrementDecrementCachedValues
        _expressionAnnotations = snapshot.expressionAnnotations
        _anonymousFunctionExpressions = snapshot.anonymousFunctionExpressions
        _localFunContextReceivers = snapshot.localFunContextReceivers
        _destructuringDeclLayouts = snapshot.destructuringDeclLayouts
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
            whenSubjectTypeRefs: _whenSubjectTypeRefs,
            lambdaParamTypeRefs: _lambdaParamTypeRefs,
            callableRefReceiverTypeRefs: _callableRefReceiverTypeRefs,
            infixCallExpressions: _infixCallExpressions,
            infixFunctionExpressions: _infixFunctionExpressions,
            operatorFunctionExpressions: _operatorFunctionExpressions,
            explicitCallExpressions: _explicitCallExpressions,
            receiverExpressionArgsCallExpressions: _receiverExpressionArgsCallExpressions,
            incrementDecrementExpressions: _incrementDecrementExpressions,
            incrementDecrementValueExpressions: _incrementDecrementValueExpressions,
            callResultCompoundAssignmentBlocks: _callResultCompoundAssignmentBlocks,
            nonFunctionLambdaLabels: _nonFunctionLambdaLabels,
            incrementDecrementCachedValues: _incrementDecrementCachedValues,
            expressionAnnotations: _expressionAnnotations,
            anonymousFunctionExpressions: _anonymousFunctionExpressions,
            localFunContextReceivers: _localFunContextReceivers,
            destructuringDeclLayouts: _destructuringDeclLayouts
        )
    }

    /// Append one worker's arena after the existing incremental prefix. Internal
    /// edges and side-table keys/values all receive the same namespace offsets.
    /// Callers publish snapshots in input-file order, never completion order.
    func appendFileSnapshot(
        _ snapshot: ASTArenaSnapshot,
        sharedStringCount: Int,
        addedStrings: [InternedString]
    ) -> ASTIDRemapper {
        lock.lock()
        defer { lock.unlock() }
        let remapper = ASTIDRemapper(
            declOffset: Int32(_decls.count),
            exprOffset: Int32(_exprs.count),
            typeRefOffset: Int32(_typeRefs.count),
            sharedStringCount: sharedStringCount,
            addedStrings: addedStrings
        )
        _decls.append(contentsOf: snapshot.declarations.map { remapper.remap($0) })
        _exprs.append(contentsOf: snapshot.expressions.map { remapper.remap($0) })
        _typeRefs.append(contentsOf: snapshot.typeRefs.map { remapper.remap($0) })
        _expressionRangeIndex = nil
        for (key, value) in snapshot.loopLabels {
            _loopLabels[remapper.remap(key)] = remapper.remap(value)
        }
        for (key, value) in snapshot.whenSubjectVarNames {
            _whenSubjectVarNames[remapper.remap(key)] = remapper.remap(value)
        }
        for (key, value) in snapshot.whenSubjectTypeRefs {
            _whenSubjectTypeRefs[remapper.remap(key)] = remapper.remap(value)
        }
        for (key, value) in snapshot.lambdaParamTypeRefs {
            _lambdaParamTypeRefs[remapper.remap(key)] = value.map { $0.map { remapper.remap($0) } }
        }
        for (key, value) in snapshot.callableRefReceiverTypeRefs {
            _callableRefReceiverTypeRefs[remapper.remap(key)] = remapper.remap(value)
        }
        for (key, value) in snapshot.incrementDecrementCachedValues {
            _incrementDecrementCachedValues[remapper.remap(key)] = remapper.remap(value)
        }
        for (key, value) in snapshot.expressionAnnotations {
            _expressionAnnotations[remapper.remap(key)] = value.map { remapper.remap($0) }
        }
        for (key, value) in snapshot.localFunContextReceivers {
            _localFunContextReceivers[remapper.remap(key)] = value.map { remapper.remap($0) }
        }
        for (key, value) in snapshot.destructuringDeclLayouts {
            _destructuringDeclLayouts[remapper.remap(key)] = DestructuringDeclLayout(
                syntax: value.syntax,
                properties: value.properties.map { $0.map { remapper.remap($0) } },
                mutableFlags: value.mutableFlags
            )
        }
        _anonymousFunctionExpressions.formUnion(snapshot.anonymousFunctionExpressions.map { remapper.remap($0) })
        _infixCallExpressions.formUnion(snapshot.infixCallExpressions.map { remapper.remap($0) })
        _infixFunctionExpressions.formUnion(snapshot.infixFunctionExpressions.map { remapper.remap($0) })
        _operatorFunctionExpressions.formUnion(snapshot.operatorFunctionExpressions.map { remapper.remap($0) })
        _explicitCallExpressions.formUnion(snapshot.explicitCallExpressions.map { remapper.remap($0) })
        _receiverExpressionArgsCallExpressions.formUnion(snapshot.receiverExpressionArgsCallExpressions.map { remapper.remap($0) })
        _incrementDecrementExpressions.formUnion(snapshot.incrementDecrementExpressions.map { remapper.remap($0) })
        _incrementDecrementValueExpressions.formUnion(snapshot.incrementDecrementValueExpressions.map { remapper.remap($0) })
        _callResultCompoundAssignmentBlocks.formUnion(snapshot.callResultCompoundAssignmentBlocks.map { remapper.remap($0) })
        _nonFunctionLambdaLabels.formUnion(snapshot.nonFunctionLambdaLabels.map { remapper.remap($0) })
        return remapper
    }

    public func appendDecl(_ decl: Decl) -> DeclID {
        lock.lock()
        defer { lock.unlock() }
        let id = Int32(_decls.count)
        _decls.append(decl)
        return DeclID(rawValue: id)
    }

    public func prependExpressionAnnotations(_ annotations: [AnnotationNode], for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _expressionAnnotations[exprID] = annotations + (_expressionAnnotations[exprID] ?? [])
    }

    public func expressionAnnotations(for exprID: ExprID) -> [AnnotationNode] {
        lock.lock()
        defer { lock.unlock() }
        return _expressionAnnotations[exprID] ?? []
    }

    public var annotatedExpressions: [ExprID: [AnnotationNode]] {
        lock.lock()
        defer { lock.unlock() }
        return _expressionAnnotations
    }

    public func markAnonymousFunction(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _anonymousFunctionExpressions.insert(exprID)
    }

    public func isAnonymousFunction(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _anonymousFunctionExpressions.contains(exprID)
    }

    public func setLocalFunContextReceivers(_ receivers: [ContextReceiverDecl], for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _localFunContextReceivers[exprID] = receivers
    }

    public func setDestructuringDeclLayout(_ layout: DestructuringDeclLayout, for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _destructuringDeclLayouts[exprID] = layout
    }

    public func destructuringDeclLayout(for exprID: ExprID) -> DestructuringDeclLayout? {
        lock.lock()
        defer { lock.unlock() }
        return _destructuringDeclLayouts[exprID]
    }

    public func localFunContextReceivers(for exprID: ExprID) -> [ContextReceiverDecl] {
        lock.lock()
        defer { lock.unlock() }
        return _localFunContextReceivers[exprID] ?? []
    }

    public func setCallableRefReceiverTypeRef(_ exprID: ExprID, typeRef: TypeRefID) {
        lock.lock()
        defer { lock.unlock() }
        _callableRefReceiverTypeRefs[exprID] = typeRef
    }

    public func callableRefReceiverTypeRef(for exprID: ExprID) -> TypeRefID? {
        lock.lock()
        defer { lock.unlock() }
        return _callableRefReceiverTypeRefs[exprID]
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
             let .nullLiteral(range),
             let .boolLiteral(_, range),
             let .stringLiteral(_, range),
             let .nameRef(_, range),
             let .forExpr(_, _, _, _, range),
             let .whileExpr(_, _, _, range),
             let .doWhileExpr(_, _, _, range),
             let .breakExpr(_, range),
             let .continueExpr(_, range),
             let .localDecl(_, _, _, _, _, _, range),
             let .localAssign(_, _, range),
             let .memberAssign(_, _, _, range),
             let .safeMemberAssign(_, _, _, range),
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
             let .localFunDecl(_, _, _, _, _, _, range, _),
             let .localNominalDecl(_, range),
             let .blockExpr(_, _, range),
             let .superRef(_, _, range),
             let .thisRef(_, range),
             let .inExpr(_, _, range),
             let .notInExpr(_, _, range),
             let .destructuringDecl(_, _, _, range),
             let .forDestructuringExpr(_, _, _, _, range):
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

    public func setWhenSubjectTypeRef(_ typeRef: TypeRefID, for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _whenSubjectTypeRefs[exprID] = typeRef
    }

    public func whenSubjectTypeRef(for exprID: ExprID) -> TypeRefID? {
        lock.lock()
        defer { lock.unlock() }
        return _whenSubjectTypeRefs[exprID]
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

    public func markInfixFunction(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _infixFunctionExpressions.insert(exprID)
    }

    public func isInfixFunction(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _infixFunctionExpressions.contains(exprID)
    }

    public func markOperatorFunction(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _operatorFunctionExpressions.insert(exprID)
    }

    public func isOperatorFunction(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _operatorFunctionExpressions.contains(exprID)
    }

    public func markInfixCall(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _infixCallExpressions.insert(exprID)
    }

    public func isInfixCall(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _infixCallExpressions.contains(exprID)
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

    public func markReceiverExpressionArgsCall(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _receiverExpressionArgsCallExpressions.insert(exprID)
    }

    public func isReceiverExpressionArgsCall(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _receiverExpressionArgsCallExpressions.contains(exprID)
    }

    public func markCallResultCompoundAssignmentBlock(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _callResultCompoundAssignmentBlocks.insert(exprID)
    }

    public func isCallResultCompoundAssignmentBlock(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _callResultCompoundAssignmentBlocks.contains(exprID)
    }

    public func markIncrementDecrement(
        _ exprID: ExprID,
        cachedValue: ExprID? = nil,
        returnsValue: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }
        _incrementDecrementExpressions.insert(exprID)
        if returnsValue {
            _incrementDecrementValueExpressions.insert(exprID)
        }
        if let cachedValue {
            _incrementDecrementCachedValues[exprID] = cachedValue
        }
    }

    public func incrementDecrementCachedValue(for exprID: ExprID) -> ExprID? {
        lock.lock()
        defer { lock.unlock() }
        return _incrementDecrementCachedValues[exprID]
    }

    public func isIncrementDecrement(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _incrementDecrementExpressions.contains(exprID)
    }

    public func incrementDecrementReturnsValue(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _incrementDecrementValueExpressions.contains(exprID)
    }

    public func markNonFunctionLambdaLabel(_ exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _nonFunctionLambdaLabels.insert(exprID)
    }

    public func isNonFunctionLambdaLabel(_ exprID: ExprID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _nonFunctionLambdaLabels.contains(exprID)
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
    public let sortedFiles: [ASTFile]

    /// Files indexed by fileID so resolving a declaration's owning file does
    /// not scan the whole file list. `fileID` is unique per file, so a
    /// dictionary hit is identical to `files.first { $0.fileID == fileID }`.
    private let filesByID: [FileID: ASTFile]

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
        filesByID = Dictionary(
            files.map { ($0.fileID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // ASTModule is finalized after all expressions have been appended, so
        // build the index before the first position-based query pays for it.
        arena.prepareExpressionRangeIndex()
    }

    /// Each Sema worker gets its own arena lock and copy-on-write storage.
    /// Scalar inference preserves every AST ID and never needs the LSP range
    /// index, so copying the finalized module avoids rebuilding that index.
    func makeSemaWorkerAST() -> ASTModule {
        ASTModule(workerSnapshotOf: self)
    }

    private init(workerSnapshotOf module: ASTModule) {
        files = module.files
        arena = ASTArena(snapshot: module.arena.snapshot())
        declarationCount = module.declarationCount
        tokenCount = module.tokenCount
        activeDeclsByFileRawID = module.activeDeclsByFileRawID
        sortedFiles = module.sortedFiles
        filesByID = module.filesByID
    }

    /// O(1) lookup of the file with `fileID`; identical result to a linear
    /// `files.first { $0.fileID == fileID }` scan.
    public func file(for fileID: FileID) -> ASTFile? {
        filesByID[fileID]
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
