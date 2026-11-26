import Foundation

struct RuntimeKClassMetadataEntry {
    var displayName: String? = nil
    let qualifiedName: String
    let simpleName: String
    let supertypeDisplayNames: [String]
    let isDataClass: Bool
    let isSealedClass: Bool
    let isValueClass: Bool
    let isInterface: Bool
    let isObject: Bool
    let isEnumClass: Bool
    let isAbstract: Bool
    let fieldCount: Int
    let memberCount: Int
    let constructorCount: Int
    let isFinal: Bool
    let isOpen: Bool
    let visibility: String
    var typeParameterCount: Int = 0
    var typeParameters: [RuntimeKTypeParameterMetadata] = []
    var enclosingClassName: String? = nil
    var declaringClassName: String? = nil
    var enclosingMember: RuntimeKClassEnclosingMember? = nil
    var isInner: Bool = false
    var isCompanion: Bool = false
    var isFunInterface: Bool = false
    var isLocal: Bool = false
    var isAnonymous: Bool = false
    var annotations: [RuntimeAnnotationRecord] = []
}

struct RuntimeKTypeParameterMetadata: Equatable {
    let identity: Int
    let name: String
    let varianceOrdinal: Int
}

struct RuntimeKClassEnclosingMember: Equatable {
    enum Kind: Int {
        case method = 1
        case constructor = 2
    }

    let kind: Kind
    let name: String
    let signature: String
}

struct RuntimeAnnotationRecord {
    let annotationFQName: String
    let arguments: [String]
    let factory: Int

    init(annotationFQName: String, arguments: [String], factory: Int = 0) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.factory = factory
    }
}

func runtimeAppendAnnotationRecord(_ annotation: RuntimeAnnotationRecord, to records: inout [RuntimeAnnotationRecord]) {
    let sameValue: (RuntimeAnnotationRecord) -> Bool = {
        $0.annotationFQName == annotation.annotationFQName && $0.arguments == annotation.arguments
    }
    if annotation.factory == 0, records.contains(where: { $0.factory != 0 && sameValue($0) }) { return }
    if annotation.factory != 0, records.contains(where: {
        $0.factory == annotation.factory && $0.annotationFQName == annotation.annotationFQName
    }) { return }
    if annotation.factory != 0, let legacyIndex = records.firstIndex(where: { $0.factory == 0 && sameValue($0) }) {
        records.remove(at: legacyIndex)
    }
    records.append(annotation)
}

final class RuntimeKClassMetadataRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: RuntimeKClassMetadataEntry] = [:]
    private var typeTokensByQualifiedName: [String: Int] = [:]
    private var classCastNamesByTypeToken: [Int: String] = [:]
    private var javaInheritedAnnotationNames: Set<String> = []

    func register(typeToken: Int, entry: RuntimeKClassMetadataEntry) {
        lock.lock()
        defer { lock.unlock() }
        var registered = entry
        if registered.annotations.isEmpty {
            registered.annotations = entries[typeToken]?.annotations.filter { $0.factory != 0 } ?? []
        }
        if registered.typeParameters.isEmpty,
           let previous = entries[typeToken], !previous.typeParameters.isEmpty {
            registered.typeParameters = previous.typeParameters
            registered.typeParameterCount = previous.typeParameterCount
        }
        if registered.enclosingClassName == nil, let previous = entries[typeToken] {
            registered.enclosingClassName = previous.enclosingClassName
        }
        if registered.declaringClassName == nil, let previous = entries[typeToken] {
            registered.declaringClassName = previous.declaringClassName
        }
        if registered.enclosingMember == nil, let previous = entries[typeToken] {
            registered.enclosingMember = previous.enclosingMember
        }
        let previousQualifiedName = entries[typeToken]?.qualifiedName
        entries[typeToken] = registered
        if let previousQualifiedName,
           previousQualifiedName != registered.qualifiedName,
           typeTokensByQualifiedName[previousQualifiedName] == typeToken
        {
            typeTokensByQualifiedName.removeValue(forKey: previousQualifiedName)
        }
        if typeTokensByQualifiedName[registered.qualifiedName] == nil {
            typeTokensByQualifiedName[registered.qualifiedName] = typeToken
        }
    }

    func registerTypeParameter(
        typeToken: Int,
        index: Int,
        metadata: RuntimeKTypeParameterMetadata
    ) {
        guard index >= 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[typeToken] else { return }
        while entry.typeParameters.count <= index {
            let missingIndex = entry.typeParameters.count
            entry.typeParameters.append(RuntimeKTypeParameterMetadata(
                identity: 0,
                name: "T\(missingIndex)",
                varianceOrdinal: 0
            ))
        }
        entry.typeParameters[index] = metadata
        entry.typeParameterCount = max(entry.typeParameterCount, index + 1)
        entries[typeToken] = entry
    }

    func registerEnclosingMetadata(
        typeToken: Int,
        enclosingClassName: String?,
        declaringClassName: String?,
        enclosingMember: RuntimeKClassEnclosingMember?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[typeToken] else { return }
        entry.enclosingClassName = enclosingClassName
        entry.declaringClassName = declaringClassName
        entry.enclosingMember = enclosingMember
        entries[typeToken] = entry
    }

    func lookup(typeToken: Int) -> RuntimeKClassMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[typeToken]
    }

    func lookup(qualifiedName: String) -> RuntimeKClassMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let typeToken = typeTokensByQualifiedName[qualifiedName] else { return nil }
        return entries[typeToken]
    }

    func registerJavaInheritedAnnotation(name: String) {
        guard !name.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        javaInheritedAnnotationNames.insert(name)
    }

    func isJavaInheritedAnnotation(name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return javaInheritedAnnotationNames.contains(name)
    }

    func setDisplayName(typeToken: Int, displayName: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[typeToken]?.displayName = displayName
    }

    func setClassCastName(typeToken: Int, name: String) {
        let normalizedTypeToken = Int(
            truncatingIfNeeded: Int64(truncatingIfNeeded: typeToken)
                & ~RuntimeTypeTokenEncoding.nullableBit
        )
        lock.lock()
        defer { lock.unlock() }
        classCastNamesByTypeToken[normalizedTypeToken] = name
    }

    func classCastName(typeToken: Int) -> String? {
        let normalizedTypeToken = Int(
            truncatingIfNeeded: Int64(truncatingIfNeeded: typeToken)
                & ~RuntimeTypeTokenEncoding.nullableBit
        )
        lock.lock()
        defer { lock.unlock() }
        return classCastNamesByTypeToken[normalizedTypeToken]
    }

    func appendAnnotations(typeToken: Int, annotations: [RuntimeAnnotationRecord]) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[typeToken] {
            for annotation in annotations { runtimeAppendAnnotationRecord(annotation, to: &entry.annotations) }
            entries[typeToken] = entry
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        typeTokensByQualifiedName.removeAll()
        classCastNamesByTypeToken.removeAll()
        javaInheritedAnnotationNames.removeAll()
    }
}

