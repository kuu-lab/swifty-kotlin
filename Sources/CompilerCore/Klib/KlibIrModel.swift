import Foundation

/// Decoded Kotlin IR schema types (`KotlinIr.proto`), as stored in the
/// `ir/*.kn*` chunk tables of a `.klib`.
///
/// Indices (`Int32` fields named `*Index` or inside list values) refer to
/// the *file-local* tables — `types`, `signatures`, `strings`, `bodies`,
/// `fileEntries` — resolved through ``KlibIrModule``. Every symbol `Int64`
/// is a `BinarySymbolData` code: `(signatureIndex << 8) | kind`.

// MARK: - Binary encodings

/// Kotlin `BinarySymbolData.SymbolKind` ordinals.
package enum KlibSymbolKind: Int, Sendable, CustomStringConvertible {
    case function = 0
    case constructor = 1
    case enumEntry = 2
    case field = 3
    case valueParameter = 4
    case returnableBlock = 5
    case `class` = 6
    case typeParameter = 7
    case variable = 8
    case anonymousInit = 9
    case standaloneField = 10
    case receiverParameter = 11
    case property = 12
    case localDelegatedProperty = 13
    case typeAlias = 14
    case file = 15

    package var description: String {
        switch self {
        case .function: "function"
        case .constructor: "constructor"
        case .enumEntry: "enumEntry"
        case .field: "field"
        case .valueParameter: "valueParameter"
        case .returnableBlock: "returnableBlock"
        case .class: "class"
        case .typeParameter: "typeParameter"
        case .variable: "variable"
        case .anonymousInit: "anonymousInit"
        case .standaloneField: "standaloneField"
        case .receiverParameter: "receiverParameter"
        case .property: "property"
        case .localDelegatedProperty: "localDelegatedProperty"
        case .typeAlias: "typeAlias"
        case .file: "file"
        }
    }
}

/// Signature-table identity: all `signatures`/`types`/`bodies`/`strings`
/// tables are file-local, so a signature index only makes sense paired with
/// its file index. Used as the key of the `(fileIndex, signatureIndex) →
/// SymbolID` map that body materialization resolves symbol references with.
package struct KlibSignatureKey: Hashable, Sendable {
    package let fileIndex: Int
    package let signatureIndex: Int

    package init(fileIndex: Int, signatureIndex: Int) {
        self.fileIndex = fileIndex
        self.signatureIndex = signatureIndex
    }
}

/// A decoded `BinarySymbolData` code referencing a signature-table entry.
package struct KlibSymbolRef: Equatable, Sendable {
    /// Index into the file's `signatures.knt` row.
    package let signatureIndex: Int
    package let kind: KlibSymbolKind

    package init?(_ code: Int64) {
        guard let kind = KlibSymbolKind(rawValue: Int(code & 0xFF)) else { return nil }
        // `code ushr 8`: unsigned shift — the signature id occupies the
        // upper bits and is always non-negative in valid data.
        self.signatureIndex = Int(UInt64(bitPattern: code) >> 8)
        self.kind = kind
    }
}

/// File-relative source coordinates decoded from a lattice code.
/// `local` coordinates are relative to the parent's start offset.
package struct KlibCoordinates: Equatable, Sendable {
    package let start: Int32
    package let end: Int32
}

