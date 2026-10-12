import Foundation

/// Runtime reflection metadata record stored in the global registry.
/// Populated from the binary metadata blob emitted by `RuntimeReflectionMetadataEmitter`.
/// Each entry corresponds to a type or declaration that can be queried via `KClass` at runtime.
struct RuntimeKClassMetadataEntry {
    /// JVM binary name used only when rendering KClass handles.
    var displayName: String? = nil
    let qualifiedName: String
    let simpleName: String
    /// Fully-qualified display names of every direct supertype (class first,
    /// then interfaces in declaration order), e.g. "kotlin.Comparable<kotlin.Int>".
    /// The compiler joins them with '|' in `supertypeNameRaw`; the runtime
    /// splits them back into `KType` elements for `KClass.supertypes`.
    let supertypeDisplayNames: [String]
    let isDataClass: Bool
    let isSealedClass: Bool
    let isValueClass: Bool
    let isInterface: Bool
    let isObject: Bool
    let isEnumClass: Bool
    let isAnnotationClass: Bool
    let isAbstract: Bool
    let fieldCount: Int
    let memberCount: Int
    let constructorCount: Int
    // STDLIB-REFLECT-060: additional KClass basic reflection fields
    let isFinal: Bool
    let isOpen: Bool
    let visibility: String
    let typeParameterCount: Int
    // STDLIB-REFLECT-067: additional type-kind introspection flags
    var isInner: Bool = false
    var isCompanion: Bool = false
    var isFunInterface: Bool = false
    /// Runtime annotations attached to this type (STDLIB-REFLECT-065).
    var annotations: [RuntimeAnnotationRecord] = []
}

/// Runtime representation of an annotation attached to a declaration (STDLIB-REFLECT-065).
struct RuntimeAnnotationRecord {
    /// Fully-qualified name of the annotation class (e.g. "MyLabel").
    let annotationFQName: String
    /// Argument values serialized as strings (e.g. ["hello"]).
    let arguments: [String]
}

/// Global registry mapping type tokens to runtime metadata entries.
/// Populated during module initialization via `__kk_kclass_register_metadata`.
final class RuntimeKClassMetadataRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: RuntimeKClassMetadataEntry] = [:]

    func register(typeToken: Int, entry: RuntimeKClassMetadataEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries[typeToken] = entry
    }

    func lookup(typeToken: Int) -> RuntimeKClassMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[typeToken]
    }

    func setDisplayName(typeToken: Int, displayName: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[typeToken]?.displayName = displayName
    }

    func appendAnnotations(typeToken: Int, annotations: [RuntimeAnnotationRecord]) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[typeToken] {
            entry.annotations.append(contentsOf: annotations)
            entries[typeToken] = entry
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

let runtimeKClassMetadataRegistry = RuntimeKClassMetadataRegistry()

/// Global registry mapping a `KClass` raw handle to constructor reflection handles.
final class RuntimeKConstructorRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var constructorsByClassRaw: [Int: [Int]] = [:]

    func register(classRaw: Int, constructorRaw: Int) {
        guard classRaw != 0, classRaw != runtimeNullSentinelInt,
              constructorRaw != 0, constructorRaw != runtimeNullSentinelInt
        else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        constructorsByClassRaw[classRaw, default: []].append(constructorRaw)
    }

    func constructors(for classRaw: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return constructorsByClassRaw[classRaw] ?? []
    }

    func primaryConstructor(for classRaw: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let constructors = constructorsByClassRaw[classRaw] ?? []
        for constructorRaw in constructors {
            guard let ptr = UnsafeMutableRawPointer(bitPattern: constructorRaw),
                  let box = tryCast(ptr, to: RuntimeKConstructorBox.self),
                  box.isPrimary
            else {
                continue
            }
            return constructorRaw
        }
        return constructors.first
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        constructorsByClassRaw.removeAll()
    }
}

let runtimeKConstructorRegistry = RuntimeKConstructorRegistry()

