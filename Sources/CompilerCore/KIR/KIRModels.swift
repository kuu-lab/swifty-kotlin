import Foundation

public struct KIRDeclID: Hashable, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct KIRExprID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = KIRExprID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct KIRParameter: Sendable {
    public let symbol: SymbolID
    public let type: TypeID

    public init(symbol: SymbolID, type: TypeID) {
        self.symbol = symbol
        self.type = type
    }
}

public enum KIRBinaryOp: Equatable, Sendable {
    case add
    case subtract
    case multiply
    case divide
    case modulo
    case equal
    case notEqual
    case lessThan
    case lessOrEqual
    case greaterThan
    case greaterOrEqual
    case logicalAnd
    case logicalOr
}

public enum KIRUnaryOp: Equatable, Sendable {
    case not
    case unaryPlus
    case unaryMinus
}

public enum KIRExprKind: Equatable, Sendable {
    case intLiteral(Int64)
    case longLiteral(Int64)
    case uintLiteral(UInt64)
    case ulongLiteral(UInt64)
    case floatLiteral(Double)
    case doubleLiteral(Double)
    case charLiteral(UInt32)
    case boolLiteral(Bool)
    case stringLiteral(InternedString)
    case symbolRef(SymbolID)
    /// Address of an extern C symbol (e.g. kk_comparator_from_multi_selectors_trampoline).
    case externSymbolAddress(InternedString)
    case temporary(Int32)
    case null
    case unit
}

public enum KIRDispatchKind: Equatable, Sendable {
    case vtable(slot: Int)
    case itable(interfaceSlot: Int, methodSlot: Int)
    /// Used when the receiver's static type is the interface itself (e.g. a
    /// function parameter typed `d: SomeInterface`) rather than a concrete
    /// class — the itable slot assigned to that interface varies per
    /// implementing class and isn't known at this call site, so it's looked
    /// up at runtime from the object's registered (interfaceTypeID -> slot)
    /// map instead of being baked in as a fixed slot index.
    case itableDynamic(interfaceTypeID: Int64, methodSlot: Int)
}

public enum KIRInstruction: Equatable, Sendable {
    case nop
    case beginBlock
    case endBlock
    case label(Int32)
    case jump(Int32)
    case jumpIfEqual(lhs: KIRExprID, rhs: KIRExprID, target: Int32)
    case constValue(result: KIRExprID, value: KIRExprKind)
    case binary(op: KIRBinaryOp, lhs: KIRExprID, rhs: KIRExprID, result: KIRExprID)
    case unary(op: KIRUnaryOp, operand: KIRExprID, result: KIRExprID)
    case nullAssert(operand: KIRExprID, result: KIRExprID)
    case call(symbol: SymbolID?, callee: InternedString, arguments: [KIRExprID], result: KIRExprID?, canThrow: Bool, thrownResult: KIRExprID?, isSuperCall: Bool = false, qualifiedSuperType: SymbolID? = nil)
    case virtualCall(symbol: SymbolID?, callee: InternedString, receiver: KIRExprID, arguments: [KIRExprID], result: KIRExprID?, canThrow: Bool, thrownResult: KIRExprID?, dispatch: KIRDispatchKind)
    case jumpIfNotNull(value: KIRExprID, target: Int32)
    case copy(from: KIRExprID, to: KIRExprID)
    /// Store a value into a global variable identified by its symbol.
    case storeGlobal(value: KIRExprID, symbol: SymbolID)
    /// Load a global variable into a result expression.
    case loadGlobal(result: KIRExprID, symbol: SymbolID)
    case rethrow(value: KIRExprID)
    case returnIfEqual(lhs: KIRExprID, rhs: KIRExprID)
    case returnUnit
    case returnValue(KIRExprID)
    /// Non-local return from a lambda passed to an inline function.
    /// During inline expansion this is converted into a real return
    /// from the enclosing (caller) function.
    case nonLocalReturn(KIRExprID?)
    /// Sentinel markers delimiting an already-wrapped finally guard region.
    /// `appendThrowAwareInstructions` passes instructions between these
    /// sentinels through verbatim to prevent double-wrapping.
    case beginFinallyGuard
    case endFinallyGuard
}

