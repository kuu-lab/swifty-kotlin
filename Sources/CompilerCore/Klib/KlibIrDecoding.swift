import Foundation

/// `ProtoFields` → ``KlibIrModel`` decoding for every message in
/// `KotlinIr.proto`. Field numbers follow the proto file; required fields
/// that are absent surface as ``KlibFormatError/corruptProto(_:)``.
///
/// `body`/`initializer`/`default_value` fields are indices into the
/// file's `bodies.knb` row, `type`/`class_type`/`operand` into `types.knt`,
/// `name`/`origin_name`/`label`/`description` into `strings.knt`, and every
/// `symbol`/`classifier`/`super` int64 is a `BinarySymbolData` code.

private enum KlibIrDecodeError {
    static func missing(_ field: String) -> KlibFormatError {
        .corruptProto("missing required field \(field)")
    }

    static func badSymbol(_ field: String) -> KlibFormatError {
        .corruptProto("invalid symbol code in \(field)")
    }
}

private extension ProtoFields {
    /// Required int64 symbol field → ``KlibSymbolRef``.
    func symbol(_ field: Int, name: String) throws -> KlibSymbolRef {
        guard let code = int64(field) else { throw KlibIrDecodeError.missing(name) }
        guard let ref = KlibSymbolRef(code) else { throw KlibIrDecodeError.badSymbol(name) }
        return ref
    }

    func optionalSymbol(_ field: Int) throws -> KlibSymbolRef? {
        guard let code = int64(field) else { return nil }
        guard let ref = KlibSymbolRef(code) else { throw KlibIrDecodeError.badSymbol("symbol") }
        return ref
    }

    func symbolList(_ field: Int) throws -> [KlibSymbolRef] {
        try int64List(field).map { code in
            guard let ref = KlibSymbolRef(code) else { throw KlibIrDecodeError.badSymbol("symbol list") }
            return ref
        }
    }

    /// `name_type` lattice → ``KlibNameAndType``.
    func nameAndType(_ field: Int, name: String) throws -> KlibNameAndType {
        guard let code = int64(field) else { throw KlibIrDecodeError.missing(name) }
        let pair = KlibBinaryEncoding.decodeNameAndType(code)
        return KlibNameAndType(nameIndex: pair.nameIndex, typeIndex: pair.typeIndex)
    }

    func globalCoordinates(_ field: Int) -> KlibCoordinates? {
        guard has(field), let code = int64(field) else { return nil }
        return KlibBinaryEncoding.decodeCoordinates(code, usesZigZag: false)
    }

    func localCoordinates(_ field: Int) -> KlibCoordinates? {
        guard has(field), let code = int64(field) else { return nil }
        return KlibBinaryEncoding.decodeCoordinates(code, usesZigZag: true)
    }

    /// Optional sub-message decoded by `decode`.
    func decoded<T>(_ field: Int, _ decode: (ProtoFields) throws -> T) throws -> T? {
        guard let proto = try message(field) else { return nil }
        return try decode(proto)
    }

    /// Required sub-message decoded by `decode`.
    func required<T>(_ field: Int, name: String, _ decode: (ProtoFields) throws -> T) throws -> T {
        guard let value = try decoded(field, decode) else {
            throw KlibIrDecodeError.missing(name)
        }
        return value
    }

    /// Repeated sub-message field decoded by `decode`.
    func decodedList<T>(_ field: Int, _ decode: (ProtoFields) throws -> T) throws -> [T] {
        try messages(field).map(decode)
    }

    /// `repeated NullableIrExpression` → `[KlibIrExpression?]` (an absent
    /// element message means `null`).
    func nullableExpressionList(_ field: Int) throws -> [KlibIrExpression?] {
        try wireValues(field).map { value in
            guard case .bytes(let bytes) = value else { return nil }
            let proto = try ProtoFields(bytes)
            return try proto.decoded(1, KlibIrDecoding.expression)
        }
    }
}