/// Global registry mapping a `KClass` raw handle to its member callable handles.
/// Members are registered during module initialization via `__kk_kclass_register_member`.
/// Each entry is a KFunction or KPropertyStub raw handle (STDLIB-REFLECT-ABI-002).
final class RuntimeKMemberRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var membersByClassRaw: [Int: [Int]] = [:]

    func register(classRaw: Int, memberRaw: Int) {
        guard classRaw != 0, classRaw != runtimeNullSentinelInt,
              isCallableMemberHandle(memberRaw)
        else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        membersByClassRaw[classRaw, default: []].append(memberRaw)
    }

    func members(for classRaw: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return membersByClassRaw[classRaw] ?? []
    }

    func functions(for classRaw: Int) -> [Int] {
        members(for: classRaw, matching: RuntimeKFunctionBox.self)
    }

    func properties(for classRaw: Int) -> [Int] {
        members(for: classRaw, matching: RuntimeKPropertyStub.self)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        membersByClassRaw.removeAll()
    }

    private func members<T: AnyObject>(for classRaw: Int, matching type: T.Type) -> [Int] {
        members(for: classRaw).filter { isRuntimeObject($0, of: type) }
    }

    private func isCallableMemberHandle(_ raw: Int) -> Bool {
        isRuntimeObject(raw, of: RuntimeKFunctionBox.self)
            || isRuntimeObject(raw, of: RuntimeKPropertyStub.self)
    }

    private func isRuntimeObject<T: AnyObject>(_ raw: Int, of type: T.Type) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isObjectPointer else {
            return false
        }
        return tryCast(ptr, to: type) != nil
    }
}

let runtimeKMemberRegistry = RuntimeKMemberRegistry()