public struct KIRFunction: Sendable {
    public let symbol: SymbolID
    public let name: InternedString
    public let params: [KIRParameter]
    public let returnType: TypeID
    public internal(set) var body: [KIRInstruction]
    public let isSuspend: Bool
    public let isInline: Bool
    /// When true, this function was auto-promoted to inline because it has
    /// function-type parameters. Its body should only be used for inline
    /// expansion and should not be emitted as a standalone LLVM function.
    public let isInlineOnly: Bool
    public let isTailrec: Bool
    public let sourceRange: SourceRange? // function-level source location
    public internal(set) var instructionLocations: [SourceRange?] // per-instruction source locations, parallel to body

    public init(
        symbol: SymbolID, name: InternedString, params: [KIRParameter], returnType: TypeID,
        body: [KIRInstruction], isSuspend: Bool, isInline: Bool, isInlineOnly: Bool = false, isTailrec: Bool = false,
        sourceRange: SourceRange? = nil, instructionLocations: [SourceRange?] = []
    ) {
        self.symbol = symbol; self.name = name; self.params = params
        self.returnType = returnType; self.body = body
        self.isSuspend = isSuspend; self.isInline = isInline
        self.isInlineOnly = isInlineOnly
        self.isTailrec = isTailrec; self.sourceRange = sourceRange
        self.instructionLocations = instructionLocations
    }

    public mutating func replaceBody(_ body: [KIRInstruction]) {
        self.body = body
    }

    public mutating func replaceInstructionLocations(_ instructionLocations: [SourceRange?]) {
        self.instructionLocations = instructionLocations
    }
}

public struct KIRGlobal: Sendable {
    public let symbol: SymbolID
    public let type: TypeID

    public init(symbol: SymbolID, type: TypeID) {
        self.symbol = symbol
        self.type = type
    }
}

public struct KIRNominalType: Sendable, CustomStringConvertible {
    public let symbol: SymbolID
    public let memberDecls: [KIRDeclID]

    public var description: String {
        return "KIRNominalType(\(symbol.rawValue), members: \(memberDecls.count))"
    }

    public init(symbol: SymbolID, memberDecls: [KIRDeclID] = []) {
        self.symbol = symbol
        self.memberDecls = memberDecls
    }
}

public enum KIRDecl: Sendable {
    case function(KIRFunction)
    case global(KIRGlobal)
    case nominalType(KIRNominalType)
}

public struct KIRFile: Sendable, CustomStringConvertible {
    public let fileID: FileID
    public let decls: [KIRDeclID]

    public var description: String {
        return "KIRFile(\(fileID.rawValue), decls: \(decls.count))"
    }

    public init(fileID: FileID, decls: [KIRDeclID]) {
        self.fileID = fileID
        self.decls = decls
    }
}

public final class KIRArena {
    public private(set) var declarations: [KIRDecl] = []
    public private(set) var expressions: [KIRExprKind] = []
    public private(set) var exprTypes: [KIRExprID: TypeID] = [:]
    public private(set) var lambdaCaptureArgsBySymbol: [SymbolID: [KIRExprID]] = [:]
    var callableValueInfoByExprID: [KIRExprID: KIRCallableValueInfo] = [:]

    private let parallelLock = NSLock()
    var isParallelTransformActive = false

    public init() {}

    public func appendDecl(_ decl: KIRDecl) -> KIRDeclID {
        let id = KIRDeclID(rawValue: Int32(declarations.count))
        declarations.append(decl)
        return id
    }

    public func appendExpr(_ expr: KIRExprKind, type: TypeID? = nil) -> KIRExprID {
        if isParallelTransformActive {
            parallelLock.lock()
            defer { parallelLock.unlock() }
            let id = KIRExprID(rawValue: Int32(expressions.count))
            expressions.append(expr)
            if let type { exprTypes[id] = type }
            return id
        }
        let id = KIRExprID(rawValue: Int32(expressions.count))
        expressions.append(expr)
        if let type {
            exprTypes[id] = type
        }
        return id
    }

    public func appendTemporary(type: TypeID? = nil) -> KIRExprID {
        if isParallelTransformActive {
            parallelLock.lock()
            defer { parallelLock.unlock() }
            let id = KIRExprID(rawValue: Int32(expressions.count))
            expressions.append(.temporary(id.rawValue))
            if let type { exprTypes[id] = type }
            return id
        }
        let id = KIRExprID(rawValue: Int32(expressions.count))
        expressions.append(.temporary(id.rawValue))
        if let type {
            exprTypes[id] = type
        }
        return id
    }

    public func decl(_ id: KIRDeclID) -> KIRDecl? {
        let index = Int(id.rawValue)
        guard index >= 0, index < declarations.count else {
            return nil
        }
        return declarations[index]
    }