let runtimeKClassMetadataRegistry = RuntimeKClassMetadataRegistry()

final class RuntimeKConstructorRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var constructorsByClassRaw: [Int: [Int]] = [:]
    private var initializedBuiltinArrays: Set<Int> = []

    func register(classRaw: Int, constructorRaw: Int) {
        guard classRaw != 0, classRaw != runtimeNullSentinelInt,
              constructorRaw != 0, constructorRaw != runtimeNullSentinelInt
        else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        guard !initializedBuiltinArrays.contains(classRaw) else { return }
        constructorsByClassRaw[classRaw, default: []].append(constructorRaw)
    }

    func builtinArrayInitialized(for classRaw: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return initializedBuiltinArrays.contains(classRaw)
    }

    func clearBuiltinArrayConstructors(for classRaw: Int) {
        lock.lock()
        defer { lock.unlock() }
        constructorsByClassRaw.removeValue(forKey: classRaw)
    }

    func markBuiltinArrayInitialized(for classRaw: Int) {
        lock.lock()
        defer { lock.unlock() }
        initializedBuiltinArrays.insert(classRaw)
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
        return nil
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        constructorsByClassRaw.removeAll()
        initializedBuiltinArrays.removeAll()
    }
}

let runtimeKConstructorRegistry = RuntimeKConstructorRegistry()