/// Global registry mapping a class's type token to its companion object's
/// type token and name-hint string raw handle, populated by
/// `__kk_kclass_register_companion` (KUU-1357).
final class RuntimeKCompanionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: (token: Int, nameRaw: Int)] = [:]

    func register(typeToken: Int, companionToken: Int, companionNameRaw: Int) {
        guard companionToken != 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        entries[typeToken] = (companionToken, companionNameRaw)
    }

    func companion(for typeToken: Int) -> (token: Int, nameRaw: Int)? {
        lock.lock()
        defer { lock.unlock() }
        return entries[typeToken]
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

let runtimeKCompanionRegistry = RuntimeKCompanionRegistry()

/// Global registry mapping a class's type token to its nested classes'
/// (typeToken, nameRaw) pairs, populated by `__kk_kclass_register_nested_class`
/// (KUU-1357 / MIGRATION-REFLECT-002).
final class RuntimeKNestedClassRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: [(token: Int, nameRaw: Int)]] = [:]

    func register(typeToken: Int, nestedToken: Int, nestedNameRaw: Int) {
        guard nestedToken != 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        entries[typeToken, default: []].append((nestedToken, nestedNameRaw))
    }

    func nestedClasses(for typeToken: Int) -> [(token: Int, nameRaw: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return entries[typeToken] ?? []
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

let runtimeKNestedClassRegistry = RuntimeKNestedClassRegistry()

/// Runtime box for `KClass<T>` metadata references produced by `T::class`.
/// Stores the type token and an optional name-hint pointer so that
/// `.simpleName` / `.qualifiedName` can be resolved at runtime.
/// When metadata has been registered via `__kk_kclass_register_metadata`,
/// additional properties (isData, isSealed, qualifiedName, etc.) are
/// available through the global metadata registry.
final class RuntimeKClassBox {
    let typeToken: Int
    let nameHint: Int

    init(typeToken: Int, nameHint: Int) {
        self.typeToken = typeToken
        self.nameHint = nameHint
    }

    /// Looks up the associated metadata entry from the global registry.
    var metadata: RuntimeKClassMetadataEntry? {
        runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    }
}

// MARK: - kotlin.reflect.KType (REFL-005)

/// Runtime box for `kotlin.reflect.KType`.
/// Represents a Kotlin type at runtime, as returned by `typeOf<T>()`.
final class RuntimeKTypeBox {
    /// The classifier — typically a `KClass` raw handle.
    let classifierRaw: Int
    /// Type arguments as `RuntimeKTypeProjectionBox` raw handles.
    let argumentRaws: [Int]
    /// Whether the type is marked nullable (`T?`).
    let isMarkedNullable: Bool
    /// Optional compact type descriptor used by callable reflection metadata.
    let typeNameRaw: Int

    init(
        classifierRaw: Int,
        argumentRaws: [Int],
        isMarkedNullable: Bool,
        typeNameRaw: Int = 0
    ) {
        self.classifierRaw = classifierRaw
        self.argumentRaws = argumentRaws
        self.isMarkedNullable = isMarkedNullable
        self.typeNameRaw = typeNameRaw
    }
}

/// Runtime representation of `kotlin.reflect.KVariance`.
/// Matches the Kotlin enum ordinals: IN=0, OUT=1, INVARIANT=2.
enum RuntimeKVariance: Int {
    case `in` = 0
    case out = 1
    case invariant = 2
}

/// Runtime box for `kotlin.reflect.KTypeProjection`.
/// Represents a type argument with optional variance.
final class RuntimeKTypeProjectionBox {
    /// The projected type as a `RuntimeKTypeBox` raw handle, or 0 for star projection.
    let typeRaw: Int
    /// The variance (nil for star projection).
    let variance: RuntimeKVariance?

    init(typeRaw: Int, variance: RuntimeKVariance?) {
        self.typeRaw = typeRaw
        self.variance = variance
    }
}

/// Packed flags carried on the `__kk_kparameter_create*` `flags` argument.
/// bit0 = isOptional, bit1 = isVararg (KUU-1364).
enum RuntimeKParameterFlags {
    static let isOptional: Int = 1 << 0
    static let isVararg: Int = 1 << 1
}

/// Runtime box for `kotlin.reflect.KParameter`.
/// Represents a single parameter of a KFunction or KConstructor.
final class RuntimeKParameterBox {
    var typeToken: Int?
    var callableOwner = 0
    var boundArguments: [Int] = []
    /// Parameter index (0-based).
    let index: Int
    /// Parameter name as a KKString raw handle (0 if unnamed).
    let nameRaw: Int
    /// Parameter type as a KKString raw handle describing the type name.
    let typeRaw: Int
    /// Whether this parameter is optional (has a default value).
    let isOptional: Bool
    /// Whether this parameter is declared `vararg`.
    let isVararg: Bool
    /// Parameter kind in the runtime's own ordering: 0 = INSTANCE,
    /// 1 = EXTENSION_RECEIVER, 2 = VALUE. The Kotlin 2.3.10
    /// `KParameter.Kind` declaration inserts CONTEXT at ordinal 1;
    /// `__kk_kparameter_get_kind` translates to the Kotlin declaration
    /// ordinals at the ABI boundary.
    let kind: Int

    init(index: Int, nameRaw: Int, typeRaw: Int, isOptional: Bool = false, kind: Int = 2, isVararg: Bool = false) {
        self.index = index
        self.nameRaw = nameRaw
        self.typeRaw = typeRaw
        self.isOptional = isOptional
        self.isVararg = isVararg
        self.kind = kind
    }
}

/// Packed modifier flags carried by KFunction reflection handles.
/// bit0=suspend, bit1=inline, bit2=operator, bit3=infix, bit4=external.
enum RuntimeKFunctionFlags {
    static let suspend: Int = 1 << 0
    static let `inline`: Int = 1 << 1
    static let `operator`: Int = 1 << 2
    static let `infix`: Int = 1 << 3
    static let `external`: Int = 1 << 4
}

/// Runtime box for `kotlin.reflect.KFunction<T>`.
/// Represents a constructor or function member with full reflection metadata (STDLIB-REFLECT-063).
final class RuntimeKFunctionBox {
    /// Interned KKString raw pointer for the function name.
    let nameRaw: Int
    /// Number of value parameters (not counting the dispatch receiver).
    let arity: Int
    /// Interned KKString raw pointer for the return type descriptor, or 0 if unknown.
    let returnTypeRaw: Int
    /// Packed modifier flags (see `RuntimeKFunctionFlags`).
    let flags: Int
    /// Raw function pointer used by `call()` dispatch.  Zero when not callable.
    let fnPtr: Int
    /// Closure environment for the callable reference (zero for top-level functions).
    let closureRaw: Int
    /// KParameter raw handles for all parameters (including receiver if any).
    let parameterRaws: [Int]
    /// Function type string as a KKString raw handle (e.g. "(Int, Int) -> Int").
    let typeStringRaw: Int

    /// Whether this function is declared `suspend`.
    var isSuspend: Bool { (flags & RuntimeKFunctionFlags.suspend) != 0 }

    init(
        nameRaw: Int,
        arity: Int,
        returnTypeRaw: Int = 0,
        flags: Int = 0,
        fnPtr: Int = 0,
        closureRaw: Int = 0,
        parameterRaws: [Int] = [],
        typeStringRaw: Int = 0
    ) {
        self.nameRaw = nameRaw
        self.arity = arity
        self.returnTypeRaw = returnTypeRaw
        self.flags = flags
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.parameterRaws = parameterRaws
        self.typeStringRaw = typeStringRaw
    }
}

// MARK: - kotlin.reflect.KConstructor (STDLIB-REFLECT-064)

/// Runtime box for `kotlin.reflect.KFunction<T>` representing a constructor.
/// Extends the basic KFunction box with constructor-specific metadata:
/// isPrimary, visibility, and the declaring class reference.
final class RuntimeKConstructorBox {
    let nameRaw: Int
    let arity: Int
    let returnTypeRaw: Int
    /// C function pointer for the underlying constructor implementation (0 if unavailable).
    let fnPtr: Int
    /// Whether this is the primary constructor of the class.
    let isPrimary: Bool
    /// Visibility as a KKString raw handle (e.g. "PUBLIC", "PRIVATE", "PROTECTED", "INTERNAL").
    let visibilityRaw: Int
    /// The declaring KClass raw handle (0 if unknown).
    let declaringClassRaw: Int
    /// Parameter names as KKString raw handles.
    let parameterNameRaws: [Int]

    init(
        nameRaw: Int,
        arity: Int,
        returnTypeRaw: Int = 0,
        fnPtr: Int = 0,
        isPrimary: Bool = false,
        visibilityRaw: Int = 0,
        declaringClassRaw: Int = 0,
        parameterNameRaws: [Int] = []
    ) {
        self.nameRaw = nameRaw
        self.arity = arity
        self.returnTypeRaw = returnTypeRaw
        self.fnPtr = fnPtr
        self.isPrimary = isPrimary
        self.visibilityRaw = visibilityRaw
        self.declaringClassRaw = declaringClassRaw
        self.parameterNameRaws = parameterNameRaws
    }
}

// MARK: - Annotation Reflection (STDLIB-REFLECT-065)

/// Runtime box for a Kotlin annotation instance.
/// Represents a single annotation applied to a declaration, with its class
/// name and argument values accessible at runtime.
final class RuntimeAnnotationBox {
    /// Fully-qualified name of the annotation class.
    let annotationFQName: String
    /// Argument values serialized as strings.
    let arguments: [String]
    /// Raw KClass handle for the annotation class (0 if not available).
    let annotationClassRaw: Int

    init(annotationFQName: String, arguments: [String], annotationClassRaw: Int = 0) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.annotationClassRaw = annotationClassRaw
    }
}
