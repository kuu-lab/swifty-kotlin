/// Typed, stack-neutral JVM IR. Each value has a fixed local slot; branches
/// have empty operand stacks, allowing deterministic verifier frames.
public enum JVMValueType: Hashable, Sendable {
    case int, long, float, double, boolean, byte, short, char, uint, ulong, ubyte, ushort, string, unit
    case unsignedArray(PrimitiveType, nullable: Bool)
    case reference(String, nullable: Bool, platform: Bool = false)

    public var descriptor: String {
        switch self {
        case .int, .uint: "I"
        case .byte, .ubyte: "B"
        case .short, .ushort: "S"
        case .char: "C"
        case let .unsignedArray(p, _): "[" + JVMValueType.primitive(p).descriptor
        case .long, .ulong: "J"
        case .float: "F"
        case .double: "D"
        case .boolean: "Z"
        case .string: "Ljava/lang/String;"
        case .unit: "V"
        case let .reference(name, _, _): name.hasPrefix("[") ? name : "L" + name + ";"
        }
    }
    public var width: Int { self == .unit ? 0 : (self == .long || self == .ulong || self == .double ? 2 : 1) }
    public var isNumeric: Bool { [.int, .long, .float, .double, .byte, .short, .char, .uint, .ulong, .ubyte, .ushort].contains(self) }
    /// The primitive carrier used for numeric operations, without changing the
    /// reference descriptor required by generic bounds and nullable values.
    var numericCarrier: JVMValueType? {
        if isNumeric { return self }
        return switch referenceName {
        case "java/lang/Byte": .byte
        case "java/lang/Short": .short
        case "java/lang/Character": .char
        case "java/lang/Integer": .int
        case "java/lang/Long": .long
        case "java/lang/Float": .float
        case "java/lang/Double": .double
        case "kotlin/UByte": .ubyte
        case "kotlin/UShort": .ushort
        case "kotlin/UInt": .uint
        case "kotlin/ULong": .ulong
        default: nil
        }
    }
    public var referenceName: String? {
        if self == .string { return "java/lang/String" }
        if case .unsignedArray = self { return descriptor }
        if case let .reference(name, _, _) = self { return name }
        return nil
    }
    public var isPlatform: Bool {
        if case let .reference(_, _, platform) = self { return platform }
        return false
    }
    public var isNullable: Bool {
        if case let .reference(_, nullable, _) = self { return nullable }
        if case let .unsignedArray(_, nullable) = self { return nullable }
        return false
    }
}

extension JVMValueType {
    public static func primitive(_ p: PrimitiveType) -> JVMValueType {
        switch p {
        case .int: .int
        case .long: .long
        case .float: .float
        case .double: .double
        case .boolean: .boolean
        case .byte: .byte
        case .short: .short
        case .char: .char
        case .uint: .uint
        case .ulong: .ulong
        case .ubyte: .ubyte
        case .ushort: .ushort
        }
    }
    public var unsignedName: String? {
        switch self {
        case .uint: "kotlin/UInt"
        case .ulong: "kotlin/ULong"
        case .ubyte: "kotlin/UByte"
        case .ushort: "kotlin/UShort"
        case let .unsignedArray(p, _): "kotlin/" + p.kotlinName + "Array"
        case let .reference(name, _, _) where ["kotlin/UInt", "kotlin/ULong", "kotlin/UByte", "kotlin/UShort", "kotlin/UIntArray", "kotlin/ULongArray", "kotlin/UByteArray", "kotlin/UShortArray"].contains(name): name
        default: nil
        }
    }
    public var stackType: JVMValueType {
        if self == .ulong { return .long }
        if [.byte, .short, .char, .uint, .ubyte, .ushort].contains(self) { return .int }
        return self
    }
    public var boxName: String? {
        switch self {
        case .uint, .ulong, .ubyte, .ushort, .unsignedArray: return unsignedName
        default: break
        }
        switch self {
        case .int: return "java/lang/Integer"
        case .long: return "java/lang/Long"
        case .float: return "java/lang/Float"
        case .double: return "java/lang/Double"
        case .boolean: return "java/lang/Boolean"
        case .byte: return "java/lang/Byte"
        case .short: return "java/lang/Short"
        case .char: return "java/lang/Character"
        default: return nil
        }
    }
    public var stringParameter: JVMValueType {
        if unsignedName != nil { return .reference("java/lang/Object", nullable: true) }
        return [.byte, .short].contains(self) ? .int : (referenceName != nil && self != .string ? .reference("java/lang/Object", nullable: true) : self)
    }
}

public struct JVMValue {
    public let slot: Int
    public let type: JVMValueType
}

public enum JVMConstant {
    case int(Int32), long(Int64), float(Float), double(Double), boolean(Bool), string(String)
    case null
}