/// Kotlin `BinaryLattice`/`BinaryCoordinates`/`BinaryNameAndType` helpers.
package enum KlibBinaryEncoding {
    /// Splits a bit-interleaved code into its two 32-bit halves.
    package static func decodeLattice(_ code: Int64) -> (first: Int32, second: Int32) {
        (decodeHalf(code), decodeHalf(code >> 1))
    }

    /// `name_type` field → `(nameIndex, typeIndex)` into the file-local
    /// `strings`/`types` tables.
    package static func decodeNameAndType(_ code: Int64) -> (nameIndex: Int32, typeIndex: Int32) {
        let pair = decodeLattice(code)
        return (nameIndex: pair.first, typeIndex: pair.second)
    }

    /// `BinaryCoordinatesEncoding`: lattice of `(start, end - start)`;
    /// local coordinates zigzag-encode the signed `start`.
    package static func decodeCoordinates(_ code: Int64, usesZigZag: Bool) -> KlibCoordinates {
        let decoded = decodeLattice(code)
        var start = decoded.first
        if usesZigZag {
            // ZigZag32 decode: (n >> 1) ^ -(n & 1)
            let bits = UInt32(bitPattern: start)
            start = Int32(bitPattern: (bits >> 1) ^ (0 &- (bits & 1)))
        }
        return KlibCoordinates(start: start, end: start &+ decoded.second)
    }

    /// `BinaryTypeProjection`: `0` = `*`, otherwise
    /// `(typeIndex << 2) | (varianceOrdinal + 1)`.
    package static func decodeTypeProjection(_ code: Int64) -> KlibTypeArgument {
        guard code != 0 else { return .star }
        let varianceId = Int(code & 0x3) - 1
        let variance = KlibVariance(rawValue: varianceId) ?? .invariant
        return .type(index: Int32(truncatingIfNeeded: code >> 2), variance: variance)
    }

    private static func decodeHalf(_ code: Int64) -> Int32 {
        var x = UInt64(bitPattern: code)
        x = x & 0x5555_5555_5555_5555
        x = (x ^ (x >> 1)) & 0x3333_3333_3333_3333
        x = (x ^ (x >> 2)) & 0x0F0F_0F0F_0F0F_0F0F
        x = (x ^ (x >> 4)) & 0x00FF_00FF_00FF_00FF
        x = (x ^ (x >> 8)) & 0x0000_FFFF_0000_FFFF
        x = (x ^ (x >> 16)) & 0x0000_0000_FFFF_FFFF
        return Int32(bitPattern: UInt32(truncatingIfNeeded: x))
    }
}

// MARK: - Signatures

/// Kotlin `IdSignature` cases. Signature references are indices into the
/// file-local `signatures` table; fq-name segment lists are `strings`
/// table indices joined with `.`.
package enum KlibIdSignature: Equatable {
    /// Top-level public signature (`CommonIdSignature`).
    case common(packageFqName: [Int32], declarationFqName: [Int32], memberId: Int64?, flags: Int64, debugInfo: Int32?)
    /// Property accessor signature.
    case accessor(propertySignature: Int32, name: Int32, hashId: Int64, flags: Int64, debugInfo: Int32?)
    /// Private/file-local signature (`FileLocalIdSignature`).
    case fileLocal(container: Int32, localId: Int64)
    /// Local symbol scoped to the file (`scoped_local_sig` raw value).
    case scopedLocal(Int32)
    case composite(container: Int32, inner: Int32)
    case local(fqName: [Int32], hash: Int64?)
    /// Marker resolved to the owning file's `FileSignature`.
    case file
}

// MARK: - Flags

package enum KlibVisibility: Int { case `internal` = 0, `private` = 1, protected = 2, `public` = 3, privateToThis = 4, local = 5 }
package enum KlibModality: Int { case final = 0, open = 1, abstract = 2, sealed = 3 }
package enum KlibMemberKind: Int { case declaration = 0, fakeOverride = 1, delegation = 2, synthesized = 3 }
package enum KlibClassKind: Int { case `class` = 0, interface = 1, enumClass = 2, enumEntry = 3, annotationClass = 4, object = 5, companionObject = 6 }
package enum KlibVariance: Int { case `in` = 0, out = 1, invariant = 2 }

