public struct CallBinding {
    public let chosenCallee: SymbolID
    public let substitutedTypeArguments: [TypeID]
    public let parameterMapping: [Int: Int]
    /// Maps source argument indices to explicitly supplied context-parameter indices.
    public let contextParameterArgumentMapping: [Int: Int]
    /// The interface default source in an inherited class use-site scope.
    public let defaultArgumentOwner: SymbolID?
    /// The selected lexical dispatch receiver for a member-extension call.
    /// Most call sites track this separately by expression; synthetic calls
    /// such as for-in convention calls carry it with the binding instead.
    public let dispatchReceiverSymbol: SymbolID?
    /// Receiver values selected for the callee's context parameters, in declaration order.
    /// A nil entry falls back to the lowering context's context and implicit receiver lookup.
    public let contextParameterReceiverSymbols: [SymbolID?]
    /// Whether lowering must wrap this reference to adapt its function shape,
    /// including its arity, receiver, or return type, to the selected type.
    public let isCallableReferenceAdapter: Bool
    /// Context parameters captured when a context-requiring callable reference
    /// is adapted to a function type without context receivers.
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
        self.boundContextParameterTypes = boundContextParameterTypes
    }
}

struct DestructuringPropertyBinding {
    let propertySymbol: SymbolID
    let type: TypeID
    let getterCall: CallBinding?
}

/// The value read before invoking an object's operator member through a property.
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
    /// The callable value used by an unqualified `invoke(...)` on an implicit
    /// function-typed receiver. The source AST still has `invoke` as its callee,
    /// so KIR needs this receiver expression to lower the function value.
    public let implicitInvokeReceiverExpr: ExprID?
    public let contextArgumentCount: Int
    public let receiverArgumentOffset: Int

    public init(
        target: CallableTarget?,
        functionType: TypeID,
        parameterMapping: [Int: Int],
        extensionCallableExpr: ExprID? = nil,
        implicitInvokeReceiverExpr: ExprID? = nil,
        contextArgumentCount: Int = 0,
        receiverArgumentOffset: Int = 0
    ) {
        self.target = target
        self.functionType = functionType
        self.parameterMapping = parameterMapping
        self.extensionCallableExpr = extensionCallableExpr
        self.implicitInvokeReceiverExpr = implicitInvokeReceiverExpr
        self.contextArgumentCount = contextArgumentCount
        self.receiverArgumentOffset = receiverArgumentOffset
    }
}

/// The custom `set()` operator call resolved for the write-back half of an
/// `a[i] op= v` / `a[i]++`/`a[i]--` compound assignment on a receiver whose
/// indexing is backed by a user-defined (or source-backed member, e.g.
/// `MutableList`) `operator fun get`/`set` pair rather than a genuine
/// built-in array. The matching `get()` call is already recorded in
/// `callBindings[exprID]` for the same expression by the read half's
/// resolution; this side-channel carries the write-back `set()` binding
/// plus the get's substituted element type (needed to pick the right
/// `kk_op_*` runtime variant), since the compound-assign expression itself
/// is bound to `Unit`, not the element type.
public struct IndexedCompoundAssignOperatorBinding {
    public let setCall: CallBinding
    public let elementType: TypeID

    public init(setCall: CallBinding, elementType: TypeID) {
        self.setCall = setCall
        self.elementType = elementType
    }
}

/// The operator applied to the *element* of `a[i] op= v` / `a[i]++` when the
/// element type defines it (`plusAssign`, `plus`, `inc`, ...), as opposed to
/// the builtin numeric/String arithmetic. Bound separately from the `get()`
/// call binding, which already occupies `callBindings[expr]`.
public struct IndexedCompoundAssignElementOperatorBinding {
    public enum Kind {
        /// `plusAssign`-style operator returning Unit: mutates the element
        /// in place, so no `set()` write-back follows.
        case inPlace
        /// `plus`-style binary operator: `a[i] = a[i].plus(v)`.
        case binary
        /// `inc()` / `dec()` for `a[i]++` / `a[i]--`; takes no argument.
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
    /// Closeable.use { } (STDLIB-520): like `let`, but wraps in try-finally calling close().
    case scopeUse
    /// T.usePinned { } (STDLIB-CINTEROP-FN-042): like `use`, but pins the receiver via
    /// pin() first, passes the resulting Pinned<T> (not the receiver) to the lambda, and
    /// wraps in try-finally calling unpin().
    case scopeUsePinned
    /// CValue<T>.useContents { } (STDLIB-CINTEROP-FN-041): temporarily exposes
    /// the contained native value as the lambda receiver.
    case scopeUseContents
    /// kotlinx.cinterop.memScoped { } (KUU-1375): creates a MemScope arena,
    /// invokes the block with it as the implicit receiver, and runs
    /// kk_arena_clear in a finally path (deferred blocks + frees).
    case scopeMemScoped
}

public enum StdlibSpecialCallKind: Equatable, Codable {
    /// Compiler-only contract DSL; its lambda is recorded by Sema and must
    /// not be emitted into KIR.
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
    case enumValues
    case enumValueOf
    case enumEntries
}

/// Identifies whether a callable reference (`::foo`) refers to a function
/// or a property, so that KIR lowering can emit the correct KFunction /
/// KProperty type identity metadata (REFL-003).
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
