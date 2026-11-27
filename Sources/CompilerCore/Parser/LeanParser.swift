import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum LeanParser {
    private typealias Initialize = @convention(c) () -> Int32
    private typealias ReadToken = @convention(c) (UnsafeMutableRawPointer, Int) -> UInt32
    private typealias RecordCache = @convention(c) (UnsafeMutableRawPointer, Int, Int, UInt8) -> Void
    private typealias ReportBudget = @convention(c) (UnsafeMutableRawPointer, Int) -> Void
    private typealias ParseFileItem = @convention(c) (UnsafeMutableRawPointer, UInt8) -> UInt64
    private typealias EmitFileItem = @convention(c) (UnsafeMutableRawPointer, UInt8, UInt) -> UInt
    private typealias ParseFile = @convention(c) (
        UnsafeMutableRawPointer, UnsafeMutableRawPointer, ReadToken, RecordCache, ReportBudget,
        ParseFileItem, EmitFileItem, Int, Int, UInt32
    ) -> UInt64
    private typealias CanStart = @convention(c) (UnsafeMutableRawPointer, ReadToken, Int, Int, UInt8) -> Int32
    private typealias Lookahead = @convention(c) (UnsafeMutableRawPointer, ReadToken, Int, Int, UInt8, UInt) -> UInt
    private typealias ClassifyToken = @convention(c) (UInt8) -> Int32
    private typealias ClassifyBoundary = @convention(c) (UInt8, UInt8, UInt8) -> Int32
    private typealias Scan = @convention(c) (
        UnsafeMutableRawPointer, ReadToken, RecordCache, ReportBudget, Int, Int, UInt32
    ) -> UInt64
    private typealias ScanAnnotationPrefix = @convention(c) (
        UnsafeMutableRawPointer, ReadToken, ReportBudget, Int, Int, UInt32
    ) -> UInt64
    private typealias FlaggedScan = @convention(c) (
        UnsafeMutableRawPointer, ReadToken, RecordCache, ReportBudget, Int, Int, UInt8, UInt32
    ) -> UInt64
    private typealias ScanGroup = @convention(c) (
        UnsafeMutableRawPointer, ReadToken, RecordCache, ReportBudget,
        Int, Int, UInt8, UInt8, UInt8, UInt32
    ) -> UInt64

    private struct Bindings: Sendable {
        let parseFile: ParseFile
        let canStart: CanStart
        let lookahead: Lookahead
        let classifyBeforeNewline: ClassifyToken
        let classifySplitOnNewline: ClassifyToken
        let classifyStatementStop: ClassifyBoundary
        let scan: Scan
        let declarationPrefix: FlaggedScan
        let annotationPrefix: ScanAnnotationPrefix
        let propertyAccessor: FlaggedScan
        let scanGroup: ScanGroup
    }

    private static let readToken: ReadToken = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        return LeanParser.encodeToken(parser, index: index)
    }

    private static let parseFileItem: ParseFileItem = { state, code in
        let file = Unmanaged<KotlinParser.FileAssembly>.fromOpaque(state).takeUnretainedValue()
        guard let dispatch = TopLevelDispatch(rawValue: UInt64(code)),
              let node = file.parseItem(dispatch), let cursor = UInt64(exactly: file.cursor),
              cursor <= UInt64.max >> 8
        else { return UInt64.max }
        return (cursor << 8) | UInt64(syntaxKindCode(node.kind))
    }

    private static let emitFileItem: EmitFileItem = { state, flags, separators in
        let file = Unmanaged<KotlinParser.FileAssembly>.fromOpaque(state).takeUnretainedValue()
        guard let count = Int(exactly: separators),
              let cursor = file.emitItem(FilePlacementAction(flags: flags), separators: count)
        else { return UInt.max }
        return UInt(cursor)
    }

    private static let readFileTopLevelToken: ReadToken = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        if index == parser.stream.index {
            switch parser.stream.peek().kind {
            case .keyword(.package): return TokenCode.packageKeyword.rawValue
            case .keyword(.import): return TokenCode.importKeyword.rawValue
            default: break
            }
        }
        return LeanParser.encodeToken(parser, index: index)
    }

    private static let readReceiverToken: ReadToken = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        return LeanParser.encodeToken(parser, index: index, includesReceiverTarget: true)
    }

    private static let readPropertyTailToken: ReadToken = { state, index in
        let tokens = state.assumingMemoryBound(to: UnsafeBufferPointer<UInt32>.self).pointee
        return tokens.indices.contains(index) ? tokens[index] : TokenCode.eof.rawValue
    }

    private static let readStatementBoundaryToken: ReadToken = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        let token = parser.stream.peek(index - parser.stream.index)
        var code = statementBoundaryTokenCode(token.kind).rawValue
        if parser.hasLeadingNewline(token) { code |= 256 }
        if parser.isIdentifierLike(token.kind) { code |= 512 }
        return code
    }

    private static let readDeclarationDispatchToken: ReadToken = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        let kind = parser.stream.peek(index - parser.stream.index).kind
        let code: TokenCode = switch kind {
        case .keyword(.class): .classKeyword
        case .keyword(.interface): .interfaceKeyword
        case .keyword(.val), .keyword(.var): .propertyKeyword
        case .keyword(.typealias): .typeAliasKeyword
        case .keyword(.constructor), .softKeyword(.constructor): .constructorKeyword
        case .softKeyword(.get), .softKeyword(.set): .accessorKeyword
        default: statementBoundaryTokenCode(kind)
        }
        return code.rawValue | (parser.isIdentifierLike(kind) ? 512 : 0)
    }

    private static let readSyntaxPolicyToken: ReadToken = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        let token = parser.stream.peek(index - parser.stream.index)
        let code = syntaxPolicyTokenCode(token.kind).rawValue
        return code | (parser.hasLeadingNewline(token) ? 256 : 0)
    }

    private static let readLabelToken: ReadToken = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        let kind = parser.stream.peek(index - parser.stream.index).kind
        return (kind == .symbol(.at) ? TokenCode.at.rawValue : 0) | (kind.isLabelName ? 512 : 0)
    }

    private struct WhenSubjectTail {
        let arena: SyntaxArena
        let children: [SyntaxChild]
    }

    private static let readWhenSubjectTailToken: ReadToken = { state, offset in
        let tail = state.assumingMemoryBound(to: WhenSubjectTail.self).pointee
        guard tail.children.indices.contains(offset) else { return TokenCode.eof.rawValue }
        let index = tail.children.count - 1 - offset
        guard case let .token(id) = tail.children[index], let token = tail.arena.token(id) else {
            return TokenCode.nonToken.rawValue
        }
        return syntaxPolicyTokenCode(token.kind).rawValue
    }

    private static let recordCache: RecordCache = { state, start, end, declares in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        for index in start ..< end {
            parser.modifierDeclarationLookahead[index] = declares != 0
        }
    }

    private static let reportBudget: ReportBudget = { state, index in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        parser.reportDeclarationLookaheadBudget(at: index - parser.stream.index)
    }

    private static let recordGenuineCache: RecordCache = { state, start, end, declares in
        let parser = Unmanaged<KotlinParser>.fromOpaque(state).takeUnretainedValue()
        for index in start ..< end {
            parser.genuineDeclarationLookahead[index] = declares != 0
        }
    }

    private static let bindings: Bindings? = {
        #if os(macOS)
        let library = "liblean_parser.dylib"
        #else
        let library = "liblean_parser.so"
        #endif
        let embedded = Bundle.module
        // SwiftPM can retain an older copy of the resource bundle inside an incremental XCTest build.
        let sibling = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent(embedded.bundleURL.lastPathComponent))
        for bundle in [embedded, sibling].compactMap({ $0 }) {
            guard let directory = bundle.resourceURL?.appendingPathComponent("LeanParserResources"),
                  let stamp = try? String(contentsOf: directory.appendingPathComponent(".build-id"), encoding: .utf8),
                  stamp == LeanParserBuildIdentity.fingerprint + "\n",
                  let handle = dlopen(directory.appendingPathComponent(library).path, RTLD_NOW | RTLD_LOCAL)
            else {
                continue
            }
            guard let initialize = dlsym(handle, "kswiftk_lean_parser_init"),
                  let parseFile = dlsym(handle, "kswiftk_lean_parser_parse_file"),
                  let canStart = dlsym(handle, "kswiftk_lean_parser_can_start_type_arguments"),
                  let lookahead = dlsym(handle, "kswiftk_lean_parser_run_lookahead"),
                  let classifyBeforeNewline = dlsym(handle, "kswiftk_lean_parser_classify_before_newline"),
                  let classifySplitOnNewline = dlsym(handle, "kswiftk_lean_parser_classify_split_on_newline"),
                  let classifyStatementStop = dlsym(handle, "kswiftk_lean_parser_classify_statement_stop"),
                  let scan = dlsym(handle, "kswiftk_lean_parser_scan"),
                  let declarationPrefix = dlsym(handle, "kswiftk_lean_parser_declaration_prefix"),
                  let annotationPrefix = dlsym(handle, "kswiftk_lean_parser_annotation_prefix"),
                  let propertyAccessor = dlsym(handle, "kswiftk_lean_parser_property_accessor"),
                  let scanGroup = dlsym(handle, "kswiftk_lean_parser_scan_group"),
                  unsafeBitCast(initialize, to: Initialize.self)() == 1
            else {
                return nil
            }
            return Bindings(
                parseFile: unsafeBitCast(parseFile, to: ParseFile.self),
                canStart: unsafeBitCast(canStart, to: CanStart.self),
                lookahead: unsafeBitCast(lookahead, to: Lookahead.self),
                classifyBeforeNewline: unsafeBitCast(classifyBeforeNewline, to: ClassifyToken.self),
                classifySplitOnNewline: unsafeBitCast(classifySplitOnNewline, to: ClassifyToken.self),
                classifyStatementStop: unsafeBitCast(classifyStatementStop, to: ClassifyBoundary.self),
                scan: unsafeBitCast(scan, to: Scan.self),
                declarationPrefix: unsafeBitCast(declarationPrefix, to: FlaggedScan.self),
                annotationPrefix: unsafeBitCast(annotationPrefix, to: ScanAnnotationPrefix.self),
                propertyAccessor: unsafeBitCast(propertyAccessor, to: FlaggedScan.self),
                scanGroup: unsafeBitCast(scanGroup, to: ScanGroup.self)
            )
        }
        return nil
    }()

    private enum LookaheadOperation: UInt8 {
        case angles, parens, annotation, defaultTypeArguments, anonymousFunction, leadingPrefix, annotatedEnumEntry
        case primaryConstructorHeader, propertyTailAccessor, explicitBackingField
        case objectExpression, ambiguousDeclarationPrefix
        case afterBlock, afterNewline, recovery, nestingRecovery, qualifiedPath, headerDeclaration
        case topLevelRecovery = 19, declarationDispatch, declarationPrefixHead
        case labelStart, loopStart, typeNameStart, whenConditionNewline, companionName, bareDeclarationStart
        case constructorTail, declarationHeaderNewline, whenSubjectTail
    }

    private static func lookahead(
        _ parser: KotlinParser, offset: Int, operation: LookaheadOperation,
        argument: UInt = 0, reader: ReadToken = readToken
    ) -> Int? {
        guard let bindings else {
            parser.reportUnavailableLeanParser()
            return nil
        }
        let state = Unmanaged.passUnretained(parser).toOpaque()
        let result = withExtendedLifetime(parser) {
            bindings.lookahead(
                state, reader, parser.stream.tokens.count, parser.stream.index + offset,
                operation.rawValue, argument
            )
        }
        if result == UInt.max {
            parser.reportUnavailableLeanParser()
            return nil
        }
        return result == 0 ? nil : Int(result - 1)
    }

    enum DeclarationDispatch: Int {
        case classDecl, objectDecl, interfaceDecl, funInterface, function, property, typeAlias
        case enumDecl, packageHeader, importHeader, constructor
        case companionObject, companionBlock, retryAfterCompanion, retryAfterEnum
        case statement, prefixedStatement, invalidAccessor
    }

    static func declarationDispatch(_ parser: KotlinParser, hasPrefix: Bool) -> DeclarationDispatch? {
        guard let code = lookahead(
            parser, offset: 0, operation: .declarationDispatch, argument: hasPrefix ? 1 : 0,
            reader: readDeclarationDispatchToken
        ) else { return nil }
        guard let dispatch = DeclarationDispatch(rawValue: code) else {
            parser.reportUnavailableLeanParser()
            return nil
        }
        return dispatch
    }

    static func offsetPastTypeArguments(_ parser: KotlinParser, from offset: Int) -> Int {
        lookahead(parser, offset: offset, operation: .angles).map { $0 - parser.stream.index } ?? offset
    }

    static func offsetPastParens(_ parser: KotlinParser, from offset: Int, maxDistance: Int?) -> Int {
        let limit = maxDistance.map { UInt(clamping: $0) + 1 } ?? 0
        return lookahead(parser, offset: offset, operation: .parens, argument: limit)
            .map { $0 - parser.stream.index } ?? offset
    }

    static func offsetPastAnnotation(_ parser: KotlinParser, from offset: Int) -> Int? {
        lookahead(parser, offset: offset, operation: .annotation).map { $0 - parser.stream.index }
    }

    enum LeadingPrefixMode: UInt {
        case declaration, annotations, receiver
    }

    static func scanLeadingPrefix(
        _ parser: KotlinParser, mode: LeadingPrefixMode
    ) -> (consumed: Int, recovered: Bool)? {
        let reader = mode == .receiver ? readReceiverToken : readToken
        guard let packed = lookahead(
            parser, offset: 0, operation: .leadingPrefix, argument: mode.rawValue, reader: reader
        ),
              let result = decodeScan(UInt64(packed), parser: parser)
        else { return nil }
        return (result.consumed, packed & 3 == 2)
    }

    enum DeclarationContextClause: Int {
        case absent, group, missingOpen
    }

    enum DeclarationPrefixHead {
        case contextFirst(DeclarationContextClause)
        case prefixFirst(consumed: Int, recovered: Bool, context: DeclarationContextClause)
    }

    static func declarationPrefixHead(_ parser: KotlinParser) -> DeclarationPrefixHead? {
        guard let packed = lookahead(parser, offset: 0, operation: .declarationPrefixHead) else { return nil }
        let consumed = packed >> 5
        guard let clause = DeclarationContextClause(rawValue: (packed >> 2) & 3),
              consumed <= parser.stream.tokens.count - parser.stream.index
        else {
            parser.reportUnavailableLeanParser()
            return nil
        }
        if packed & 16 != 0 { return .contextFirst(clause) }
        return .prefixFirst(consumed: consumed, recovered: packed & 3 == 2, context: clause)
    }

    static func isLabelStart(_ parser: KotlinParser) -> Bool {
        lookahead(parser, offset: 0, operation: .labelStart, reader: readLabelToken) == 1
    }

    static func isLoopStart(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        lookahead(parser, offset: 0, operation: .loopStart, argument: UInt(syntaxPolicyTokenCode(kind).rawValue)) == 1
    }

    static func canStartTypeName(_ parser: KotlinParser, after kind: TokenKind?) -> Bool {
        let code = kind.map(syntaxPolicyTokenCode) ?? .other
        return lookahead(parser, offset: 0, operation: .typeNameStart, argument: UInt(code.rawValue)) == 1
    }

    static func whenConditionContinuesAfterLineBreak(_ parser: KotlinParser) -> Bool {
        lookahead(parser, offset: 0, operation: .whenConditionNewline) == 1
    }

    static func isCompanionObjectName(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        var code = syntaxPolicyTokenCode(kind).rawValue
        if case .softKeyword = kind { code |= 8192 }
        return lookahead(parser, offset: 0, operation: .companionName, argument: UInt(code)) == 1
    }

    static func isBareDeclarationStart(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        lookahead(
            parser, offset: 0, operation: .bareDeclarationStart, argument: UInt(syntaxPolicyTokenCode(kind).rawValue)
        ) == 1
    }

    static func constructorTailCount(_ parser: KotlinParser) -> Int {
        let start = parser.stream.index
        guard let end = lookahead(parser, offset: 0, operation: .constructorTail, reader: readSyntaxPolicyToken)
        else { return 0 }
        guard end >= start, end <= parser.stream.tokens.count else {
            parser.reportUnavailableLeanParser()
            return 0
        }
        return end - start
    }

    static func stopsDeclarationHeaderAtNewline(
        _ parser: KotlinParser, includeBlock: Bool, allowsClassHeaderColon: Bool, allowsClassDelegation: Bool
    ) -> Bool {
        let options: UInt = (includeBlock ? 1 : 0) | (allowsClassHeaderColon ? 2 : 0) | (allowsClassDelegation ? 4 : 0)
        return lookahead(
            parser, offset: 0, operation: .declarationHeaderNewline, argument: options, reader: readSyntaxPolicyToken
        ) == 1
    }

    static func consumedTokensEndWithWhenSubject(_ parser: KotlinParser, children: [SyntaxChild]) -> Bool {
        guard !children.isEmpty else { return false }
        guard let bindings else {
            parser.reportUnavailableLeanParser()
            return false
        }
        let tail = WhenSubjectTail(arena: parser.arena, children: children)
        let result = withUnsafePointer(to: tail) { state in
            bindings.lookahead(
                UnsafeMutableRawPointer(mutating: state), readWhenSubjectTailToken,
                children.count, 0, LookaheadOperation.whenSubjectTail.rawValue, 0
            )
        }
        if result == UInt.max { parser.reportUnavailableLeanParser() }
        return result == 2
    }

    static func valueParameterDefaultStartsTypeArguments(_ parser: KotlinParser) -> Bool {
        let anchored = parser.lastConsumedToken.map { parser.isIdentifierLike($0.kind) } ?? false
        return lookahead(parser, offset: 0, operation: .defaultTypeArguments, argument: anchored ? 1 : 0) == 1
    }

    static func isAnonymousFunctionExpressionStart(_ parser: KotlinParser, at offset: Int) -> Bool {
        lookahead(parser, offset: offset, operation: .anonymousFunction) == 1
    }

    static func enumEntryStartsAfterLeadingAnnotations(_ parser: KotlinParser) -> Bool {
        lookahead(parser, offset: 0, operation: .annotatedEnumEntry) == 1
    }

    static func startsPrimaryConstructorHeader(_ parser: KotlinParser) -> Bool {
        lookahead(parser, offset: 0, operation: .primaryConstructorHeader) == 1
    }

    static func isExplicitBackingFieldStart(_ parser: KotlinParser) -> Bool {
        lookahead(parser, offset: 0, operation: .explicitBackingField) == 1
    }

    static func isObjectExpressionStart(_ parser: KotlinParser) -> Bool {
        lookahead(parser, offset: 0, operation: .objectExpression) == 1
    }

    static func isDeclarationStart(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        isBareDeclarationStart(parser, kind: kind)
    }

    static func whenConditionContinuesAfterLineBreak(_ parser: KotlinParser, kind _: TokenKind) -> Bool {
        whenConditionContinuesAfterLineBreak(parser)
    }

    static func isObjectExpressionStart(_ parser: KotlinParser, kind _: TokenKind) -> Bool {
        isObjectExpressionStart(parser)
    }

    static func isExplicitBackingFieldStart(_ parser: KotlinParser, kind _: TokenKind) -> Bool {
        isExplicitBackingFieldStart(parser)
    }

    static func isAmbiguousDeclarationPrefix(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        lookahead(
            parser, offset: 0, operation: .ambiguousDeclarationPrefix,
            argument: UInt(tokenCode(kind).rawValue)
        ) == 1
    }

    static func continuesAfterBlock(_ parser: KotlinParser, sawTry: Bool) -> Bool {
        lookahead(parser, offset: 0, operation: .afterBlock, argument: sawTry ? 1 : 0) == 1
    }

    static func continuesExpressionAfterNewline(_ parser: KotlinParser, kind: TokenKind) -> Bool {
        lookahead(
            parser, offset: 0, operation: .afterNewline,
            argument: UInt(tokenCode(kind).rawValue)
        ) == 1
    }

    static func continuesExpressionBeforeNewline(_ token: Token, diagnostics: DiagnosticEngine? = nil) -> Bool {
        classifyToken(token, diagnostics: diagnostics, using: bindings?.classifyBeforeNewline) ?? false
    }

    static func shouldSplitStatementOnNewline(_ token: Token, diagnostics: DiagnosticEngine? = nil) -> Bool {
        classifyToken(token, diagnostics: diagnostics, using: bindings?.classifySplitOnNewline) ?? true
    }

    static func shouldStopStatementBefore(
        _ token: Token, inBlock: Bool, hasLeadingNewline: Bool, diagnostics: DiagnosticEngine
    ) -> Bool {
        let kind = statementBoundaryTokenCode(token.kind)
        guard let result = bindings?.classifyStatementStop(
            UInt8(kind.rawValue), inBlock ? 1 : 0, hasLeadingNewline ? 1 : 0
        ), result >= 0 else {
            reportUnavailable(diagnostics, at: token.rangeIfAvailable)
            return token.kind == .eof || token.kind == .symbol(.rBrace)
        }
        return result == 1
    }

    static func recoverySkipCount(
        _ parser: KotlinParser, inBlock: Bool, fromNestingLimit: Bool = false
    ) -> Int? {
        statementBoundaryScanCount(
            parser, operation: fromNestingLimit ? .nestingRecovery : .recovery, argument: inBlock ? 1 : 0
        )
    }

    struct TopLevelRecovery {
        let skippedCount: Int
        let forceAdvance: Bool
    }

    static func topLevelRecovery(_ parser: KotlinParser, before: Int) -> TopLevelRecovery? {
        if let result = lookahead(
            parser, offset: 0, operation: .topLevelRecovery, argument: UInt(before), reader: readStatementBoundaryToken
        ) {
            guard result != 0 else { return nil }
            let encoded = result - 1
            let plan = TopLevelRecovery(skippedCount: encoded >> 1, forceAdvance: encoded & 1 != 0)
            let count = plan.skippedCount + (plan.forceAdvance ? 1 : 0)
            if count <= parser.stream.tokens.count - parser.stream.index { return plan }
            parser.reportUnavailableLeanParser()
        }
        guard parser.stream.index == before else { return nil }
        return TopLevelRecovery(skippedCount: 0, forceAdvance: !parser.stream.atEOF())
    }

    static func qualifiedPathCount(_ parser: KotlinParser, allowImportWildcard: Bool, stopAtAs: Bool) -> Int {
        let options: UInt = (allowImportWildcard ? 1 : 0) | (stopAtAs ? 2 : 0)
        return statementBoundaryScanCount(parser, operation: .qualifiedPath, argument: options) ?? 0
    }

    enum HeaderAlias: Int {
        case absent = 0, missing = 1, present = 2
    }

    struct HeaderPlan {
        let hasKeyword: Bool
        let pathCount: Int
        let alias: HeaderAlias
        let hasTerminator: Bool
    }

    static func headerPlan(_ parser: KotlinParser, isImport: Bool) -> HeaderPlan? {
        guard let result = lookahead(
            parser, offset: 0, operation: .headerDeclaration, argument: isImport ? 1 : 0,
            reader: readStatementBoundaryToken
        ) else { return nil }
        guard let alias = HeaderAlias(rawValue: (result >> 2) & 3) else {
            parser.reportUnavailableLeanParser()
            return nil
        }
        let plan = HeaderPlan(
            hasKeyword: result & 1 != 0,
            pathCount: result >> 4,
            alias: alias,
            hasTerminator: result & 2 != 0
        )
        let count = (plan.hasKeyword ? 1 : 0) + plan.pathCount + alias.rawValue + (plan.hasTerminator ? 1 : 0)
        guard count <= parser.stream.tokens.count - parser.stream.index else {
            parser.reportUnavailableLeanParser()
            return nil
        }
        return plan
    }

    static func parseFile(_ parser: KotlinParser, assembly: KotlinParser.FileAssembly) -> FilePlacementAction {
        guard let bindings else {
            parser.reportUnavailableLeanParser()
            return FilePlacementAction(flags: 0)
        }
        let result = withExtendedLifetime((parser, assembly)) {
            bindings.parseFile(
                Unmanaged.passUnretained(parser).toOpaque(), Unmanaged.passUnretained(assembly).toOpaque(),
                readFileTopLevelToken, recordGenuineCache, reportBudget, parseFileItem, emitFileItem,
                parser.stream.tokens.count, parser.stream.index, UInt32(KotlinParser.declarationLookaheadWorkLimit)
            )
        }
        if result > 255 { parser.reportUnavailableLeanParser() }
        return FilePlacementAction(flags: result <= 511 ? UInt8(truncatingIfNeeded: result) : 0)
    }

    private static func syntaxKindCode(_ kind: SyntaxKind) -> UInt8 {
        switch kind {
        case .kotlinFile: 0
        case .script: 1
        case .packageHeader: 2
        case .importList: 3
        case .importHeader: 4
        case .classDecl: 5
        case .objectDecl: 6
        case .interfaceDecl: 7
        case .funDecl: 8
        case .propertyDecl: 9
        case .propertyAccessor: 10
        case .typeAliasDecl: 11
        case .enumEntry: 12
        case .constructorDecl: 13
        case .statement: 14
        case .block: 15
        case .loopStmt: 16
        case .tryExpr: 17
        case .ifExpr: 18
        case .whenExpr: 19
        case .whenEntry: 20
        case .whenConditionList: 21
        case .whenCondition: 22
        case .callExpr: 23
        case .typeArgs: 24
        }
    }

    struct FilePlacementAction {
        fileprivate let flags: UInt8
        var lateImport: Bool { flags & 16 != 0 }
        var appendImport: Bool { flags & 32 != 0 }
        var flushImports: Bool { flags & 64 != 0 }
        var rootKind: SyntaxKind { flags & 128 != 0 ? .script : .kotlinFile }
    }

    private static func statementBoundaryScanCount(
        _ parser: KotlinParser, operation: LookaheadOperation, argument: UInt
    ) -> Int? {
        guard let end = lookahead(
            parser, offset: 0, operation: operation, argument: argument, reader: readStatementBoundaryToken
        ) else { return nil }
        let start = parser.stream.index
        guard end >= start, end <= parser.stream.tokens.count else {
            parser.reportUnavailableLeanParser()
            return nil
        }
        return end - start
    }

    private static func classifyToken(
        _ token: Token, diagnostics: DiagnosticEngine?, using classify: ClassifyToken?
    ) -> Bool? {
        guard let result = classify?(UInt8(tokenCode(token.kind).rawValue)), result >= 0 else {
            reportUnavailable(diagnostics, at: token.rangeIfAvailable)
            return nil
        }
        return result == 1
    }

    static func reportUnavailable(_ diagnostics: DiagnosticEngine?, at range: SourceRange?) {
        diagnostics?.error(
            "KSWIFTK-PARSE-0032",
            "Unable to run the bundled Lean parser. Build it with Scripts/build_lean.sh and rebuild the compiler.",
            range: range
        )
    }

    static func scanBalancedGroup(
        _ parser: KotlinParser, opening: Symbol, closing: Symbol,
        allowsValueParameters: Bool, allowsWhenSubjectVariable: Bool
    ) -> (consumed: Int, unterminated: Bool)? {
        guard let bindings else { return nil }
        let state = Unmanaged.passUnretained(parser).toOpaque()
        let options: UInt8 = (allowsValueParameters ? 1 : 0) | (allowsWhenSubjectVariable ? 2 : 0)
        let result = withExtendedLifetime(parser) {
            bindings.scanGroup(
                state, readToken, recordCache, reportBudget,
                parser.stream.tokens.count, parser.stream.index,
                UInt8(tokenCode(.symbol(opening)).rawValue),
                UInt8(tokenCode(.symbol(closing)).rawValue), options,
                UInt32(KotlinParser.declarationLookaheadWorkLimit)
            )
        }
        return decodeScan(result, parser: parser)
    }

    static func canStartTypeArguments(_ parser: KotlinParser, hasAnchorToken: Bool) -> Bool? {
        guard let bindings else { return nil }
        let state = Unmanaged.passUnretained(parser).toOpaque()
        let result = withExtendedLifetime(parser) {
            bindings.canStart(
                state, readToken, parser.stream.tokens.count, parser.stream.index, hasAnchorToken ? 1 : 0
            )
        }
        guard result >= 0 else { return nil }
        return result == 1
    }

    static func scanTypeArguments(_ parser: KotlinParser) -> (consumed: Int, unterminated: Bool)? {
        guard let bindings else { return nil }
        let state = Unmanaged.passUnretained(parser).toOpaque()
        let result = withExtendedLifetime(parser) {
            bindings.scan(
                state,
                readToken,
                recordCache,
                reportBudget,
                parser.stream.tokens.count,
                parser.stream.index,
                UInt32(KotlinParser.declarationLookaheadWorkLimit)
            )
        }
        return decodeScan(result, parser: parser)
    }

    private enum DeclarationScanMode: UInt8 {
        case verdict, boundary, enumBody = 3
    }

    private static func scanDeclaration(
        _ parser: KotlinParser, at offset: Int, mode: DeclarationScanMode
    ) -> UInt64? {
        guard let bindings else {
            parser.reportUnavailableLeanParser()
            return nil
        }
        let state = Unmanaged.passUnretained(parser).toOpaque()
        let result = withExtendedLifetime(parser) {
            bindings.declarationPrefix(
                state, readToken,
                recordGenuineCache, reportBudget, parser.stream.tokens.count,
                parser.stream.index + offset, mode.rawValue, UInt32(KotlinParser.declarationLookaheadWorkLimit)
            )
        }
        if result == UInt64.max {
            parser.reportUnavailableLeanParser()
            return nil
        }
        return result
    }

    static func declarationPrefixVerdict(_ parser: KotlinParser, at offset: Int) -> KotlinParser.DeclarationPrefixVerdict {
        guard let result = scanDeclaration(parser, at: offset, mode: .verdict) else { return .notDeclaration }
        switch result {
        case 0: return .notDeclaration
        case 1: return .declaration
        case 2: return .overBudget
        default:
            parser.reportUnavailableLeanParser()
            return .notDeclaration
        }
    }

    static func isGenuineDeclarationBoundary(_ parser: KotlinParser) -> Bool {
        guard let result = scanDeclaration(parser, at: 0, mode: .boundary) else { return true }
        return result == 1
    }

    static func enumBodyStartsDeclaration(_ parser: KotlinParser) -> Bool {
        scanDeclaration(parser, at: 0, mode: .enumBody) == 1
    }

    enum TopLevelDispatch: UInt64 {
        case packageHeader = 0, importHeader = 1, declaration = 2, statement = 3, eof = 4
    }

    static func isPropertyAccessorStart(_ parser: KotlinParser, allowsBodyless: Bool) -> Bool {
        guard let bindings else {
            parser.reportUnavailableLeanParser()
            return false
        }
        let state = Unmanaged.passUnretained(parser).toOpaque()
        let result = withExtendedLifetime(parser) {
            bindings.propertyAccessor(
                state, readToken, recordGenuineCache, reportBudget, parser.stream.tokens.count,
                parser.stream.index, allowsBodyless ? 1 : 0, UInt32(KotlinParser.declarationLookaheadWorkLimit)
            )
        }
        if result == UInt64.max { parser.reportUnavailableLeanParser() }
        return result == 1
    }

    static func propertyTailContainsAccessorHeader(_ parser: KotlinParser, children: [SyntaxChild]) -> Bool {
        let tokens: [UInt32] = children.compactMap { child in
            guard case let .token(id) = child, let token = parser.arena.token(id) else { return nil }
            return encodePropertyTailToken(token.kind)
        }
        guard !tokens.isEmpty else { return false }
        guard let bindings else {
            parser.reportUnavailableLeanParser()
            return false
        }
        let result = tokens.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: buffer) { state in
                bindings.lookahead(
                    UnsafeMutableRawPointer(mutating: state), readPropertyTailToken,
                    buffer.count, 0, LookaheadOperation.propertyTailAccessor.rawValue, 0
                )
            }
        }
        if result == UInt.max { parser.reportUnavailableLeanParser() }
        return result == 2
    }

    enum AnnotationPrefixEnd: Equatable {
        case complete(Int)
        case incomplete(Int)
        case overBudget(Int)
    }

    static func annotationPrefixEnd(_ parser: KotlinParser, from offset: Int) -> AnnotationPrefixEnd {
        guard let bindings else {
            parser.reportUnavailableLeanParser()
            return .incomplete(offset)
        }
        let state = Unmanaged.passUnretained(parser).toOpaque()
        let result = withExtendedLifetime(parser) {
            bindings.annotationPrefix(
                state, readToken, reportBudget, parser.stream.tokens.count,
                parser.stream.index + offset, UInt32(KotlinParser.declarationLookaheadWorkLimit)
            )
        }
        let end = Int(result >> 2) - parser.stream.index
        switch result & 3 {
        case 0: return .complete(end)
        case 1: return .incomplete(end)
        case 2: return .overBudget(end)
        default:
            parser.reportUnavailableLeanParser()
            return .incomplete(offset)
        }
    }

    private static func decodeScan(_ result: UInt64, parser: KotlinParser) -> (consumed: Int, unterminated: Bool)? {
        guard let consumed = Int(exactly: result >> 2),
              consumed <= parser.stream.tokens.count - parser.stream.index
        else { return nil }
        return (consumed, result & 3 >= 2)
    }

    private enum TokenCode: UInt32 {
        case other = 0, openAngle, closeAngle, at, dot, colon
        case openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace
        case templateStart, templateEnd, context, modifier, declaration, varianceIn, eof
        case identifier, star, varianceOut, comma, question, questionDot, doubleColon
        case assign, funKeyword, objectKeyword, semicolon
        case bang, bangBang, isKeyword, literal, expressionKeyword, plus, minus, stringStart
        case catchKeyword, finallyKeyword, elseKeyword, asKeyword, byKeyword
        case slash, percent, ampAmp, barBar, equalEqual, bangEqual
        case tripleEqual, notTripleEqual, lessOrEqual, greaterOrEqual
        case plusAssign, minusAssign, starAssign, slashAssign, percentAssign
        case dotDot, dotDotLt, questionQuestion, questionColon, arrow
        case enumKeyword, importKeyword, returnKeyword, companionKeyword, packageKeyword
        case classKeyword, interfaceKeyword, propertyKeyword, typeAliasKeyword, constructorKeyword, accessorKeyword
        case loopKeyword, whenKeyword, softWhenKeyword, companionNameKeyword, whereKeyword
        case constructorDelegationKeyword, nonToken
    }

    private static func accessorKeywordFlags(_ kind: TokenKind) -> UInt32 {
        switch kind {
        case .softKeyword(.get): 33554432
        case .softKeyword(.set): 67108864
        default: 0
        }
    }

    private static func encodePropertyTailToken(_ kind: TokenKind) -> UInt32 {
        switch kind {
        case .keyword, .softKeyword:
            return tokenCode(kind).rawValue | accessorKeywordFlags(kind) | 536870912
        case .eof:
            // An arena token within the buffer must not act as the end-of-buffer sentinel.
            return TokenCode.other.rawValue
        default:
            return tokenCode(kind).rawValue
        }
    }

    private static func encodeToken(_ parser: KotlinParser, index: Int, includesReceiverTarget: Bool = false) -> UInt32 {
        let token = parser.stream.peek(index - parser.stream.index)
        var result = tokenCode(token.kind).rawValue
        if parser.hasLeadingNewline(token) { result |= 256 }
        if parser.isIdentifierLike(token.kind) { result |= 512 }
        if parser.isAnnotationUseSiteTarget(token) { result |= 1024 }
        if token.kind == .keyword(.constructor) || token.kind == .softKeyword(.constructor) {
            result |= 16777216
        }
        if includesReceiverTarget, parser.isReceiverUseSiteTarget(token) { result |= 8388608 }
        if let cached = parser.modifierDeclarationLookahead[index] {
            result |= 2048
            if cached { result |= 4096 }
        }
        if let cached = parser.genuineDeclarationLookahead[index] {
            result |= 2097152
            if cached { result |= 4194304 }
        }
        switch token.kind {
        case .softKeyword(.field):
            result |= 8192 | 1073741824
        case .softKeyword:
            result |= 8192 | accessorKeywordFlags(token.kind)
        case .keyword(.public), .keyword(.private), .keyword(.internal), .keyword(.protected):
            result |= 16384 | 134217728
        case .keyword(.inline):
            result |= 268435456
        case .keyword(.override), .keyword(.final), .keyword(.open), .keyword(.actual), .keyword(.expect),
             .keyword(.vararg), .keyword(.noinline), .keyword(.crossinline):
            result |= 16384
        case .keyword(.val):
            result |= 32768 | 65536 | 1048576
        case .keyword(.var):
            result |= 32768 | 1048576
        case .keyword(.class):
            result |= 131072
        case .keyword(.companion):
            result |= 262144
        case .keyword(.value):
            result |= 524288
        case .keyword(.interface), .keyword(.typealias):
            result |= 1048576
        default:
            break
        }
        return result
    }

    private static func statementBoundaryTokenCode(_ kind: TokenKind) -> TokenCode {
        switch kind {
        case .keyword(.enum): .enumKeyword
        case .keyword(.import): .importKeyword
        case .keyword(.package): .packageKeyword
        case .keyword(.return): .returnKeyword
        case .keyword(.companion): .companionKeyword
        default: tokenCode(kind)
        }
    }

    private static func syntaxPolicyTokenCode(_ kind: TokenKind) -> TokenCode {
        switch kind {
        case .keyword(.for), .keyword(.while), .keyword(.do): .loopKeyword
        case .keyword(.when): .whenKeyword
        case .softKeyword(.when): .softWhenKeyword
        case .keyword(.dynamic), .keyword(.reified): .companionNameKeyword
        case .keyword(.constructor): .constructorKeyword
        case .softKeyword(.where): .whereKeyword
        case .keyword(.this), .keyword(.super): .constructorDelegationKeyword
        default: statementBoundaryTokenCode(kind)
        }
    }

    private static func tokenCode(_ kind: TokenKind) -> TokenCode {
        switch kind {
        case .symbol(.lessThan): .openAngle
        case .symbol(.greaterThan): .closeAngle
        case .symbol(.at): .at
        case .symbol(.dot): .dot
        case .symbol(.colon): .colon
        case .symbol(.lParen): .openParen
        case .symbol(.rParen): .closeParen
        case .symbol(.lBracket): .openBracket
        case .symbol(.rBracket): .closeBracket
        case .symbol(.lBrace): .openBrace
        case .symbol(.rBrace): .closeBrace
        case .templateExprStart: .templateStart
        case .templateExprEnd: .templateEnd
        case .softKeyword(.context): .context
        case .keyword(.in): .varianceIn
        case .identifier, .backtickedIdentifier: .identifier
        case .symbol(.star): .star
        case .softKeyword(.out): .varianceOut
        case .symbol(.comma): .comma
        case .symbol(.question): .question
        case .symbol(.questionDot): .questionDot
        case .symbol(.doubleColon): .doubleColon
        case .symbol(.assign): .assign
        case .keyword(.fun): .funKeyword
        case .keyword(.object): .objectKeyword
        case .symbol(.semicolon): .semicolon
        case .symbol(.bang): .bang
        case .symbol(.bangBang): .bangBang
        case .keyword(.is): .isKeyword
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral, .charLiteral:
            .literal
        case .keyword(.true), .keyword(.false), .keyword(.null), .keyword(.if), .keyword(.when),
             .keyword(.try), .keyword(.throw), .keyword(.return), .keyword(.for), .keyword(.while),
             .keyword(.do), .keyword(.super), .keyword(.this):
            .expressionKeyword
        case .symbol(.plus): .plus
        case .symbol(.minus): .minus
        case .stringQuote, .rawStringQuote, .multiDollarStringQuote, .multiDollarRawStringQuote: .stringStart
        case let .keyword(keyword) where KotlinParser.isDeclarationModifierKeyword(keyword): .modifier
        case let .keyword(keyword) where KotlinParser.isDeclarationKeyword(keyword): .declaration
        case .keyword(.catch): .catchKeyword
        case .keyword(.finally): .finallyKeyword
        case .keyword(.else): .elseKeyword
        case .keyword(.as): .asKeyword
        case .softKeyword(.by): .byKeyword
        case .symbol(.slash): .slash
        case .symbol(.percent): .percent
        case .symbol(.ampAmp): .ampAmp
        case .symbol(.barBar): .barBar
        case .symbol(.equalEqual): .equalEqual
        case .symbol(.bangEqual): .bangEqual
        case .symbol(.tripleEqual): .tripleEqual
        case .symbol(.notTripleEqual): .notTripleEqual
        case .symbol(.lessOrEqual): .lessOrEqual
        case .symbol(.greaterOrEqual): .greaterOrEqual
        case .symbol(.plusAssign): .plusAssign
        case .symbol(.minusAssign): .minusAssign
        case .symbol(.starAssign): .starAssign
        case .symbol(.slashAssign): .slashAssign
        case .symbol(.percentAssign): .percentAssign
        case .symbol(.dotDot): .dotDot
        case .symbol(.dotDotLt): .dotDotLt
        case .symbol(.questionQuestion): .questionQuestion
        case .symbol(.questionColon): .questionColon
        case .symbol(.arrow): .arrow
        case .eof: .eof
        default: .other
        }
    }
}