final class RuntimeKMemberRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var membersByClassRaw: [Int: [Int]] = [:]
    private var extensionMemberRaws: Set<Int> = []
    private var initializedBuiltinClasses: Set<Int> = []

    func builtinMembersInitialized(for classRaw: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return initializedBuiltinClasses.contains(classRaw)
    }

    func markBuiltinMembersInitialized(for classRaw: Int) {
        lock.lock()
        defer { lock.unlock() }
        initializedBuiltinClasses.insert(classRaw)
    }

    func register(classRaw: Int, memberRaw: Int, isMemberExtension: Bool = false) {
        guard classRaw != 0, classRaw != runtimeNullSentinelInt,
              isCallableMemberHandle(memberRaw)
        else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        membersByClassRaw[classRaw, default: []].append(memberRaw)
        if isMemberExtension {
            extensionMemberRaws.insert(memberRaw)
        }
    }

    func isMemberExtension(_ memberRaw: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return extensionMemberRaws.contains(memberRaw)
    }

    func members(for classRaw: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return membersByClassRaw[classRaw] ?? []
    }

    func remove(classRaw: Int, members: Set<Int>) {
        lock.lock()
        defer { lock.unlock() }
        membersByClassRaw[classRaw]?.removeAll { members.contains($0) }
        extensionMemberRaws.subtract(members)
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
        extensionMemberRaws.removeAll()
        initializedBuiltinClasses.removeAll()
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

final class RuntimeKNestedClassRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: [(token: Int, nameRaw: Int)]] = [:]

    func register(typeToken: Int, nestedToken: Int, nestedNameRaw: Int) {
        guard nestedToken != 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if !entries[typeToken, default: []].contains(where: { $0.token == nestedToken }) {
            entries[typeToken, default: []].append((nestedToken, nestedNameRaw))
        }
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

final class RuntimeKClassBox {
    let typeToken: Int
    let nameHint: Int
    let arrayComponent: Int

    init(typeToken: Int, nameHint: Int, arrayComponent: Int = 0) {
        self.typeToken = typeToken
        self.nameHint = nameHint
        self.arrayComponent = arrayComponent
    }

    var metadata: RuntimeKClassMetadataEntry? {
        runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    }
}

final class RuntimeKTypeBox {
    let classifierRaw: Int
    let argumentRaws: [Int]
    let isMarkedNullable: Bool
    let typeNameRaw: Int
    var annotations: [RuntimeAnnotationRecord] = []

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

final class RuntimeKTypeParameterBox {
    let nameRaw: Int
    let varianceOrdinal: Int
    let isReified: Bool
    var upperBoundsRaw: Int

    init(nameRaw: Int, varianceOrdinal: Int, isReified: Bool, upperBoundsRaw: Int) {
        self.nameRaw = nameRaw
        self.varianceOrdinal = varianceOrdinal
        self.isReified = isReified
        self.upperBoundsRaw = upperBoundsRaw
    }
}

/// Matches the Kotlin enum ordinals: IN=0, OUT=1, INVARIANT=2.
enum RuntimeKVariance: Int {
    case `in` = 0
    case out = 1
    case invariant = 2
}

final class RuntimeKTypeProjectionBox {
    let typeRaw: Int
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

enum RuntimeKParameterCallableOwnerDiscriminator {
    static let property = 0
}

final class RuntimeKParameterBox {
    var typeToken: Int?
    var reflectedTypeRaw: Int = 0
    var arrayComponentType: Int?
    var callableOwner = 0
    var callableRaw = 0
    var callableOwnerDiscriminator = RuntimeKParameterCallableOwnerDiscriminator.property
    var boundArguments: [Int] = []
    var annotations: [RuntimeAnnotationRecord] = []
    let index: Int
    let nameRaw: Int
    let typeRaw: Int
    let isOptional: Bool
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

final class RuntimeKFunctionBox {
    let nameRaw: Int
    let arity: Int
    let returnTypeRaw: Int
    let flags: Int
    let fnPtr: Int
    let closureRaw: Int
    let parameterRaws: [Int]
    let typeStringRaw: Int
    /// KUU-4423: `KCallable.visibility` ordinal (PUBLIC=0, PROTECTED=1,
    /// INTERNAL=2, PRIVATE=3) pinned by `__kk_kcallable_set_visibility`.
    /// Member handles carry no `RuntimeCallableRefMetadata`, so the
    /// metadata getter falls back to this field.
    var visibilityOrdinal: Int = 0
    /// KUU-4423: full `KType` box for `returnType`, pinned by
    /// `__kk_kcallable_register_return_type` when the handle has no
    /// callable metadata. Without it the getter falls back to the
    /// `returnTypeRaw` string descriptor and builds a classifier-less
    /// KType that resolves to `java.lang.Void`.
    var returnTypeKTypeRaw: Int = 0

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

final class RuntimeKConstructorBox {
    let nameRaw: Int
    let arity: Int
    let returnTypeRaw: Int
    let fnPtr: Int
    let isPrimary: Bool
    let visibilityRaw: Int
    var jvmVisibilityOrdinal: Int = 0
    let declaringClassRaw: Int
    let parameterNameRaws: [Int]
    var parameterTypeTokens: [Int?] = []

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

    func setParameterTypeToken(_ typeToken: Int, at index: Int) {
        guard index >= 0 else { return }
        if parameterTypeTokens.count <= index {
            parameterTypeTokens.append(contentsOf: Array(repeating: nil, count: index + 1 - parameterTypeTokens.count))
        }
        parameterTypeTokens[index] = typeToken
    }
}

final class RuntimeAnnotationBox {
    let annotationFQName: String
    let arguments: [String]
    let annotationClassRaw: Int

    init(annotationFQName: String, arguments: [String], annotationClassRaw: Int = 0) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.annotationClassRaw = annotationClassRaw
    }
}