public struct JVMFunctionReference {
    public let name: String
    public let parameters: [JVMValueType]
    public let result: JVMValueType
    public var owner: String? = nil
    public var ownerIsInterface = false
    public var isSuspend = false
    public var suspendDefaultMasks = 0
    public var descriptor: String { "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor }
}

public enum JVMInstruction {
    case constant(JVMConstant, JVMValue)
    case callableSignature(String, String, String, JVMValue)
    case classLiteral(String, JVMValue)
    case reifiedOperation(Int, String, JVMValue?, JVMValue)
    case copy(JVMValue, JVMValue)
    case binary(BinaryOp, JVMValue, JVMValue, JVMValue)
    case referenceCompare(BinaryOp, JVMValue, JVMValue, JVMValue)
    case unary(UnaryOp, JVMValue, JVMValue)
    case call(JVMFunctionReference, [JVMValue], JVMValue?)
    case allocate(String, JVMValue)
    case abandonAllocations([JVMValue])
    case foreignCall(JVMForeignMethod, receiver: JVMValue?, arguments: [JVMValue], result: JVMValue?)
    case getStatic(JVMField, JVMValue)
    case putStatic(JVMField, JVMValue)
    case getField(JVMField, JVMValue, JVMValue)
    case putField(JVMField, JVMValue, JVMValue)
    case newArray(JVMValueType, count: JVMValue, result: JVMValue)
    case arrayLength(JVMValue, JVMValue)
    case arrayGet(JVMValue, JVMValue, JVMValue)
    case arraySet(JVMValue, JVMValue, JVMValue)
    case instanceOf(JVMValue, String, JVMValue)
    case throwValue(JVMValue)
    case monitor(JVMValue, enter: Bool)
    case regionBoundary(Int)
    case inlineFinallyMarker(Int, start: Bool)
    case exceptionHandler(Int, JVMValue, preserving: [JVMValue])
    case print(JVMValue?, newline: Bool)
    case label(Int)
    case jump(Int)
    case jumpIfFalse(JVMValue, Int)
    case defaultArgument(JVMValue, Int32, Int)
    case returnValue(JVMValue?)
}

public struct JVMFunction {
    public var reference: JVMFunctionReference
    public var isPrivate: Bool
    public var locals: [JVMValue]
    public var parameterCount: Int
    public var instructions: [JVMInstruction]
    public var parameterNames: [String]
    public var isInternal: Bool
    public var owner: String? = nil
    public var access: UInt16? = nil
    public var isConstructor: Bool = false
    public var isValueConstructor = false
    public var isSecondaryConstructor: Bool = false
    public var isAbstract: Bool = false
    public var handlers: [JVMExceptionHandler] = []
    public var genericSignature: String? = nil
    public var typeParameters: [JVMTypeParameter] = []
    public var kotlinParameters: [JVMKotlinType] = []
    public var kotlinResult: JVMKotlinType? = nil
    /// The indexed Boolean value parameter is true after any normal return.
    public var normalReturnConditionParameter: Int? = nil
    public var kotlinReceiver: JVMKotlinType? = nil
    public var isSynthetic: Bool = false
    public var isMetadataHidden: Bool = false
    public var isSuspend = false
    public var suspendValueResult: JVMSuspendValueResult? = nil
    public var forwardedSuspendValueResult: JVMSuspendValueResult? = nil
    public var checksParameters = true
    public var isInfix = false
    public var isOperator = false
    public var parameterDefaultFlags: [Bool] = []
    public var kotlinParameterOffset = 0
    public var isInline = false
    public var callsInPlaceEffects: [Int: InvocationKind] = [:]
    public var inlineContinuation: JVMValue? = nil
    public var inlineSuspendValueResults: [String: JVMSuspendValueResult] = [:]
    public var parameterInlineFlags: [Int] = []
    public var sourceName: String? = nil
    public var jvmName: String? = nil
    public var metadataDescriptor: String? = nil
    public var metadataParameterOffset = 0
    public var annotations: [JVMAnnotation] = []
    public var parameterAnnotations: [[JVMAnnotation]] = []
    public var annotationDefault: JVMAnnotationValue? = nil
    public var isDeprecated = false
    public var isHiddenByDeprecation = false
    public var parameterVarargTypes: [JVMKotlinType?] = []
}

public struct JVMProgram {
    public init(internalClassName: String, sourceFileName: String, functions: [JVMFunction], hasMain: Bool, moduleName: String, classes: [JVMClass] = []) {
        self.internalClassName = internalClassName; self.sourceFileName = sourceFileName
        self.functions = functions; self.hasMain = hasMain; self.moduleName = moduleName; self.classes = classes
    }
    public let internalClassName: String
    public let sourceFileName: String
    public var functions: [JVMFunction]
    public let hasMain: Bool
    public let moduleName: String
    public var classes: [JVMClass] = []
    public var stdlibRequirements: [JVMStdlibRequirement] = []
    public var properties: [JVMProperty] = []
    public var extraFields: [JVMField] = []
    public var annotations: [JVMAnnotation] = []
    public var typeAliases: [JVMTypeAlias] = []
}

public struct JVMForeignMethod {
    public let owner: String
    public let name: String
    public let descriptor: String
    public let parameters: [JVMValueType]
    public let result: JVMValueType
    public let isStatic: Bool
    public let isInterface: Bool
    public let isAbstract: Bool
    public var isFinal: Bool = false
    public var isSpecial: Bool = false
    public var isSuspend = false
    public var isConstructor: Bool { name == "<init>" }
}

public struct JVMField {
    public let owner: String
    public let name: String
    public let type: JVMValueType
    public let access: UInt16
    public var annotations: [JVMAnnotation] = []
    public var isDeprecated = false
    public var constantValue: JVMConstant? = nil
}

public struct JVMProperty {
    public let name: String
    public let type: JVMValueType
    public var getter: JVMForeignMethod
    public var setter: JVMForeignMethod?
    public var field: JVMField?
    public let modifiers: Modifiers
    public var kotlinType: JVMKotlinType? = nil
    public var kotlinReceiver: JVMKotlinType? = nil
    public var genericSignature: String? = nil
    public var receiverGenericSignature: String? = nil
    public var delegateField: JVMField? = nil
    public var delegateSymbol: SymbolID? = nil
    public var annotationsMethod: JVMForeignMethod? = nil
    public var customGetter: Bool = false
    public var customSetter: Bool = false
}

public struct JVMClass {
    public let name: String
    public let superclass: String
    public let interfaces: [String]
    public let access: UInt16
    public var functions: [JVMFunction]
    public var properties: [JVMProperty]
    public var extraFields: [JVMField] = []
    public var isFileFacade = false
    public var sourceFileName: String? = nil
    public var emitMetadata = true
    public var isObject = false
    public var isCompanion = false
    public var isData = false
    public var isInner = false
    public var isEnum = false
    public var isSealed = false
    public var outerName: String? = nil
    public var innerName: String? = nil
    public var nestedNames: [String] = []
    public var companionName: String? = nil
    public var sealedSubclasses: [String] = []
    public var enumEntries: [String] = []
    public var isValue = false
    public var isAnnotation = false
    public var annotationConstructor: JVMFunction? = nil
    public var underlyingProperty: String? = nil
    public var annotations: [JVMAnnotation] = []
    public var typeAliases: [JVMTypeAlias] = []
    public var isFunInterface = false
    public var genericSignature: String? = nil
    public var typeParameters: [JVMTypeParameter] = []
    public var kotlinSupertypes: [JVMKotlinType] = []
    public var modifiers: Modifiers = []
    public var isInterface: Bool { access & 0x0200 != 0 }
}

public struct JVMExceptionHandler {
    public let start: Int
    public let end: Int
    public let handler: Int
    public let type: String?
}

/// Source types retained independently of JVM erasure for Kotlin consumers.
public indirect enum JVMKotlinType {
    case named(String, [JVMKotlinTypeArgument], nullable: Bool)
    case parameter(Int, nullable: Bool)
    case flexible(JVMKotlinType, JVMKotlinType)
    case function([JVMKotlinType], JVMKotlinType, receiver: JVMKotlinType?, nullable: Bool, isSuspend: Bool = false)
}
public struct JVMKotlinTypeArgument {
    public let type: JVMKotlinType?
    public let variance: Int
    public init(type: JVMKotlinType?, variance: Int) { self.type = type; self.variance = variance }
}
public struct JVMTypeParameter {
    public let id: Int
    public let name: String
    public let variance: Int
    public let bounds: [JVMKotlinType]
    public let signature: String
    public var isReified = false
}

public struct JVMAnnotation {
    public let descriptor: String
    public var values: [(String, JVMAnnotationValue)]
    public var visible: Bool = true
    public init(descriptor: String, values: [(String, JVMAnnotationValue)] = [], visible: Bool = true) {
        self.descriptor = descriptor; self.values = values; self.visible = visible
    }
}
public indirect enum JVMAnnotationValue {
    case constant(JVMConstant)
    case integral(Int32, UInt8)
    case enumEntry(String, String)
    case classType(String)
    case array([JVMAnnotationValue])
    case annotation(JVMAnnotation)
}
public struct JVMTypeAlias {
    public let name: String
    public let modifiers: Modifiers
    public let typeParameters: [JVMTypeParameter]
    public let underlyingType: JVMKotlinType
}

/// Reference value classes return raw storage synchronously and boxed values on resume.
public struct JVMSuspendValueResult {
    public let boxed: JVMValueType
    public let underlying: JVMValueType
    public var adapterOwner: String? = nil
}

public struct JVMStdlibRequirement {
    public let owner: String
    public let name: String
    public let descriptor: String
    public let source: String
}