/// `IrFlags` bit layout (extends metadata `Flags`): bit 0
/// `hasAnnotations`, bits 1–3 `visibility`, bits 4–5 `modality`; the rest
/// is declaration-specific.
package struct KlibIrFlags {
    package let raw: UInt64

    package init(raw: UInt64) { self.raw = raw }

    package var hasAnnotations: Bool { bit(0) }
    package var visibility: KlibVisibility { KlibVisibility(rawValue: field(1, width: 3)) ?? .public }
    package var modality: KlibModality { KlibModality(rawValue: field(4, width: 2)) ?? .final }

    // MARK: Class bits (after modality)
    package var classKind: KlibClassKind { KlibClassKind(rawValue: field(6, width: 3)) ?? .class }
    package var isInner: Bool { bit(9) }
    package var isData: Bool { bit(10) }
    package var isExternalClass: Bool { bit(11) }
    package var isExpectClass: Bool { bit(12) }
    package var isValueClass: Bool { bit(13) }
    package var isFunInterface: Bool { bit(14) }
    package var hasEnumEntries: Bool { bit(15) }

    // MARK: Callable bits (after modality)
    package var memberKind: KlibMemberKind { KlibMemberKind(rawValue: field(6, width: 2)) ?? .declaration }
    // Functions
    package var isOperator: Bool { bit(8) }
    package var isInfix: Bool { bit(9) }
    package var isInline: Bool { bit(10) }
    package var isTailrec: Bool { bit(11) }
    package var isExternalFunction: Bool { bit(12) }
    package var isSuspend: Bool { bit(13) }
    package var isExpectFunction: Bool { bit(14) }
    package var hasNonStableParameterNames: Bool { bit(15) }
    /// `IrFlags.IS_PRIMARY` for constructors (aliases the function's
    /// non-stable-names bit).
    package var isPrimaryConstructor: Bool { bit(15) }
    package var isStaticFunction: Bool { bit(18) }
    // Properties
    package var isVar: Bool { bit(8) }
    package var hasGetter: Bool { bit(9) }
    package var hasSetter: Bool { bit(10) }
    package var isConst: Bool { bit(11) }
    package var isLateinit: Bool { bit(12) }
    package var hasConstant: Bool { bit(13) }
    package var isExternalProperty: Bool { bit(14) }
    package var isDelegated: Bool { bit(15) }
    package var isExpectProperty: Bool { bit(16) }
    package var isStaticProperty: Bool { bit(19) }
    // Accessors
    package var isNotDefaultAccessor: Bool { bit(6) }
    package var isExternalAccessor: Bool { bit(7) }
    package var isInlineAccessor: Bool { bit(8) }

    // MARK: Type parameter bits (after hasAnnotations)
    package var typeParameterVariance: KlibVariance { KlibVariance(rawValue: field(1, width: 2)) ?? .invariant }
    package var isReified: Bool { bit(3) }

    // MARK: Type alias bits
    package var isActual: Bool { bit(4) }

    // MARK: Field bits (after visibility)
    package var isFinalField: Bool { bit(4) }
    package var isExternalField: Bool { bit(5) }
    package var isStaticField: Bool { bit(6) }
    package var isFakeOverrideField: Bool { bit(7) }

    // MARK: Value parameter bits (after hasAnnotations)
    package var declaresDefaultValue: Bool { bit(1) }
    package var isCrossinline: Bool { bit(2) }
    package var isNoinline: Bool { bit(3) }
    package var isHiddenParameter: Bool { bit(4) }
    package var isAssignable: Bool { bit(5) }

    // MARK: Local variable bits (after hasAnnotations)
    package var isLocalVar: Bool { bit(1) }
    package var isLocalConst: Bool { bit(2) }
    package var isLocalLateinit: Bool { bit(3) }

    private func bit(_ index: Int) -> Bool {
        (raw >> index) & 1 == 1
    }

    private func field(_ offset: Int, width: Int) -> Int {
        Int((raw >> offset) & ((1 << width) - 1))
    }
}

// MARK: - Types

package enum KlibTypeNullability: Int {
    case markedNullable = 0
    case notSpecified = 1
    case definitelyNotNull = 2
}

package enum KlibTypeArgument: Equatable {
    case star
    /// `index` into the file's `types` table.
    case type(index: Int32, variance: KlibVariance)
}

/// Kotlin `IrAnnotation` has the same shape as `IrConstructorCall`.
package struct KlibAnnotation {
    package var symbol: KlibSymbolRef
    package var constructorTypeArgumentsCount: Int32
    package var memberAccess: KlibMemberAccess?
    package var arguments: [KlibIrExpression]
    /// Indices into `types` (packed int64? no — `type_argument` is packed int32).
    package var typeArguments: [Int32]
    package var originName: Int32?
}

package enum KlibIrType {
    case simple(classifier: KlibSymbolRef, nullability: KlibTypeNullability, arguments: [KlibTypeArgument], annotations: [KlibAnnotation])
    case legacySimple(classifier: KlibSymbolRef, hasQuestionMark: Bool, arguments: [KlibTypeArgument], annotations: [KlibAnnotation])
    case dynamic(annotations: [KlibAnnotation])
    case error(annotations: [KlibAnnotation])
    /// `types` are indices into the `types` table.
    case definitelyNotNull(types: [Int32])
}

// MARK: - Declarations