    public func function(for symbol: SymbolID) -> KIRFunction? {
        declarations.lazy.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl, function.symbol == symbol else {
                return nil
            }
            return function
        }.first
    }

    public func expr(_ id: KIRExprID) -> KIRExprKind? {
        if isParallelTransformActive {
            parallelLock.lock()
            defer { parallelLock.unlock() }
            let index = Int(id.rawValue)
            guard index >= 0, index < expressions.count else { return nil }
            return expressions[index]
        }
        let index = Int(id.rawValue)
        guard index >= 0, index < expressions.count else {
            return nil
        }
        return expressions[index]
    }

    public func setExprType(_ type: TypeID, for id: KIRExprID) {
        if isParallelTransformActive {
            parallelLock.lock()
            defer { parallelLock.unlock() }
            guard Int(id.rawValue) >= 0, Int(id.rawValue) < expressions.count else { return }
            exprTypes[id] = type
            return
        }
        guard expr(id) != nil else {
            return
        }
        exprTypes[id] = type
    }

    public func exprType(_ id: KIRExprID) -> TypeID? {
        if isParallelTransformActive {
            parallelLock.lock()
            defer { parallelLock.unlock() }
            return exprTypes[id]
        }
        return exprTypes[id]
    }

    public func registerLambdaCaptureArgs(_ lambdaSymbol: SymbolID, captureArgs: [KIRExprID]) {
        lambdaCaptureArgsBySymbol[lambdaSymbol] = captureArgs
    }

    func callableValueInfo(for exprID: KIRExprID) -> KIRCallableValueInfo? {
        callableValueInfoByExprID[exprID]
    }

    public func transformFunctions(_ transform: (KIRFunction) -> KIRFunction) {
        if isParallelTransformActive {
            transformFunctionsParallel(transform)
            return
        }
        for index in declarations.indices {
            guard case let .function(function) = declarations[index] else {
                continue
            }
            declarations[index] = .function(transform(function))
        }
    }

    private func transformFunctionsParallel(_ transform: (KIRFunction) -> KIRFunction) {
        let functionIndices: [(Int, KIRFunction)] = declarations.enumerated().compactMap { index, decl in
            guard case let .function(function) = decl else { return nil }
            return (index, function)
        }
        let count = functionIndices.count
        guard count > 4 else {
            for (index, function) in functionIndices {
                declarations[index] = .function(transform(function))
            }
            return
        }

        withoutActuallyEscaping(transform) { escapingTransform in
            let work = ParallelTransformWork(
                functions: functionIndices,
                transform: escapingTransform
            )
            DispatchQueue.concurrentPerform(iterations: count) { i in
                let result = work.transform(work.functions[i].1)
                work.lock.lock()
                work.results[i] = result
                work.lock.unlock()
            }
            for i in 0..<count {
                if let result = work.results[i] {
                    declarations[functionIndices[i].0] = .function(result)
                }
            }
        }
    }
}

private final class ParallelTransformWork: @unchecked Sendable {
    let functions: [(Int, KIRFunction)]
    let transform: (KIRFunction) -> KIRFunction
    let lock = NSLock()
    var results: [Int: KIRFunction] = [:]

    init(functions: [(Int, KIRFunction)], transform: @escaping (KIRFunction) -> KIRFunction) {
        self.functions = functions
        self.transform = transform
    }
}

public struct KIRModuleFeatures: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let hasBeginEndBlock         = KIRModuleFeatures(rawValue: 1 << 0)
    public static let hasBinaryOp              = KIRModuleFeatures(rawValue: 1 << 1)
    public static let hasUnaryOp               = KIRModuleFeatures(rawValue: 1 << 2)
    public static let hasNullAssert            = KIRModuleFeatures(rawValue: 1 << 3)
    public static let hasTailrecFunction       = KIRModuleFeatures(rawValue: 1 << 4)
    public static let hasInlineFunction        = KIRModuleFeatures(rawValue: 1 << 5)
    public static let hasSuspendFunction       = KIRModuleFeatures(rawValue: 1 << 6)
    public static let hasNonTerminatedFunction = KIRModuleFeatures(rawValue: 1 << 7)
}

public final class KIRModule {
    public let files: [KIRFile]
    public let arena: KIRArena
    public private(set) var executedLowerings: [String]