/// Stateless decoder namespace; index-based fields stay raw — resolution
/// happens in ``KlibIrModule``.
package enum KlibIrDecoding {

    // MARK: Files

    package static func fileEntry(_ proto: ProtoFields) throws -> KlibFileEntry {
        var lineOffsets = try proto.int32List(2)
        if lineOffsets.isEmpty {
            // 2.3.0+: first element absolute, the rest are deltas.
            var absolute: [Int32] = []
            for delta in try proto.int32List(5) {
                absolute.append((absolute.last ?? 0) &+ delta)
            }
            lineOffsets = absolute
        }
        return KlibFileEntry(
            nameIndex: proto.int32(4),
            nameOld: proto.string(1),
            lineStartOffsets: lineOffsets,
            firstRelevantLineIndex: proto.int32(3) ?? 0
        )
    }

    package static func file(_ proto: ProtoFields) throws -> KlibIrFile {
        try KlibIrFile(
            declarationIds: proto.int32List(1),
            fileEntry: proto.decoded(2, fileEntry),
            fileEntryId: proto.int32(7),
            fqName: proto.int32List(3),
            annotations: proto.decodedList(4, annotation),
            explicitlyExportedToCompiler: proto.int64List(5)
        )
    }

    // MARK: Signatures

    package static func idSignature(_ proto: ProtoFields) throws -> KlibIdSignature {
        if let common = try proto.message(1) {
            // `member_uniq_id` moved from varint (3) to fixed64 (6) in 2.4.0.
            return .common(
                packageFqName: try common.int32List(1),
                declarationFqName: try common.int32List(2),
                memberId: common.fixed64(6).map { Int64(bitPattern: $0) } ?? common.int64(3),
                flags: common.int64(4) ?? 0,
                debugInfo: common.int32(5)
            )
        }
        if let private_ = try proto.message(2) {
            return .fileLocal(
                container: try requiredInt32(private_, 1, "private_sig.container"),
                localId: try requiredInt64(private_, 2, "private_sig.local_id")
            )
        }
        if let accessor = try proto.message(3) {
            return .accessor(
                propertySignature: try requiredInt32(accessor, 1, "accessor_sig.property_signature"),
                name: try requiredInt32(accessor, 2, "accessor_sig.name"),
                hashId: try requiredInt64(accessor, 3, "accessor_sig.accessor_hash_id"),
                flags: accessor.int64(4) ?? 0,
                debugInfo: accessor.int32(5)
            )
        }
        if let scoped = proto.int32(4) {
            return .scopedLocal(scoped)
        }
        if let composite = try proto.message(5) {
            return .composite(
                container: try requiredInt32(composite, 1, "composite_sig.container_sig"),
                inner: try requiredInt32(composite, 2, "composite_sig.inner_sig")
            )
        }
        if let local = try proto.message(6) {
            return .local(
                fqName: try local.int32List(1),
                hash: local.int64(2)
            )
        }
        if try proto.message(7) != nil || proto.has(7) {
            return .file
        }
        throw KlibFormatError.corruptProto("IdSignature has no id_sig set")
    }

    // MARK: Types

    package static func type(_ proto: ProtoFields) throws -> KlibIrType {
        if let legacy = try proto.message(1) {
            return .legacySimple(
                classifier: try legacy.symbol(2, name: "legacySimple.classifier"),
                hasQuestionMark: legacy.bool(3) ?? false,
                arguments: try legacy.int64List(4).map(KlibBinaryEncoding.decodeTypeProjection),
                annotations: try legacy.decodedList(1, annotation)
            )
        }
        if let dynamic = try proto.message(2) {
            return .dynamic(annotations: try dynamic.decodedList(1, annotation))
        }
        if let error = try proto.message(3) {
            return .error(annotations: try error.decodedList(1, annotation))
        }
        if let dnn = try proto.message(4) {
            return .definitelyNotNull(types: try dnn.int32List(1))
        }
        if let simple = try proto.message(5) {
            return .simple(
                classifier: try simple.symbol(2, name: "simple.classifier"),
                nullability: simple.int32(3).flatMap { KlibTypeNullability(rawValue: Int($0)) } ?? .notSpecified,
                arguments: try simple.int64List(4).map(KlibBinaryEncoding.decodeTypeProjection),
                annotations: try simple.decodedList(1, annotation)
            )
        }
        throw KlibFormatError.corruptProto("IrType has no kind set")
    }

    static func annotation(_ proto: ProtoFields) throws -> KlibAnnotation {
        try KlibAnnotation(
            symbol: proto.symbol(1, name: "annotation.symbol"),
            constructorTypeArgumentsCount: proto.int32(2) ?? 0,
            memberAccess: proto.decoded(3, memberAccess),
            arguments: proto.decodedList(5, expression),
            typeArguments: proto.int32List(6),
            originName: proto.int32(4)
        )
    }

    static func memberAccess(_ proto: ProtoFields) throws -> KlibMemberAccess {
        try KlibMemberAccess(
            dispatchReceiver: proto.decoded(1, expression),
            extensionReceiver: proto.decoded(2, expression),
            regularArguments: proto.nullableExpressionList(3),
            argumentsPre240: proto.nullableExpressionList(6),
            arguments: [],
            typeArguments: proto.int32List(4)
        )
    }

    // MARK: Declarations

    private static func declarationBase(_ proto: ProtoFields) throws -> KlibDeclBase {
        try KlibDeclBase(
            symbol: proto.symbol(1, name: "declaration.symbol"),
            originName: proto.int32(2) ?? 0,
            globalCoordinates: proto.globalCoordinates(3),
            localCoordinates: proto.localCoordinates(6),
            flags: KlibIrFlags(raw: proto.int64(4).map { UInt64(bitPattern: $0) } ?? 0),
            annotations: proto.decodedList(5, annotation)
        )
    }

    private static func functionBase(_ proto: ProtoFields) throws -> KlibFunctionBase {
        try KlibFunctionBase(
            base: proto.required(1, name: "function.base", declarationBase),
            nameType: proto.nameAndType(2, name: "function.name_type"),
            typeParameters: proto.decodedList(3, typeParameter),
            dispatchReceiver: proto.decoded(4, valueParameter),
            contextParameters: proto.decodedList(9, valueParameter),
            extensionReceiver: proto.decoded(5, valueParameter),
            regularParameters: proto.decodedList(6, valueParameter),
            bodyIndex: proto.int32(7),
            companionExtensionClass: proto.optionalSymbol(10)
        )
    }

    private static func anonymousInit(_ proto: ProtoFields) throws -> KlibAnonymousInit {
        try KlibAnonymousInit(
            base: proto.required(1, name: "anonymous_init.base", declarationBase),
            bodyIndex: proto.int32(2) ?? 0
        )
    }

    private static func `class`(_ proto: ProtoFields) throws -> KlibClass {
        try KlibClass(
            base: proto.required(1, name: "class.base", declarationBase),
            nameIndex: proto.int32(2) ?? 0,
            thisReceiver: proto.decoded(3, valueParameter),
            typeParameters: proto.decodedList(4, typeParameter),
            declarations: proto.decodedList(5, declaration),
            superTypes: proto.int32List(6),
            inlineClassRepresentation: proto.decoded(7, inlineClassRepresentation),
            sealedSubclasses: proto.symbolList(8)
        )
    }

    private static func inlineClassRepresentation(_ proto: ProtoFields) throws -> KlibInlineClassRepresentation {
        KlibInlineClassRepresentation(
            underlyingPropertyName: proto.int32(1) ?? 0,
            underlyingPropertyType: proto.int32(2) ?? 0
        )
    }

    private static func constructor(_ proto: ProtoFields) throws -> KlibConstructor {
        try KlibConstructor(
            base: proto.required(1, name: "constructor.base", functionBase)
        )
    }

    private static func enumEntry(_ proto: ProtoFields) throws -> KlibEnumEntry {
        try KlibEnumEntry(
            base: proto.required(1, name: "enum_entry.base", declarationBase),
            nameIndex: proto.int32(2) ?? 0,
            initializerIndex: proto.int32(3),
            correspondingClass: proto.decoded(4, `class`)
        )
    }

    private static func field(_ proto: ProtoFields) throws -> KlibField {
        try KlibField(
            base: proto.required(1, name: "field.base", declarationBase),
            nameType: proto.nameAndType(2, name: "field.name_type"),
            initializerIndex: proto.int32(3)
        )
    }

    static func function(_ proto: ProtoFields) throws -> KlibFunction {
        try KlibFunction(
            base: proto.required(1, name: "function.base", functionBase),
            overridden: proto.symbolList(2),
            preparedInlineFileEntryId: proto.int32(3)
        )
    }

    private static func localDelegatedProperty(_ proto: ProtoFields) throws -> KlibLocalDelegatedProperty {
        try KlibLocalDelegatedProperty(
            base: proto.required(1, name: "local_delegated_property.base", declarationBase),
            nameType: proto.nameAndType(2, name: "localDelegatedProperty.name_type"),
            delegate: proto.decoded(3, variable),
            getter: proto.decoded(4, function),
            setter: proto.decoded(5, function)
        )
    }

    private static func property(_ proto: ProtoFields) throws -> KlibProperty {
        try KlibProperty(
            base: proto.required(1, name: "property.base", declarationBase),
            nameIndex: proto.int32(2) ?? 0,
            backingField: proto.decoded(3, field),
            getter: proto.decoded(4, function),
            setter: proto.decoded(5, function)
        )
    }

    private static func variable(_ proto: ProtoFields) throws -> KlibVariable {
        try KlibVariable(
            base: proto.required(1, name: "variable.base", declarationBase),
            nameType: proto.nameAndType(2, name: "variable.name_type"),
            initializer: proto.decoded(3, expression)
        )
    }

    private static func valueParameter(_ proto: ProtoFields) throws -> KlibValueParameter {
        try KlibValueParameter(
            base: proto.required(1, name: "value_parameter.base", declarationBase),
            nameType: proto.nameAndType(2, name: "valueParameter.name_type"),
            varargElementType: proto.int32(3),
            defaultValueIndex: proto.int32(4)
        )
    }

    private static func typeParameter(_ proto: ProtoFields) throws -> KlibTypeParameter {
        try KlibTypeParameter(
            base: proto.required(1, name: "type_parameter.base", declarationBase),
            nameIndex: proto.int32(2) ?? 0,
            superTypes: proto.int32List(3)
        )
    }

    private static func typeAlias(_ proto: ProtoFields) throws -> KlibTypeAlias {
        try KlibTypeAlias(
            base: proto.required(1, name: "type_alias.base", declarationBase),
            nameType: proto.nameAndType(2, name: "typeAlias.name_type"),
            typeParameters: proto.decodedList(3, typeParameter)
        )
    }

    package static func declaration(_ proto: ProtoFields) throws -> KlibIrDeclaration {
        // `IrDeclaration` oneof field numbers.
        if let value = try proto.message(1) { return .anonymousInit(try anonymousInit(value)) }
        if let value = try proto.message(2) { return .class(try `class`(value)) }
        if let value = try proto.message(3) { return .constructor(try constructor(value)) }
        if let value = try proto.message(4) { return .enumEntry(try enumEntry(value)) }
        if let value = try proto.message(5) { return .field(try field(value)) }
        if let value = try proto.message(6) { return .function(try function(value)) }
        if let value = try proto.message(7) { return .property(try property(value)) }
        if let value = try proto.message(8) { return .typeParameter(try typeParameter(value)) }
        if let value = try proto.message(9) { return .variable(try variable(value)) }
        if let value = try proto.message(10) { return .valueParameter(try valueParameter(value)) }
        if let value = try proto.message(11) { return .localDelegatedProperty(try localDelegatedProperty(value)) }
        if let value = try proto.message(12) { return .typeAlias(try typeAlias(value)) }
        throw KlibFormatError.corruptProto("IrDeclaration has no declarator set")
    }

    // MARK: Expressions

    private static func optionalExpression(_ proto: ProtoFields, field: Int) throws -> KlibIrExpression? {
        try proto.decoded(field, expression)
    }

    private static func expressionList(_ proto: ProtoFields, field: Int) throws -> [KlibIrExpression] {
        try proto.decodedList(field, expression)
    }

    private static func statementList(_ proto: ProtoFields, field: Int) throws -> [KlibIrStatement] {
        try proto.decodedList(field, statement)
    }

    /// Merges `member_access_pre_2_4_0` with the post-2.4 on-message
    /// `argument`/`type_argument` fields.
    private static func callMemberAccess(
        _ proto: ProtoFields,
        memberAccessField: Int,
        argumentField: Int,
        typeArgumentField: Int
    ) throws -> KlibMemberAccess {
        var access = try proto.decoded(memberAccessField, memberAccess) ?? KlibMemberAccess(
            dispatchReceiver: nil, extensionReceiver: nil,
            regularArguments: [], argumentsPre240: [], arguments: [], typeArguments: []
        )
        access.arguments = try expressionList(proto, field: argumentField)
        if !proto.has(typeArgumentField) { return access }
        access.typeArguments = try proto.int32List(typeArgumentField)
        return access
    }

    private static func const(_ proto: ProtoFields) throws -> KlibIrExpressionKind {
        if proto.has(1) { return .constNull }
        if let v = proto.bool(2) { return .constBool(v) }
        if let v = proto.int32(3) { return .constChar(v) }
        if let v = proto.int32(4) { return .constByte(v) }
        if let v = proto.int32(5) { return .constShort(v) }
        if let v = proto.int32(6) { return .constInt(v) }
        if let v = proto.int64(7) { return .constLong(v) }
        if let v = proto.fixed32(8) { return .constFloat(v) }
        if let v = proto.fixed64(9) { return .constDouble(v) }
        if let v = proto.int32(10) { return .constString(v) }
        throw KlibFormatError.corruptProto("IrConst has no value set")
    }

    private static func fieldAccess(_ proto: ProtoFields) throws -> KlibFieldAccess {
        try KlibFieldAccess(
            symbol: proto.symbol(1, name: "field_access.symbol"),
            super: proto.optionalSymbol(2),
            receiver: proto.decoded(3, expression)
        )
    }

    private static func loop(_ proto: ProtoFields) throws -> KlibLoop {
        guard let condition = try proto.message(2) else {
            throw KlibIrDecodeError.missing("loop.condition")
        }
        return try KlibLoop(
            loopId: proto.int32(1) ?? 0,
            condition: expression(condition),
            label: proto.int32(3),
            body: proto.decoded(4, expression),
            originName: proto.int32(5)
        )
    }

    private static func varargElement(_ proto: ProtoFields) throws -> KlibVarargElement {
        if let expr = try proto.message(1) {
            return .expression(try expression(expr))
        }
        if let spread = try proto.message(2) {
            guard let exprProto = try spread.message(1) else {
                throw KlibIrDecodeError.missing("spread_element.expression")
            }
            return .spread(
                expression: try expression(exprProto),
                globalCoordinates: spread.globalCoordinates(2),
                localCoordinates: spread.localCoordinates(3)
            )
        }
        throw KlibFormatError.corruptProto("IrVarargElement has no value set")
    }

    /// `IrOperationPre_2_4_0` — the legacy operation oneof (field numbers
    /// differ from `IrExpression.operation`).
    private static func legacyOperation(_ proto: ProtoFields) throws -> KlibIrExpressionKind {
        if let value = try proto.message(1) {
            return .block(
                statements: try statementList(value, field: 1),
                originName: value.int32(2)
            )
        }
        if let value = try proto.message(2) {
            return .break(loopId: value.int32(1) ?? 0, label: value.int32(2))
        }
        if let value = try proto.message(3) {
            return .call(
                symbol: try value.symbol(1, name: "call.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 2, argumentField: 5, typeArgumentField: 6),
                super: try value.optionalSymbol(3),
                originName: value.int32(4)
            )
        }
        if let value = try proto.message(4) {
            return .classReference(
                classSymbol: try value.symbol(1, name: "class_reference.class_symbol"),
                classType: value.int32(2) ?? 0
            )
        }
        if let value = try proto.message(5) {
            return .composite(
                statements: try statementList(value, field: 1),
                originName: value.int32(2)
            )
        }
        if let value = try proto.message(6) {
            return try const(value)
        }
        if let value = try proto.message(7) {
            return .continue(loopId: value.int32(1) ?? 0, label: value.int32(2))
        }
        if let value = try proto.message(8) {
            return .delegatingConstructorCall(
                symbol: try value.symbol(1, name: "delegating_constructor_call.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 2, argumentField: 3, typeArgumentField: 4)
            )
        }
        if let value = try proto.message(9) {
            return .doWhile(loop: try protoMessageLoop(value))
        }
        if let value = try proto.message(10) {
            return .enumConstructorCall(
                symbol: try value.symbol(1, name: "enum_constructor_call.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 2, argumentField: 3, typeArgumentField: 4)
            )
        }
        if let value = try proto.message(11) {
            return .functionReference(
                symbol: try value.symbol(1, name: "function_reference.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 3, argumentField: 5, typeArgumentField: 6),
                reflectionTarget: try value.optionalSymbol(4),
                originName: value.int32(2)
            )
        }
        if let value = try proto.message(12) {
            guard let argument = try value.message(1) else { throw KlibIrDecodeError.missing("get_class.argument") }
            return .getClass(argument: try expression(argument))
        }
        if let value = try proto.message(13) {
            return .getEnumValue(symbol: try value.symbol(1, name: "get_enum_value.symbol"))
        }
        if let value = try proto.message(14) {
            return .getField(
                access: try value.required(1, name: "field_access", fieldAccess),
                originName: value.int32(2)
            )
        }
        if let value = try proto.message(15) {
            return .getObject(symbol: try value.symbol(1, name: "get_object.symbol"))
        }
        if let value = try proto.message(16) {
            return .getValue(
                symbol: try value.symbol(1, name: "get_value.symbol"),
                originName: value.int32(2)
            )
        }
        if let value = try proto.message(17) {
            return .instanceInitializerCall(symbol: try value.symbol(1, name: "instance_initializer_call.symbol"))
        }
        if let value = try proto.message(18) {
            return .propertyReference(
                field: try value.optionalSymbol(1),
                getter: try value.optionalSymbol(2),
                setter: try value.optionalSymbol(3),
                symbol: try value.symbol(6, name: "property_reference.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 5, argumentField: 7, typeArgumentField: 8),
                originName: value.int32(4)
            )
        }
        if let value = try proto.message(19) {
            guard let returnExpr = try value.message(2) else { throw KlibIrDecodeError.missing("return.value") }
            return .return(
                target: try value.symbol(1, name: "return.return_target"),
                value: try expression(returnExpr)
            )
        }
        if let value = try proto.message(20) {
            guard let setValue = try value.message(2) else { throw KlibIrDecodeError.missing("set_field.value") }
            return .setField(
                access: try value.required(1, name: "field_access", fieldAccess),
                value: try expression(setValue),
                originName: value.int32(3)
            )
        }
        if let value = try proto.message(21) {
            guard let setExpr = try value.message(2) else { throw KlibIrDecodeError.missing("set_value.value") }
            return .setValue(
                symbol: try value.symbol(1, name: "set_value.symbol"),
                value: try expression(setExpr),
                originName: value.int32(3)
            )
        }
        if let value = try proto.message(22) {
            return .stringConcat(arguments: try expressionList(value, field: 1))
        }
        if let value = try proto.message(23) {
            guard let thrown = try value.message(1) else { throw KlibIrDecodeError.missing("throw.value") }
            return .throw(value: try expression(thrown))
        }
        if let value = try proto.message(24) {
            guard let result = try value.message(1) else { throw KlibIrDecodeError.missing("try.result") }
            return .try(
                result: try expression(result),
                catches: try statementList(value, field: 2),
                finally: try optionalExpression(value, field: 3)
            )
        }
        if let value = try proto.message(25) {
            guard let argument = try value.message(3) else { throw KlibIrDecodeError.missing("type_op.argument") }
            return .typeOp(
                operator: value.int32(1).flatMap { KlibTypeOperator(rawValue: Int($0)) } ?? .implicitCast,
                operandType: value.int32(2) ?? 0,
                argument: try expression(argument)
            )
        }
        if let value = try proto.message(26) {
            return .vararg(
                elementType: value.int32(1) ?? 0,
                elements: try value.decodedList(2, varargElement)
            )
        }
        if let value = try proto.message(27) {
            return .when(
                branches: try statementList(value, field: 1),
                originName: value.int32(2)
            )
        }
        if let value = try proto.message(28) {
            return .while(loop: try protoMessageLoop(value))
        }
        if let value = try proto.message(29) {
            guard let receiver = try value.message(2) else { throw KlibIrDecodeError.missing("dynamic_member.receiver") }
            return .dynamicMember(
                memberName: value.int32(1) ?? 0,
                receiver: try expression(receiver)
            )
        }
        if let value = try proto.message(30) {
            guard let receiver = try value.message(2) else { throw KlibIrDecodeError.missing("dynamic_operator.receiver") }
            return .dynamicOperator(
                operator: value.int32(1).flatMap { KlibDynamicOperator(rawValue: Int($0)) } ?? .invoke,
                receiver: try expression(receiver),
                arguments: try expressionList(value, field: 3)
            )
        }
        if let value = try proto.message(31) {
            return .localDelegatedPropertyReference(
                delegate: try value.optionalSymbol(1),
                getter: try value.optionalSymbol(2),
                setter: try value.optionalSymbol(3),
                symbol: try value.symbol(4, name: "local_delegated_property_reference.symbol"),
                originName: value.int32(5)
            )
        }
        if let value = try proto.message(32) {
            return .constructorCall(
                symbol: try value.symbol(1, name: "constructor_call.symbol"),
                constructorTypeArgumentsCount: value.int32(2) ?? 0,
                memberAccess: try callMemberAccess(value, memberAccessField: 3, argumentField: 5, typeArgumentField: 6),
                originName: value.int32(4)
            )
        }
        if let value = try proto.message(33) {
            guard let functionProto = try value.message(1) else { throw KlibIrDecodeError.missing("function_expression.function") }
            return .functionExpression(
                function: try function(functionProto),
                originName: value.int32(2) ?? 0
            )
        }
        if let value = try proto.message(34) {
            return .errorExpression(description: value.int32(1) ?? 0)
        }
        if let value = try proto.message(35) {
            return .errorCallExpression(
                description: value.int32(1) ?? 0,
                receiver: try optionalExpression(value, field: 2),
                valueArguments: try expressionList(value, field: 3)
            )
        }
        if let value = try proto.message(36) {
            let block = try value.decoded(2) { try statementList($0, field: 1) } ?? []
            return .returnableBlock(
                symbol: try value.symbol(1, name: "returnable_block.symbol"),
                statements: block,
                originName: (try value.message(2))?.int32(2)
            )
        }
        if let value = try proto.message(37) {
            return try inlinedFunctionBlock(value)
        }
        if let value = try proto.message(38) {
            guard let invokeProto = try value.message(4) else { throw KlibIrDecodeError.missing("rich_function_reference.invoke_function") }
            return .richFunctionReference(
                boundValues: try expressionList(value, field: 1),
                reflectionTarget: try value.optionalSymbol(2),
                overriddenFunction: try value.symbol(3, name: "rich_function_reference.overridden_function_symbol"),
                invokeFunction: try function(invokeProto),
                flags: value.int64(5).map { UInt64(bitPattern: $0) } ?? 0,
                originName: value.int32(6)
            )
        }
        if let value = try proto.message(39) {
            guard let getterProto = try value.message(3) else { throw KlibIrDecodeError.missing("rich_property_reference.getter_function") }
            return .richPropertyReference(
                boundValues: try expressionList(value, field: 1),
                reflectionTarget: try value.optionalSymbol(2),
                getterFunction: try function(getterProto),
                setterFunction: try protoSetterFunction(value),
                originName: value.int32(5)
            )
        }
        throw KlibFormatError.corruptProto("IrOperationPre_2_4_0 has no operation set")
    }

    private static func protoMessageLoop(_ proto: ProtoFields) throws -> KlibLoop {
        guard let loopProto = try proto.message(1) else { throw KlibIrDecodeError.missing("loop") }
        return try loop(loopProto)
    }

    private static func protoSetterFunction(_ proto: ProtoFields) throws -> KlibFunction? {
        guard let setter = try proto.message(4) else { return nil }
        return try function(setter)
    }

    private static func inlinedFunctionBlock(_ value: ProtoFields) throws -> KlibIrExpressionKind {
        let block = try value.message(3)
        return .inlinedFunctionBlock(
            symbol: try value.optionalSymbol(1),
            fileEntry: try value.decoded(2, fileEntry),
            fileEntryId: value.int32(6),
            statements: try block.map { try statementList($0, field: 1) } ?? [],
            originName: block?.int32(2),
            startOffset: value.int32(4) ?? 0,
            endOffset: value.int32(5) ?? 0
        )
    }

    /// `IrExpression`: the 2.4+ `operation` oneof occupies fields 5..44;
    /// field 1 carries the legacy `IrOperationPre_2_4_0` for older klibs.
    package static func expression(_ proto: ProtoFields) throws -> KlibIrExpression {
        let typeIndex = proto.int32(2) ?? -1
        let global = proto.globalCoordinates(3)
        let local = proto.localCoordinates(4)
        let kind: KlibIrExpressionKind

        if let legacy = try proto.message(1) {
            kind = try legacyOperation(legacy)
        } else if let value = try proto.message(5) {
            kind = try const(value)
        } else if let value = try proto.message(6) {
            kind = .getValue(symbol: try value.symbol(1, name: "get_value.symbol"), originName: value.int32(2))
        } else if let value = try proto.message(7) {
            guard let setExpr = try value.message(2) else { throw KlibIrDecodeError.missing("set_value.value") }
            kind = .setValue(symbol: try value.symbol(1, name: "set_value.symbol"), value: try expression(setExpr), originName: value.int32(3))
        } else if let value = try proto.message(8) {
            kind = .call(
                symbol: try value.symbol(1, name: "call.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 2, argumentField: 5, typeArgumentField: 6),
                super: try value.optionalSymbol(3),
                originName: value.int32(4)
            )
        } else if let value = try proto.message(9) {
            kind = .constructorCall(
                symbol: try value.symbol(1, name: "constructor_call.symbol"),
                constructorTypeArgumentsCount: value.int32(2) ?? 0,
                memberAccess: try callMemberAccess(value, memberAccessField: 3, argumentField: 5, typeArgumentField: 6),
                originName: value.int32(4)
            )
        } else if let value = try proto.message(10) {
            kind = .block(statements: try statementList(value, field: 1), originName: value.int32(2))
        } else if let value = try proto.message(11) {
            let block = try value.message(2)
            kind = .returnableBlock(
                symbol: try value.symbol(1, name: "returnable_block.symbol"),
                statements: try block.map { try statementList($0, field: 1) } ?? [],
                originName: block?.int32(2)
            )
        } else if let value = try proto.message(12) {
            guard let returnExpr = try value.message(2) else { throw KlibIrDecodeError.missing("return.value") }
            kind = .return(target: try value.symbol(1, name: "return.return_target"), value: try expression(returnExpr))
        } else if let value = try proto.message(13) {
            kind = .when(branches: try statementList(value, field: 1), originName: value.int32(2))
        } else if let value = try proto.message(14) {
            guard let argument = try value.message(3) else { throw KlibIrDecodeError.missing("type_op.argument") }
            kind = .typeOp(
                operator: value.int32(1).flatMap { KlibTypeOperator(rawValue: Int($0)) } ?? .implicitCast,
                operandType: value.int32(2) ?? 0,
                argument: try expression(argument)
            )
        } else if let value = try proto.message(15) {
            kind = .getField(
                access: try value.required(1, name: "field_access", fieldAccess),
                originName: value.int32(2)
            )
        } else if let value = try proto.message(16) {
            guard let setExpr = try value.message(2) else { throw KlibIrDecodeError.missing("set_field.value") }
            kind = .setField(
                access: try value.required(1, name: "field_access", fieldAccess),
                value: try expression(setExpr),
                originName: value.int32(3)
            )
        } else if let value = try proto.message(17) {
            kind = .getObject(symbol: try value.symbol(1, name: "get_object.symbol"))
        } else if let value = try proto.message(18) {
            guard let argument = try value.message(1) else { throw KlibIrDecodeError.missing("get_class.argument") }
            kind = .getClass(argument: try expression(argument))
        } else if let value = try proto.message(19) {
            kind = .classReference(
                classSymbol: try value.symbol(1, name: "class_reference.class_symbol"),
                classType: value.int32(2) ?? 0
            )
        } else if let value = try proto.message(20) {
            kind = .getEnumValue(symbol: try value.symbol(1, name: "get_enum_value.symbol"))
        } else if let value = try proto.message(21) {
            kind = .composite(statements: try statementList(value, field: 1), originName: value.int32(2))
        } else if let value = try proto.message(22) {
            kind = .break(loopId: value.int32(1) ?? 0, label: value.int32(2))
        } else if let value = try proto.message(23) {
            kind = .continue(loopId: value.int32(1) ?? 0, label: value.int32(2))
        } else if let value = try proto.message(24) {
            kind = .while(loop: try protoMessageLoop(value))
        } else if let value = try proto.message(25) {
            kind = .doWhile(loop: try protoMessageLoop(value))
        } else if let value = try proto.message(26) {
            kind = .delegatingConstructorCall(
                symbol: try value.symbol(1, name: "delegating_constructor_call.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 2, argumentField: 3, typeArgumentField: 4)
            )
        } else if let value = try proto.message(27) {
            kind = .enumConstructorCall(
                symbol: try value.symbol(1, name: "enum_constructor_call.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 2, argumentField: 3, typeArgumentField: 4)
            )
        } else if let value = try proto.message(28) {
            kind = .instanceInitializerCall(symbol: try value.symbol(1, name: "instance_initializer_call.symbol"))
        } else if let value = try proto.message(29) {
            kind = .stringConcat(arguments: try expressionList(value, field: 1))
        } else if let value = try proto.message(30) {
            guard let thrown = try value.message(1) else { throw KlibIrDecodeError.missing("throw.value") }
            kind = .throw(value: try expression(thrown))
        } else if let value = try proto.message(31) {
            guard let result = try value.message(1) else { throw KlibIrDecodeError.missing("try.result") }
            kind = .try(
                result: try expression(result),
                catches: try statementList(value, field: 2),
                finally: try optionalExpression(value, field: 3)
            )
        } else if let value = try proto.message(32) {
            kind = .vararg(
                elementType: value.int32(1) ?? 0,
                elements: try value.decodedList(2, varargElement)
            )
        } else if let value = try proto.message(33) {
            guard let receiver = try value.message(2) else { throw KlibIrDecodeError.missing("dynamic_member.receiver") }
            kind = .dynamicMember(memberName: value.int32(1) ?? 0, receiver: try expression(receiver))
        } else if let value = try proto.message(34) {
            guard let receiver = try value.message(2) else { throw KlibIrDecodeError.missing("dynamic_operator.receiver") }
            kind = .dynamicOperator(
                operator: value.int32(1).flatMap { KlibDynamicOperator(rawValue: Int($0)) } ?? .invoke,
                receiver: try expression(receiver),
                arguments: try expressionList(value, field: 3)
            )
        } else if let value = try proto.message(35) {
            kind = .localDelegatedPropertyReference(
                delegate: try value.optionalSymbol(1),
                getter: try value.optionalSymbol(2),
                setter: try value.optionalSymbol(3),
                symbol: try value.symbol(4, name: "local_delegated_property_reference.symbol"),
                originName: value.int32(5)
            )
        } else if let value = try proto.message(36) {
            guard let functionProto = try value.message(1) else { throw KlibIrDecodeError.missing("function_expression.function") }
            kind = .functionExpression(function: try function(functionProto), originName: value.int32(2) ?? 0)
        } else if let value = try proto.message(37) {
            kind = .errorExpression(description: value.int32(1) ?? 0)
        } else if let value = try proto.message(38) {
            kind = .errorCallExpression(
                description: value.int32(1) ?? 0,
                receiver: try optionalExpression(value, field: 2),
                valueArguments: try expressionList(value, field: 3)
            )
        } else if let value = try proto.message(39) {
            kind = .functionReference(
                symbol: try value.symbol(1, name: "function_reference.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 3, argumentField: 5, typeArgumentField: 6),
                reflectionTarget: try value.optionalSymbol(4),
                originName: value.int32(2)
            )
        } else if let value = try proto.message(40) {
            kind = .propertyReference(
                field: try value.optionalSymbol(1),
                getter: try value.optionalSymbol(2),
                setter: try value.optionalSymbol(3),
                symbol: try value.symbol(6, name: "property_reference.symbol"),
                memberAccess: try callMemberAccess(value, memberAccessField: 5, argumentField: 7, typeArgumentField: 8),
                originName: value.int32(4)
            )
        } else if let value = try proto.message(41) {
            guard let invokeProto = try value.message(4) else { throw KlibIrDecodeError.missing("rich_function_reference.invoke_function") }
            kind = .richFunctionReference(
                boundValues: try expressionList(value, field: 1),
                reflectionTarget: try value.optionalSymbol(2),
                overriddenFunction: try value.symbol(3, name: "rich_function_reference.overridden_function_symbol"),
                invokeFunction: try function(invokeProto),
                flags: value.int64(5).map { UInt64(bitPattern: $0) } ?? 0,
                originName: value.int32(6)
            )
        } else if let value = try proto.message(42) {
            guard let getterProto = try value.message(3) else { throw KlibIrDecodeError.missing("rich_property_reference.getter_function") }
            kind = .richPropertyReference(
                boundValues: try expressionList(value, field: 1),
                reflectionTarget: try value.optionalSymbol(2),
                getterFunction: try function(getterProto),
                setterFunction: try protoSetterFunction(value),
                originName: value.int32(5)
            )
        } else if let value = try proto.message(43) {
            kind = try inlinedFunctionBlock(value)
        } else if proto.has(44) {
            kind = .missingExpression
        } else {
            throw KlibFormatError.corruptProto("IrExpression has no operation set")
        }

        return KlibIrExpression(kind: kind, typeIndex: typeIndex, globalCoordinates: global, localCoordinates: local)
    }

    // MARK: Statements

    package static func statement(_ proto: ProtoFields) throws -> KlibIrStatement {
        let global = proto.globalCoordinates(1)
        let local = proto.localCoordinates(8)
        let kind: KlibIrStatementKind

        if let value = try proto.message(2) {
            kind = .declaration(try declaration(value))
        } else if let value = try proto.message(3) {
            kind = .expression(try expression(value))
        } else if let value = try proto.message(4) {
            kind = .blockBody(statements: try statementList(value, field: 1))
        } else if let value = try proto.message(5) {
            guard let condition = try value.message(1),
                  let result = try value.message(2)
            else { throw KlibIrDecodeError.missing("branch.condition/result") }
            kind = .branch(condition: try expression(condition), result: try expression(result))
        } else if let value = try proto.message(6) {
            guard let parameter = try value.message(1),
                  let result = try value.message(2)
            else { throw KlibIrDecodeError.missing("catch.catch_parameter/result") }
            kind = .catch(KlibIrCatch(parameter: try variable(parameter), result: try expression(result)))
        } else if let value = try proto.message(7) {
            kind = .syntheticBody(value.int32(1).flatMap { KlibSyntheticBodyKind(rawValue: Int($0)) } ?? .enumValues)
        } else {
            throw KlibFormatError.corruptProto("IrStatement has no statement set")
        }

        return KlibIrStatement(kind: kind, globalCoordinates: global, localCoordinates: local)
    }

    // MARK: - Helpers

    private static func requiredInt32(_ proto: ProtoFields, _ field: Int, _ name: String) throws -> Int32 {
        guard let value = proto.int32(field) else { throw KlibIrDecodeError.missing(name) }
        return value
    }

    private static func requiredInt64(_ proto: ProtoFields, _ field: Int, _ name: String) throws -> Int64 {
        guard let value = proto.int64(field) else { throw KlibIrDecodeError.missing(name) }
        return value
    }
}