package struct KlibDeclBase {
    package var symbol: KlibSymbolRef
    /// `IrStatementOrigin` name → `strings` index.
    package var originName: Int32
    package var globalCoordinates: KlibCoordinates?
    /// Relative to the parent's start offset.
    package var localCoordinates: KlibCoordinates?
    package var flags: KlibIrFlags
    package var annotations: [KlibAnnotation]
}

/// Decoded `name_type` pair.
package struct KlibNameAndType: Equatable {
    package var nameIndex: Int32
    /// Index into `types` for the declared type.
    package var typeIndex: Int32
}

package struct KlibAnonymousInit {
    package var base: KlibDeclBase
    /// Index into `bodies`.
    package var bodyIndex: Int32
}

package struct KlibClass {
    package var base: KlibDeclBase
    /// `strings` index.
    package var nameIndex: Int32
    package var thisReceiver: KlibValueParameter?
    package var typeParameters: [KlibTypeParameter]
    package var declarations: [KlibIrDeclaration]
    /// `types` indices.
    package var superTypes: [Int32]
    package var inlineClassRepresentation: KlibInlineClassRepresentation?
    /// Symbol codes of sealed subclasses.
    package var sealedSubclasses: [KlibSymbolRef]
}

package struct KlibInlineClassRepresentation {
    package var underlyingPropertyName: Int32
    /// `types` index.
    package var underlyingPropertyType: Int32
}

package struct KlibConstructor {
    package var base: KlibFunctionBase
}

package struct KlibEnumEntry {
    package var base: KlibDeclBase
    package var nameIndex: Int32
    /// Index into `bodies` for the initializer expression.
    package var initializerIndex: Int32?
    package var correspondingClass: KlibClass?
}

package struct KlibField {
    package var base: KlibDeclBase
    package var nameType: KlibNameAndType
    /// Index into `bodies` for the initializer expression.
    package var initializerIndex: Int32?
}

package struct KlibFunctionBase {
    package var base: KlibDeclBase
    package var nameType: KlibNameAndType
    package var typeParameters: [KlibTypeParameter]
    package var dispatchReceiver: KlibValueParameter?
    package var contextParameters: [KlibValueParameter]
    package var extensionReceiver: KlibValueParameter?
    package var regularParameters: [KlibValueParameter]
    /// Index into `bodies`, absent for abstract/external declarations.
    package var bodyIndex: Int32?
    package var companionExtensionClass: KlibSymbolRef?
}

package struct KlibFunction {
    package var base: KlibFunctionBase
    /// Overridden function symbol codes.
    package var overridden: [KlibSymbolRef]
    package var preparedInlineFileEntryId: Int32?
}

package struct KlibLocalDelegatedProperty {
    package var base: KlibDeclBase
    package var nameType: KlibNameAndType
    package var delegate: KlibVariable?
    package var getter: KlibFunction?
    package var setter: KlibFunction?
}

package struct KlibProperty {
    package var base: KlibDeclBase
    package var nameIndex: Int32
    package var backingField: KlibField?
    package var getter: KlibFunction?
    package var setter: KlibFunction?
}

package struct KlibVariable {
    package var base: KlibDeclBase
    package var nameType: KlibNameAndType
    package var initializer: KlibIrExpression?
}

package struct KlibValueParameter {
    package var base: KlibDeclBase
    package var nameType: KlibNameAndType
    /// `types` index when the parameter is `vararg`.
    package var varargElementType: Int32?
    /// Index into `bodies` for the default-value expression.
    package var defaultValueIndex: Int32?
}

package struct KlibTypeParameter {
    package var base: KlibDeclBase
    package var nameIndex: Int32
    /// `types` indices.
    package var superTypes: [Int32]
}

package struct KlibTypeAlias {
    package var base: KlibDeclBase
    package var nameType: KlibNameAndType
    package var typeParameters: [KlibTypeParameter]
}

package enum KlibIrDeclaration {
    case anonymousInit(KlibAnonymousInit)
    case `class`(KlibClass)
    case constructor(KlibConstructor)
    case enumEntry(KlibEnumEntry)
    case field(KlibField)
    case function(KlibFunction)
    case property(KlibProperty)
    case typeParameter(KlibTypeParameter)
    case variable(KlibVariable)
    case valueParameter(KlibValueParameter)
    case localDelegatedProperty(KlibLocalDelegatedProperty)
    case typeAlias(KlibTypeAlias)
}

// MARK: - Expressions and statements