    /// Callee names that are known non-throwing, registered by earlier passes
    /// (e.g. LambdaClosureConversionPass).  ABILoweringPass consults this set
    /// instead of relying solely on string-prefix conventions.
    public private(set) var nonThrowingClosureCallees: Set<InternedString> = []

    public private(set) var features: KIRModuleFeatures = []
    public private(set) var usedCallees: Set<InternedString> = []
    private var featuresScanned = false

    public func ensureFeaturesScanned() {
        if !featuresScanned { scanFeatures() }
    }

    public init(files: [KIRFile], arena: KIRArena, executedLowerings: [String] = []) {
        self.files = files
        self.arena = arena
        self.executedLowerings = executedLowerings
    }

    public func scanFeatures() {
        var feats: KIRModuleFeatures = []
        var callees: Set<InternedString> = []
        for decl in arena.declarations {
            guard case let .function(function) = decl else { continue }
            if function.isTailrec { feats.insert(.hasTailrecFunction) }
            if function.isInline { feats.insert(.hasInlineFunction) }
            if function.isSuspend { feats.insert(.hasSuspendFunction) }
            if let last = function.body.last {
                switch last {
                case .returnUnit, .returnValue: break
                default: feats.insert(.hasNonTerminatedFunction)
                }
            } else if !function.body.isEmpty || function.params.isEmpty {
                feats.insert(.hasNonTerminatedFunction)
            }
            for instruction in function.body {
                switch instruction {
                case .beginBlock, .endBlock:
                    feats.insert(.hasBeginEndBlock)
                case .binary:
                    feats.insert(.hasBinaryOp)
                case .unary:
                    feats.insert(.hasUnaryOp)
                case .nullAssert:
                    feats.insert(.hasNullAssert)
                case let .call(_, callee, _, _, _, _, _, _):
                    callees.insert(callee)
                case let .virtualCall(_, callee, _, _, _, _, _, _):
                    callees.insert(callee)
                default:
                    break
                }
            }
        }
        features = feats
        usedCallees = callees
        featuresScanned = true
    }

    public func registerNonThrowingClosureCallee(_ name: InternedString) {
        nonThrowingClosureCallees.insert(name)
    }

    public var functionCount: Int {
        arena.declarations.reduce(0) { partial, decl in
            if case .function = decl {
                return partial + 1
            }
            return partial
        }
    }

    public var symbolCount: Int {
        var seen: Set<SymbolID> = []
        for decl in arena.declarations {
            switch decl {
            case let .function(fn):
                seen.insert(fn.symbol)
            case let .global(global):
                seen.insert(global.symbol)
            case let .nominalType(nominal):
                seen.insert(nominal.symbol)
            }
        }
        return seen.count
    }

    public func recordLowering(_ name: String) {
        executedLowerings.append(name)
    }

