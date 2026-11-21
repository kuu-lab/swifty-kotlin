public struct CallBinding {
    public let chosenCallee: SymbolID
    public let substitutedTypeArguments: [TypeID]
    public let parameterMapping: [Int: Int]
    public let contextParameterArgumentMapping: [Int: Int]
    public let defaultArgumentOwner: SymbolID?
    public let dispatchReceiverSymbol: SymbolID?
    /// Receiver values selected for the callee's context parameters, in declaration order.
    /// A nil entry falls back to the lowering context's context and implicit receiver lookup.
    public let contextParameterReceiverSymbols: [SymbolID?]
    public let isCallableReferenceAdapter: Bool
    /// Whether the adapted reference's bound signature differs from the
    /// callee's public callable signature (arity, scalar-packed varargs,
    /// bound context, or a coerced return/suspend type). On the JVM such
    /// references materialize as adapted function objects that do not
    /// implement KCallable, so lowering must not expose reflection metadata
    /// for them (KUU-3361). Thunks that only repackage the call ABI —
    /// erased or reified inputs — keep KCallable identity (KUU-3863).
    public let hidesKCallable: Bool
    public let boundContextParameterTypes: [TypeID]

    public init(
        chosenCallee: SymbolID,
        substitutedTypeArguments: [TypeID],
        parameterMapping: [Int: Int],
        contextParameterArgumentMapping: [Int: Int] = [:],
        defaultArgumentOwner: SymbolID? = nil,
        dispatchReceiverSymbol: SymbolID? = nil,
        contextParameterReceiverSymbols: [SymbolID?] = [],
        isCallableReferenceAdapter: Bool = false,
        hidesKCallable: Bool = false,
        boundContextParameterTypes: [TypeID] = []
    ) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
        self.contextParameterArgumentMapping = contextParameterArgumentMapping
        self.defaultArgumentOwner = defaultArgumentOwner
        self.dispatchReceiverSymbol = dispatchReceiverSymbol
        self.contextParameterReceiverSymbols = contextParameterReceiverSymbols
        self.isCallableReferenceAdapter = isCallableReferenceAdapter
        self.hidesKCallable = hidesKCallable
        self.boundContextParameterTypes = boundContextParameterTypes
    }
}

struct DestructuringPropertyBinding {
    let propertySymbol: SymbolID
    let type: TypeID
    let getterCall: CallBinding?
}

public struct InvokeOperatorPropertyBinding {
    public let property: SymbolID
    public let propertyType: TypeID
    public let resultType: TypeID

    public init(property: SymbolID, propertyType: TypeID, resultType: TypeID) {
        self.property = property
        self.propertyType = propertyType
        self.resultType = resultType
    }
}

public enum CallableTarget: Equatable {
    case symbol(SymbolID)
    case localValue(SymbolID)
}

public struct CallableValueCallBinding {
    public let target: CallableTarget?
    public let functionType: TypeID
    public let parameterMapping: [Int: Int]
    public let extensionCallableExpr: ExprID?
    public let implicitInvokeReceiverExpr: ExprID?
    public let contextArgumentCount: Int
    public let receiverArgumentOffset: Int
    public let contextReceiverSymbols: [SymbolID?]

    public init(
        target: CallableTarget?,
        functionType: TypeID,
        parameterMapping: [Int: Int],
        extensionCallableExpr: ExprID? = nil,
        implicitInvokeReceiverExpr: ExprID? = nil,
        contextArgumentCount: Int = 0,
        receiverArgumentOffset: Int = 0,
        contextReceiverSymbols: [SymbolID?] = []
    ) {
        self.target = target
        self.functionType = functionType
        self.parameterMapping = parameterMapping
        self.extensionCallableExpr = extensionCallableExpr
        self.implicitInvokeReceiverExpr = implicitInvokeReceiverExpr
        self.contextArgumentCount = contextArgumentCount
        self.receiverArgumentOffset = receiverArgumentOffset
        self.contextReceiverSymbols = contextReceiverSymbols
    }
}

public struct IndexedCompoundAssignOperatorBinding {
    public let setCall: CallBinding
    public let elementType: TypeID

    public init(setCall: CallBinding, elementType: TypeID) {
        self.setCall = setCall
        self.elementType = elementType
    }
}

public struct IndexedCompoundAssignElementOperatorBinding {
    public enum Kind {
        case inPlace
        case binary
        case incrementDecrement
    }

    public let call: CallBinding
    public let kind: Kind
    public let elementType: TypeID
    public let resultType: TypeID

    public init(call: CallBinding, kind: Kind, elementType: TypeID, resultType: TypeID) {
        self.call = call
        self.kind = kind
        self.elementType = elementType
        self.resultType = resultType
    }
}

public struct LoopIterationBinding {
    public let iteratorCall: CallBinding?
    public let hasNextCall: CallBinding
    public let nextCall: CallBinding
    public let iteratorType: TypeID
    public let elementType: TypeID

    public init(
        iteratorCall: CallBinding?,
        hasNextCall: CallBinding,
        nextCall: CallBinding,
        iteratorType: TypeID,
        elementType: TypeID
    ) {
        self.iteratorCall = iteratorCall
        self.hasNextCall = hasNextCall
        self.nextCall = nextCall
        self.iteratorType = iteratorType
        self.elementType = elementType
    }
}

public enum BuilderDSLKind: Equatable {
    case buildList
    case buildSet
    case buildMap
}

public enum ScopeFunctionKind: Equatable {
    case scopeContext
    case scopeUse
    case scopeUsePinned
    case scopeUseContents
    case scopeMemScoped
}

public enum StdlibSpecialCallKind: Equatable, Codable {
    case contract
    case typeOf
    case maxOfInt
    case minOfInt
    case maxOfLong
    case minOfLong
    case maxOfDouble
    case minOfDouble
    case maxOfFloat
    case minOfFloat
    case minOfByte
    case minOfShort
    case maxOfInt3
    case minOfInt3
    case maxOfLong3
    case minOfLong3
    case maxOfDouble3
    case minOfDouble3
    case maxOfFloat3
    case minOfFloat3
    case minOfByte3
    case minOfShort3
    case arrayConstructor
    case atomicIntArrayFactory
    case atomicLongArrayFactory
    case suspendCoroutineUninterceptedOrReturn
    case suspendLambdaLiteral
    case enumValues
    case enumValueOf
    case enumEntries
}

public enum CallableRefKind: Equatable {
    case functionRef
    case propertyRef
}

public struct CatchClauseBinding: Equatable {
    public let parameterSymbol: SymbolID
    public let parameterType: TypeID

    public init(parameterSymbol: SymbolID = .invalid, parameterType: TypeID) {
        self.parameterSymbol = parameterSymbol
        self.parameterType = parameterType
    }
}