/// `MemberAccessCommonPre_2_4_0` merged with the post-2.4 call-site fields.
package struct KlibMemberAccess {
    /// Pre-2.4 field 1.
    package var dispatchReceiver: KlibIrExpression?
    /// Pre-2.4 field 2.
    package var extensionReceiver: KlibIrExpression?
    /// Pre-2.4 field 3 (`NullableIrExpression` list).
    package var regularArguments: [KlibIrExpression?]
    /// Pre-2.4 field 6 (`argument_pre_2_4_0`).
    package var argumentsPre240: [KlibIrExpression?]
    /// 2.4+ `argument` list on the call message itself.
    package var arguments: [KlibIrExpression]
    /// Indices into `types`.
    package var typeArguments: [Int32]
}

package struct KlibFieldAccess {
    package var symbol: KlibSymbolRef
    package var `super`: KlibSymbolRef?
    package var receiver: KlibIrExpression?
}

package struct KlibLoop {
    package var loopId: Int32
    package var condition: KlibIrExpression
    /// `strings` index.
    package var label: Int32?
    package var body: KlibIrExpression?
    package var originName: Int32?
}

package enum KlibTypeOperator: Int {
    case cast = 1, implicitCast = 2, implicitNotNull = 3, implicitCoercionToUnit = 4
    case implicitIntegerCoercion = 5, safeCast = 6, `is` = 7, notIs = 8
    case samConversion = 9, implicitDynamicCast = 10, reinterpretCast = 11
}

package enum KlibDynamicOperator: Int {
    case unaryPlus = 1, unaryMinus = 2, excl = 3
    case prefixIncrement = 4, postfixIncrement = 5, prefixDecrement = 6, postfixDecrement = 7
    case binaryPlus = 8, binaryMinus = 9, mul = 10, div = 11, mod = 12
    case gt = 13, lt = 14, ge = 15, le = 16
    case eqeq = 17, exclEq = 18, eqeqeq = 19, exclEqEq = 20
    case andAnd = 21, orOr = 22
    case eq = 23, plusEq = 24, minusEq = 25, mulEq = 26, divEq = 27, modEq = 28
    case arrayAccess = 29, invoke = 30
}

package enum KlibVarargElement {
    case expression(KlibIrExpression)
    case spread(expression: KlibIrExpression, globalCoordinates: KlibCoordinates?, localCoordinates: KlibCoordinates?)
}