    public func dump(interner: StringInterner, symbols: SymbolTable?) -> String {
        var lines: [String] = []
        for (index, decl) in arena.declarations.enumerated() {
            switch decl {
            case let .function(function):
                let name = interner.resolve(function.name)
                lines.append("decl[\(index)] function #\(function.symbol.rawValue) \(name) params=\(function.params.count) suspend=\(function.isSuspend) inline=\(function.isInline)")
                for instruction in function.body {
                    lines.append("  \(instructionDescription(instruction, interner: interner, arena: arena, symbols: symbols))")
                }
            case .global:
                lines.append("decl[\(index)] global")
            case let .nominalType(nominal):
                if let symbol = symbols?.symbol(nominal.symbol) {
                    let name = interner.resolve(symbol.name)
                    lines.append("decl[\(index)] type \(name)")
                } else {
                    lines.append("decl[\(index)] type")
                }
            }
        }
        if !executedLowerings.isEmpty {
            lines.append("lowerings: \(executedLowerings.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func instructionDescription(
        _ instruction: KIRInstruction,
        interner: StringInterner,
        arena _: KIRArena,
        symbols: SymbolTable?
    ) -> String {
        switch instruction {
        case .nop:
            return "nop"
        case .beginBlock:
            return "beginBlock"
        case .endBlock:
            return "endBlock"
        case let .label(id):
            return "label L\(id)"
        case let .jump(target):
            return "jump L\(target)"
        case let .jumpIfEqual(lhs, rhs, target):
            return "jumpIfEqual r\(lhs.rawValue), r\(rhs.rawValue) -> L\(target)"
        case let .constValue(result, value):
            return "const r\(result.rawValue)=\(valueDescription(value, interner: interner))"
        case let .binary(op, lhs, rhs, result):
            return "binary \(op) r\(lhs.rawValue), r\(rhs.rawValue) -> r\(result.rawValue)"
        case let .unary(op, operand, result):
            return "unary \(op) r\(operand.rawValue) -> r\(result.rawValue)"
        case let .nullAssert(operand, result):
            return "nullAssert r\(operand.rawValue) -> r\(result.rawValue)"
        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
            let calleeName = interner.resolve(callee)
            let args = arguments.map { "r\($0.rawValue)" }.joined(separator: ", ")
            let symbolLabel: String = if let symbol, let sym = symbols?.symbol(symbol) {
                interner.resolve(sym.name)
            } else {
                "_"
            }
            let ret = result.map { "r\($0.rawValue)" } ?? "_"
            let thrownRet = thrownResult.map { "r\($0.rawValue)" } ?? "_"
            let superTag = isSuperCall ? " super=1" : ""
            let qualifiedSuperTag = qualifiedSuperType.map { " qualifiedSuper=\($0.rawValue)" } ?? ""
            return "call \(calleeName) symbol=\(symbolLabel) args=[\(args)] ret=\(ret) thrown=\(canThrow) thrownResult=\(thrownRet)\(superTag)\(qualifiedSuperTag)"
        case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
            let calleeName = interner.resolve(callee)
            let args = arguments.map { "r\($0.rawValue)" }.joined(separator: ", ")
            let symbolLabel: String = if let symbol, let sym = symbols?.symbol(symbol) {
                interner.resolve(sym.name)
            } else {
                "_"
            }
            let ret = result.map { "r\($0.rawValue)" } ?? "_"
            let thrownRet = thrownResult.map { "r\($0.rawValue)" } ?? "_"
            let dispatchLabel = switch dispatch {
            case let .vtable(slot):
                "vtable[\(slot)]"
            case let .itable(interfaceSlot, methodSlot):
                "itable[\(interfaceSlot):\(methodSlot)]"
            case let .itableDynamic(interfaceTypeID, methodSlot):
                "itableDynamic[\(interfaceTypeID):\(methodSlot)]"
            }
            return "virtualCall \(calleeName) symbol=\(symbolLabel) receiver=r\(receiver.rawValue) args=[\(args)] ret=\(ret) thrown=\(canThrow) thrownResult=\(thrownRet) dispatch=\(dispatchLabel)"
        case let .jumpIfNotNull(value, target):
            return "jumpIfNotNull r\(value.rawValue) -> L\(target)"
        case let .copy(from, to):
            return "copy r\(from.rawValue) -> r\(to.rawValue)"
        case let .storeGlobal(value, symbol):
            return "storeGlobal r\(value.rawValue) -> s\(symbol.rawValue)"
        case let .loadGlobal(result, symbol):
            return "loadGlobal s\(symbol.rawValue) -> r\(result.rawValue)"
        case let .rethrow(value):
            return "rethrow r\(value.rawValue)"
        case let .returnIfEqual(lhs, rhs):
            return "returnIfEqual r\(lhs.rawValue), r\(rhs.rawValue)"
        case .returnUnit:
            return "returnUnit"
        case let .returnValue(value):
            return "return r\(value.rawValue)"
        case let .nonLocalReturn(value):
            if let value {
                return "nonLocalReturn r\(value.rawValue)"
            } else {
                return "nonLocalReturnUnit"
            }
        case .beginFinallyGuard:
            return "beginFinallyGuard"
        case .endFinallyGuard:
            return "endFinallyGuard"
        }
    }

    private func valueDescription(_ value: KIRExprKind, interner: StringInterner) -> String {
        switch value {
        case let .stringLiteral(interned):
            return "stringLiteral(\"\(interner.resolve(interned))\")"
        case let .externSymbolAddress(interned):
            return "externSymbolAddress(\"\(interner.resolve(interned))\")"
        default:
            return "\(value)"
        }
    }
}

final class KIRContext {
    let diagnostics: DiagnosticEngine
    let options: CompilerOptions
    let interner: StringInterner
    let sema: SemaModule?

    init(
        diagnostics: DiagnosticEngine,
        options: CompilerOptions,
        interner: StringInterner,
        sema: SemaModule? = nil
    ) {
        self.diagnostics = diagnostics
        self.options = options
        self.interner = interner
        self.sema = sema
    }
}

protocol KIRPass {
    static var name: String { get }
    func run(module: KIRModule, ctx: KIRContext) throws
}