/// `IrExpression` operation cases. `typeIndex`/`coordinates` live on the
/// wrapper, ``KlibIrExpression``.
package indirect enum KlibIrExpressionKind {
    case constNull
    case constBool(Bool)
    case constChar(Int32)
    case constByte(Int32)
    case constShort(Int32)
    case constInt(Int32)
    case constLong(Int64)
    /// `Float(bitPattern:)`
    case constFloat(UInt32)
    /// `Double(bitPattern:)`
    case constDouble(UInt64)
    /// `strings` index.
    case constString(Int32)
    case getValue(symbol: KlibSymbolRef, originName: Int32?)
    case setValue(symbol: KlibSymbolRef, value: KlibIrExpression, originName: Int32?)
    case call(symbol: KlibSymbolRef, memberAccess: KlibMemberAccess, `super`: KlibSymbolRef?, originName: Int32?)
    case constructorCall(symbol: KlibSymbolRef, constructorTypeArgumentsCount: Int32, memberAccess: KlibMemberAccess, originName: Int32?)
    case block(statements: [KlibIrStatement], originName: Int32?)
    case returnableBlock(symbol: KlibSymbolRef, statements: [KlibIrStatement], originName: Int32?)
    case inlinedFunctionBlock(symbol: KlibSymbolRef?, fileEntry: KlibFileEntry?, fileEntryId: Int32?, statements: [KlibIrStatement], originName: Int32?, startOffset: Int32, endOffset: Int32)
    case `return`(target: KlibSymbolRef, value: KlibIrExpression)
    case when(branches: [KlibIrStatement], originName: Int32?)
    case typeOp(operator: KlibTypeOperator, operandType: Int32, argument: KlibIrExpression)
    case getField(access: KlibFieldAccess, originName: Int32?)
    case setField(access: KlibFieldAccess, value: KlibIrExpression, originName: Int32?)
    case getObject(symbol: KlibSymbolRef)
    case getClass(argument: KlibIrExpression)
    case classReference(classSymbol: KlibSymbolRef, classType: Int32)
    case getEnumValue(symbol: KlibSymbolRef)
    case composite(statements: [KlibIrStatement], originName: Int32?)
    case `break`(loopId: Int32, label: Int32?)
    case `continue`(loopId: Int32, label: Int32?)
    case `while`(loop: KlibLoop)
    case doWhile(loop: KlibLoop)
    case delegatingConstructorCall(symbol: KlibSymbolRef, memberAccess: KlibMemberAccess)
    case enumConstructorCall(symbol: KlibSymbolRef, memberAccess: KlibMemberAccess)
    case instanceInitializerCall(symbol: KlibSymbolRef)
    case stringConcat(arguments: [KlibIrExpression])
    case `throw`(value: KlibIrExpression)
    case `try`(result: KlibIrExpression, catches: [KlibIrStatement], finally: KlibIrExpression?)
    case vararg(elementType: Int32, elements: [KlibVarargElement])
    case dynamicMember(memberName: Int32, receiver: KlibIrExpression)
    case dynamicOperator(operator: KlibDynamicOperator, receiver: KlibIrExpression, arguments: [KlibIrExpression])
    case localDelegatedPropertyReference(delegate: KlibSymbolRef?, getter: KlibSymbolRef?, setter: KlibSymbolRef?, symbol: KlibSymbolRef, originName: Int32?)
    case functionExpression(function: KlibFunction, originName: Int32)
    case functionReference(symbol: KlibSymbolRef, memberAccess: KlibMemberAccess, reflectionTarget: KlibSymbolRef?, originName: Int32?)
    case propertyReference(field: KlibSymbolRef?, getter: KlibSymbolRef?, setter: KlibSymbolRef?, symbol: KlibSymbolRef, memberAccess: KlibMemberAccess, originName: Int32?)
    case richFunctionReference(boundValues: [KlibIrExpression], reflectionTarget: KlibSymbolRef?, overriddenFunction: KlibSymbolRef, invokeFunction: KlibFunction, flags: UInt64, originName: Int32?)
    case richPropertyReference(boundValues: [KlibIrExpression], reflectionTarget: KlibSymbolRef?, getterFunction: KlibFunction, setterFunction: KlibFunction?, originName: Int32?)
    case errorExpression(description: Int32)
    case errorCallExpression(description: Int32, receiver: KlibIrExpression?, valueArguments: [KlibIrExpression])
    case missingExpression
}

package struct KlibIrExpression {
    package var kind: KlibIrExpressionKind
    /// Index into `types`; `-1` marks the proto default.
    package var typeIndex: Int32
    package var globalCoordinates: KlibCoordinates?
    package var localCoordinates: KlibCoordinates?
}

package struct KlibIrCatch {
    package var parameter: KlibVariable
    package var result: KlibIrExpression
}

package enum KlibSyntheticBodyKind: Int {
    case enumValues = 1
    case enumValueOf = 2
    case enumEntries = 3
}

package enum KlibIrStatementKind {
    case declaration(KlibIrDeclaration)
    case expression(KlibIrExpression)
    case blockBody(statements: [KlibIrStatement])
    case branch(condition: KlibIrExpression, result: KlibIrExpression)
    case `catch`(KlibIrCatch)
    case syntheticBody(KlibSyntheticBodyKind)
}

package struct KlibIrStatement {
    package var kind: KlibIrStatementKind
    package var globalCoordinates: KlibCoordinates?
    package var localCoordinates: KlibCoordinates?
}

// MARK: - Files

package struct KlibFileEntry {
    /// `strings` index (2.3.0+); `nameOld` carries the inline string for
    /// older klibs.
    package var nameIndex: Int32?
    package var nameOld: String?
    /// Absolute per-line start offsets, reconstructed from deltas.
    package var lineStartOffsets: [Int32]
    package var firstRelevantLineIndex: Int32
}

package struct KlibIrFile {
    /// Top-level declaration ids → `irDeclarations` row of this file.
    package var declarationIds: [Int32]
    package var fileEntry: KlibFileEntry?
    /// Index into the `fileEntries` row of this file.
    package var fileEntryId: Int32?
    /// `strings` indices forming the package fq name.
    package var fqName: [Int32]
    package var annotations: [KlibAnnotation]
    package var explicitlyExportedToCompiler: [Int64]
}
