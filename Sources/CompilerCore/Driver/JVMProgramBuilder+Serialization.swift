import Foundation

enum JVMSerialKind: CaseIterable {
    case boolean, byte, short, char, int, long, float, double, string

    var stem: String {
        switch self {
        case .boolean: "Boolean"
        case .byte: "Byte"
        case .short: "Short"
        case .char: "Char"
        case .int: "Int"
        case .long: "Long"
        case .float: "Float"
        case .double: "Double"
        case .string: "String"
        }
    }

    var primitive: JVMValueType {
        switch self {
        case .boolean: .boolean
        case .byte: .byte
        case .short: .short
        case .char: .char
        case .int: .int
        case .long: .long
        case .float: .float
        case .double: .double
        case .string: .string
        }
    }

    var nullableType: JVMValueType {
        switch self {
        case .boolean: .reference("java/lang/Boolean", nullable: true)
        case .byte: .reference("java/lang/Byte", nullable: true)
        case .short: .reference("java/lang/Short", nullable: true)
        case .char: .reference("java/lang/Character", nullable: true)
        case .int: .reference("java/lang/Integer", nullable: true)
        case .long: .reference("java/lang/Long", nullable: true)
        case .float: .reference("java/lang/Float", nullable: true)
        case .double: .reference("java/lang/Double", nullable: true)
        case .string: .reference("java/lang/String", nullable: true)
        }
    }

    var serializerClass: String { "kotlinx/serialization/internal/" + stem + "Serializer" }
}

enum JVMSerialDefault {
    case null
    case constant(JVMConstant)
}

struct JVMSerialElement {
    let propertyName: String
    let serialName: String
    let kind: JVMSerialKind
    let isNullable: Bool
    let defaultValue: JVMSerialDefault?

    var storageType: JVMValueType { isNullable ? kind.nullableType : kind.primitive }
}

struct JVMSerializationPlan {
    let serialName: String
    let elements: [JVMSerialElement]
    let serializerSymbol: SymbolID
    let companionSymbol: SymbolID
    let companionIsSynthetic: Bool

    var optionalMask: Int32 {
        var mask: Int32 = 0
        for (index, element) in elements.enumerated() where element.defaultValue != nil {
            mask |= Int32(1) << Int32(index)
        }
        return mask
    }

    var allMask: Int32 {
        elements.count >= 32 ? -1 : Int32(bitPattern: (UInt32(1) << UInt32(elements.count)) &- 1)
    }
}

extension JVMProgramBuilder {
    static let serialDescriptorType = JVMValueType.reference("kotlinx/serialization/descriptors/SerialDescriptor", nullable: false)
    static let kSerializerType = JVMValueType.reference("kotlinx/serialization/KSerializer", nullable: false)
    static let encoderType = JVMValueType.reference("kotlinx/serialization/encoding/Encoder", nullable: false)
    static let decoderType = JVMValueType.reference("kotlinx/serialization/encoding/Decoder", nullable: false)
    static let compositeEncoderType = JVMValueType.reference("kotlinx/serialization/encoding/CompositeEncoder", nullable: false)
    static let compositeDecoderType = JVMValueType.reference("kotlinx/serialization/encoding/CompositeDecoder", nullable: false)
    static let serializationStrategyType = JVMValueType.reference("kotlinx/serialization/SerializationStrategy", nullable: false)
    static let deserializationStrategyType = JVMValueType.reference("kotlinx/serialization/DeserializationStrategy", nullable: false)
    static let generatedSerializerName = "kotlinx/serialization/internal/GeneratedSerializer"
    static let generatedDescriptorName = "kotlinx/serialization/internal/PluginGeneratedSerialDescriptor"
    static let anyOrNull = JVMValueType.reference("java/lang/Object", nullable: true)

    func serializerClassName(_ plan: JVMClassPlan) -> String { plan.name + "$$serializer" }

    private func serialFQName(_ symbol: SemanticSymbol) -> String {
        symbol.fqName.map(context.interner.resolve).joined(separator: ".")
    }

    private enum SerialNameOverride {
        case absent
        case literal(String)
        case unsupported
    }

    private func serialNameOverride(_ annotations: [MetadataAnnotationRecord]) -> SerialNameOverride {
        guard let annotation = annotations.first(where: { $0.annotationFQName == KnownCompilerAnnotation.serializationSerialName.qualifiedName }) else { return .absent }
        guard annotation.arguments.count == 1 else { return .unsupported }
        var argument = annotation.arguments[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if argument.hasPrefix("value") {
            let rest = argument.dropFirst("value".count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard rest.hasPrefix("=") else { return .unsupported }
            argument = rest.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard argument.count >= 2, argument.hasPrefix("\""), argument.hasSuffix("\"") else { return .unsupported }
        let body = String(argument.dropFirst().dropLast())
        let scalars = Array(body.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar == "\"" || scalar == "\\" || scalar.value < 0x20 || scalar.value == 0x7F { return .unsupported }
            if scalar == "$", index + 1 < scalars.count { return .unsupported }
        }
        return .literal(body)
    }

    private func hasUnsupportedSerializationAnnotation(_ annotations: [MetadataAnnotationRecord]) -> Bool {
        annotations.contains {
            $0.annotationFQName.hasPrefix("kotlinx.serialization.")
                && $0.annotationFQName != KnownCompilerAnnotation.serializationSerialName.qualifiedName
                && !($0.annotationFQName == "kotlinx.serialization.Serializable" && $0.arguments.isEmpty)
        }
    }

    private func serialKind(_ type: TypeID) -> (JVMSerialKind, Bool)? {
        switch sema.types.kind(of: type) {
        case let .stringStruct(nullability):
            return nullability == .platformType ? nil : (.string, nullability == .nullable)
        case let .primitive(primitive, nullability):
            guard nullability != .platformType else { return nil }
            let kind: JVMSerialKind
            switch primitive {
            case .boolean: kind = .boolean
            case .byte: kind = .byte
            case .short: kind = .short
            case .char: kind = .char
            case .int: kind = .int
            case .long: kind = .long
            case .float: kind = .float
            case .double: kind = .double
            default: return nil
            }
            return (kind, nullability == .nullable)
        default:
            return nil
        }
    }

    private func serialDefault(_ id: ExprID?, kind: JVMSerialKind, nullable: Bool) -> JVMSerialDefault? {
        guard let id, let expression = ast.arena.expr(id) else { return nil }
        switch expression {
        case .nullLiteral:
            return nullable ? JVMSerialDefault.null : nil
        case let .boolLiteral(value, _):
            return kind == .boolean ? .constant(.boolean(value)) : nil
        case let .stringLiteral(value, _):
            return kind == .string ? .constant(.string(context.interner.resolve(value))) : nil
        case let .charLiteral(value, _):
            return kind == .char ? Int32(exactly: value).map { JVMSerialDefault.constant(.int($0)) } : nil
        case let .intLiteral(value, _):
            return numericDefault(value, kind: kind)
        case let .unaryExpr(.unaryMinus, operand, _):
            guard let inner = ast.arena.expr(operand) else { return nil }
            switch inner {
            case let .intLiteral(value, _):
                return numericDefault(-value, kind: kind)
            case let .longLiteral(value, _):
                return kind == .long ? .constant(.long(-value)) : nil
            case let .doubleLiteral(value, _):
                return kind == .double ? .constant(.double(-value)) : nil
            case let .floatLiteral(value, _):
                return kind == .float ? .constant(.float(-Float(value))) : nil
            default:
                return nil
            }
        case let .longLiteral(value, _):
            return kind == .long ? .constant(.long(value)) : nil
        case let .doubleLiteral(value, _):
            return kind == .double ? .constant(.double(value)) : nil
        case let .floatLiteral(value, _):
            if kind == .float { return .constant(.float(Float(value))) }
            return nil
        default:
            return nil
        }
    }

    private func numericDefault(_ value: Int64, kind: JVMSerialKind) -> JVMSerialDefault? {
        switch kind {
        case .int, .short, .byte: return Int32(exactly: value).map { JVMSerialDefault.constant(.int($0)) }
        case .long: return .constant(.long(value))
        default: return nil
        }
    }

    func serializationPlan(for plan: JVMClassPlan) -> JVMSerializationPlan? {
        let symbols = sema.symbols
        guard let info = sema.serializationClasses[plan.symbol],
              info.generatedSerializerClass != nil,
              let serializerSymbol = info.companionSerializerMethod,
              let companionSymbol = info.companionObjectSymbol,
              symbols.symbol(serializerSymbol)?.flags.contains(.synthetic) == true,
              symbols.parentSymbol(for: serializerSymbol) == companionSymbol,
              let declaration = plan.declaration,
              plan.object == nil, plan.interface == nil, plan.enumParent == nil,
              !plan.isEnum, !plan.isAnonymous, !plan.isLocalNominal, !plan.isInner,
              !plan.isValue, !plan.isJvmRecord, !plan.isAnnotation,
              declaration.modifiers.isDisjoint(with: [.abstract, .sealed, .enumModifier, .annotationClass, .inner]),
              declaration.typeParams.isEmpty,
              declaration.hasPrimaryConstructorSyntax || declaration.secondaryConstructors.isEmpty,
              !declaration.primaryConstructorModifiers.contains(.private),
              declaration.primaryConstructorParams.count <= 31,
              declaration.companionBlockObject == nil,
              let classSymbol = symbols.symbol(plan.symbol)
        else { return nil }
        let companionIsSynthetic = symbols.symbol(companionSymbol)?.flags.contains(.synthetic) == true
        guard companionIsSynthetic || classes[companionSymbol] != nil else { return nil }

        for parent in symbols.directSupertypes(for: plan.symbol) {
            guard let parentSymbol = symbols.symbol(parent) else { return nil }
            if parentSymbol.kind == .interface { continue }
            guard parentSymbol.kind == .class, serialFQName(parentSymbol) == "kotlin.Any" else { return nil }
        }

        let classAnnotations = symbols.annotations(for: plan.symbol)
        guard !hasUnsupportedSerializationAnnotation(classAnnotations) else { return nil }

        var propertiesByName: [String: SerializationPropertyInfo] = [:]
        for property in info.serializableProperties {
            guard let symbol = symbols.symbol(property.symbol) else { return nil }
            propertiesByName[context.interner.resolve(symbol.name)] = property
        }

        var elements: [JVMSerialElement] = []
        for parameter in declaration.primaryConstructorParams {
            let name = context.interner.resolve(parameter.name)
            guard parameter.isProperty, !parameter.isVararg,
                  let property = propertiesByName[name],
                  let propertyType = symbols.propertyType(for: property.symbol),
                  let (kind, nullable) = serialKind(propertyType),
                  !hasUnsupportedSerializationAnnotation(symbols.annotations(for: property.symbol))
            else { return nil }
            var defaultValue: JVMSerialDefault?
            if parameter.hasDefaultValue {
                guard let literal = serialDefault(parameter.defaultValue, kind: kind, nullable: nullable) else { return nil }
                defaultValue = literal
            }
            var serialName = name
            switch serialNameOverride(symbols.annotations(for: property.symbol)) {
            case .absent: break
            case let .literal(value): serialName = value
            case .unsupported: return nil
            }
            elements.append(JVMSerialElement(
                propertyName: name,
                serialName: serialName,
                kind: kind,
                isNullable: nullable,
                defaultValue: defaultValue
            ))
        }
        guard elements.count == propertiesByName.count else { return nil }

        var classSerialName = serialFQName(classSymbol)
        switch serialNameOverride(classAnnotations) {
        case .absent: break
        case let .literal(value): classSerialName = value
        case .unsupported: return nil
        }

        return JVMSerializationPlan(
            serialName: classSerialName,
            elements: elements,
            serializerSymbol: serializerSymbol,
            companionSymbol: companionSymbol,
            companionIsSynthetic: companionIsSynthetic
        )
    }

    func hasUnsupportedSerializableClass(named name: InternedString) -> Bool {
        sema.serializationClasses.keys.contains { symbol in
            guard let plan = classes[symbol], plan.declaration?.name == name else { return false }
            return serializationPlan(for: plan) == nil
        }
    }

    func prepareSerialization() throws {
        for plan in classes.values.sorted(by: { $0.name < $1.name }) {
            guard let serialization = serializationPlan(for: plan) else { continue }
            if serialization.companionIsSynthetic, classes[serialization.companionSymbol] == nil {
                let name = context.interner.intern("Companion")
                let range = plan.declaration!.range
                let object = ObjectDecl(range: range, name: name, modifiers: [.companion])
                let declaration = ClassDecl(range: range, name: name, modifiers: [])
                let companion = JVMClassPlan(
                    symbol: serialization.companionSymbol,
                    name: try className(serialization.companionSymbol),
                    declaration: declaration
                )
                companion.object = object
                companion.companionOwner = plan.symbol
                companion.outer = plan.symbol
                classes[serialization.companionSymbol] = companion
            }
            guard let companion = classes[serialization.companionSymbol] else { continue }
            methods[serialization.serializerSymbol] = JVMForeignMethod(
                owner: companion.name,
                name: "serializer",
                descriptor: "()" + Self.kSerializerType.descriptor,
                parameters: [],
                result: Self.kSerializerType,
                isStatic: false,
                isInterface: false,
                isAbstract: false
            )
        }
    }

    func serializationMembers(_ plan: JVMClassPlan) throws -> [JVMFunction] {
        if let serialization = serializationPlan(for: plan) {
            return [try writeSelfMethod(plan, serialization)]
        }
        guard plan.isObject, let owner = plan.companionOwner, let ownerPlan = classes[owner],
              let serialization = serializationPlan(for: ownerPlan),
              serialization.companionSymbol == plan.symbol else { return [] }
        return [try companionSerializerMethod(plan, ownerPlan)]
    }

    func serializerClass(for plan: JVMClassPlan) throws -> JVMClass? {
        guard let serialization = serializationPlan(for: plan) else { return nil }
        let name = serializerClassName(plan)
        let helper = JVMClassPlan(symbol: plan.symbol, name: name, declaration: plan.declaration)
        let classType = JVMValueType.reference(plan.name, nullable: false)
        let instance = JVMField(owner: name, name: "INSTANCE", type: .reference(name, nullable: false), access: 0x19)
        let descriptor = JVMField(owner: name, name: "descriptor", type: Self.serialDescriptorType, access: 0x1A)

        var functions: [JVMFunction] = []
        functions.append(try serializerConstructor(helper))
        functions.append(try serializeMethod(helper, plan, descriptor: descriptor, classType: classType))
        functions.append(try deserializeMethod(helper, plan, serialization, descriptor: descriptor, classType: classType))
        functions.append(try descriptorGetter(helper, descriptor: descriptor))
        functions.append(try childSerializersMethod(helper, serialization))
        functions.append(try serializeBridge(helper, classType: classType))
        functions.append(try deserializeBridge(helper, classType: classType))
        functions.append(try serializerInitializer(helper, serialization, instance: instance, descriptor: descriptor))

        var result = JVMClass(
            name: name,
            superclass: "java/lang/Object",
            interfaces: [Self.generatedSerializerName],
            access: 0x0031,
            functions: functions,
            properties: []
        )
        result.extraFields = [instance, descriptor]
        result.emitMetadata = false
        result.outerName = plan.name
        result.innerName = "$serializer"
        result.genericSignature = "Ljava/lang/Object;L" + Self.generatedSerializerName + "<L" + plan.name + ";>;"
        return result
    }

    private func serialFinish(_ builder: JVMFunctionBuilder, access: UInt16, constructor: Bool = false) -> JVMFunction {
        var function = builder.finish(constructor: constructor)
        function.access = access
        function.isSynthetic = access & 0x1000 != 0
        return function
    }

    private func serialCall(
        _ b: JVMFunctionBuilder,
        _ owner: String,
        _ name: String,
        _ parameters: [JVMValueType],
        _ result: JVMValueType,
        receiver: JVMValue? = nil,
        arguments: [JVMValue] = [],
        interface: Bool = false
    ) throws -> JVMValue? {
        try b.jdkCall(owner, name, parameters, result, receiver: receiver, arguments: arguments, interface: interface)
    }

    private func intConstant(_ b: JVMFunctionBuilder, _ value: Int) throws -> JVMValue {
        try b.constant(.int(Int32(value)), .int)
    }

    private func strategy(
        _ b: JVMFunctionBuilder,
        _ element: JVMSerialElement,
        as type: JVMValueType
    ) throws -> JVMValue {
        let objectType = JVMValueType.reference(element.kind.serializerClass, nullable: false)
        let field = JVMField(owner: element.kind.serializerClass, name: "INSTANCE", type: objectType, access: 0x19)
        let loaded = try b.value(objectType)
        b.instructions.append(.getStatic(field, loaded))
        return try b.convert(loaded, to: type)
    }

    private func serializerConstructor(_ helper: JVMClassPlan) throws -> JVMFunction {
        let b = try nominalBuilder(helper, name: "<init>")
        b.instructions += [.foreignCall(objectConstructor(), receiver: b.thisValue, arguments: [], result: nil), .returnValue(nil)]
        var function = serialFinish(b, access: 2, constructor: true)
        function.isPrivate = true
        return function
    }

    private func serializeMethod(_ helper: JVMClassPlan, _ plan: JVMClassPlan, descriptor: JVMField, classType: JVMValueType) throws -> JVMFunction {
        let b = try nominalBuilder(helper, name: "serialize", parameters: [Self.encoderType, classType], result: .unit)
        let encoder = b.locals[1], value = b.locals[2]
        let desc = try b.value(Self.serialDescriptorType)
        b.instructions.append(.getStatic(descriptor, desc))
        let composite = try serialCall(b, "kotlinx/serialization/encoding/Encoder", "beginStructure", [Self.serialDescriptorType], Self.compositeEncoderType, receiver: encoder, arguments: [desc], interface: true)!
        _ = try serialCall(b, plan.name, "write$Self", [classType, Self.compositeEncoderType, Self.serialDescriptorType], .unit, arguments: [value, composite, desc])
        _ = try serialCall(b, "kotlinx/serialization/encoding/CompositeEncoder", "endStructure", [Self.serialDescriptorType], .unit, receiver: composite, arguments: [desc], interface: true)
        b.instructions.append(.returnValue(nil))
        return serialFinish(b, access: 0x11)
    }

    private func serializeBridge(_ helper: JVMClassPlan, classType: JVMValueType) throws -> JVMFunction {
        let b = try nominalBuilder(helper, name: "serialize", parameters: [Self.encoderType, Self.anyOrNull], result: .unit)
        _ = try serialCall(b, helper.name, "serialize", [Self.encoderType, classType], .unit, receiver: b.thisValue, arguments: [b.locals[1], b.locals[2]])
        b.instructions.append(.returnValue(nil))
        return serialFinish(b, access: 0x1041)
    }

    private func deserializeBridge(_ helper: JVMClassPlan, classType: JVMValueType) throws -> JVMFunction {
        let b = try nominalBuilder(helper, name: "deserialize", parameters: [Self.decoderType], result: Self.anyOrNull)
        let result = try serialCall(b, helper.name, "deserialize", [Self.decoderType], classType, receiver: b.thisValue, arguments: [b.locals[1]])!
        b.instructions.append(.returnValue(try b.convert(result, to: Self.anyOrNull)))
        return serialFinish(b, access: 0x1041)
    }

    private func descriptorGetter(_ helper: JVMClassPlan, descriptor: JVMField) throws -> JVMFunction {
        let b = try nominalBuilder(helper, name: "getDescriptor", result: Self.serialDescriptorType)
        let value = try b.value(Self.serialDescriptorType)
        b.instructions += [.getStatic(descriptor, value), .returnValue(value)]
        return serialFinish(b, access: 0x11)
    }

    private func childSerializersMethod(_ helper: JVMClassPlan, _ serialization: JVMSerializationPlan) throws -> JVMFunction {
        let arrayType = JVMValueType.reference("[Lkotlinx/serialization/KSerializer;", nullable: false)
        let b = try nominalBuilder(helper, name: "childSerializers", result: arrayType)
        let array = try b.value(arrayType)
        b.instructions.append(.newArray(Self.kSerializerType, count: try intConstant(b, serialization.elements.count), result: array))
        for (index, element) in serialization.elements.enumerated() {
            var serializer = try strategy(b, element, as: Self.kSerializerType)
            if element.isNullable {
                serializer = try serialCall(
                    b,
                    "kotlinx/serialization/builtins/BuiltinSerializersKt",
                    "getNullable",
                    [Self.kSerializerType],
                    Self.kSerializerType,
                    arguments: [serializer]
                )!
            }
            b.instructions.append(.arraySet(array, try intConstant(b, index), serializer))
        }
        b.instructions.append(.returnValue(array))
        var function = serialFinish(b, access: 0x11)
        function.genericSignature = "()[Lkotlinx/serialization/KSerializer<*>;"
        return function
    }

    private func serializerInitializer(
        _ helper: JVMClassPlan,
        _ serialization: JVMSerializationPlan,
        instance: JVMField,
        descriptor: JVMField
    ) throws -> JVMFunction {
        let b = try nominalBuilder(helper, name: "<clinit>", staticBody: true)
        let object = try b.constructJDK(helper.name)
        b.instructions.append(.putStatic(instance, object))
        let generated = JVMValueType.reference(Self.generatedSerializerName, nullable: false)
        let name = try b.constant(.string(serialization.serialName), .string)
        let count = try intConstant(b, serialization.elements.count)
        let builder = try b.constructJDK(
            Self.generatedDescriptorName,
            parameters: [.string, generated, .int],
            arguments: [name, try b.convert(object, to: generated), count]
        )
        for element in serialization.elements {
            let elementName = try b.constant(.string(element.serialName), .string)
            let optional = try b.constant(.boolean(element.defaultValue != nil), .boolean)
            _ = try serialCall(b, Self.generatedDescriptorName, "addElement", [.string, .boolean], .unit, receiver: builder, arguments: [elementName, optional])
        }
        b.instructions.append(.putStatic(descriptor, try b.convert(builder, to: Self.serialDescriptorType)))
        b.instructions.append(.returnValue(nil))
        return serialFinish(b, access: 8)
    }

    private func writeSelfMethod(_ plan: JVMClassPlan, _ serialization: JVMSerializationPlan) throws -> JVMFunction {
        let classType = JVMValueType.reference(plan.name, nullable: false)
        let b = try nominalBuilder(
            plan,
            name: "write$Self",
            parameters: [classType, Self.compositeEncoderType, Self.serialDescriptorType],
            result: .unit,
            staticBody: true
        )
        let this = b.locals[0], output = b.locals[1], desc = b.locals[2]
        for (index, element) in serialization.elements.enumerated() {
            guard let property = plan.properties.first(where: { $0.2.name == element.propertyName })?.2,
                  let field = property.field else {
                throw JVMFrontendError(message: "Missing JVM serializable property field: \(element.propertyName).", range: plan.declaration?.range)
            }
            let skip = b.label(), encode = b.label(), compare = b.label()
            let current = try b.value(field.type)
            b.instructions.append(.getField(field, this, current))
            let position = try intConstant(b, index)
            if let defaultValue = element.defaultValue {
                let forced = try serialCall(b, "kotlinx/serialization/encoding/CompositeEncoder", "shouldEncodeElementDefault", [Self.serialDescriptorType, .int], .boolean, receiver: output, arguments: [desc, position], interface: true)!
                b.instructions.append(.jumpIfFalse(forced, compare))
                b.jump(encode)
                b.mark(compare)
                let differs = try b.value(.boolean)
                switch defaultValue {
                case .null:
                    let null = try b.constant(.null, field.type)
                    b.instructions.append(.referenceCompare(.notEqual, current, null, differs))
                case let .constant(constant):
                    if element.kind == .string || element.isNullable {
                        let literal = try b.constant(constant, element.kind.primitive)
                        let equal = try serialCall(
                            b,
                            "java/util/Objects",
                            "equals",
                            [Self.anyOrNull, Self.anyOrNull],
                            .boolean,
                            arguments: [current, literal]
                        )!
                        b.instructions.append(.unary(.not, equal, differs))
                    } else {
                        let literal = try b.constant(constant, element.kind.primitive == .byte || element.kind.primitive == .short || element.kind.primitive == .char ? .int : element.kind.primitive)
                        let widened = element.kind.primitive == .byte || element.kind.primitive == .short || element.kind.primitive == .char
                            ? try b.convert(current, to: .int)
                            : current
                        b.instructions.append(.binary(.notEqual, widened, literal, differs))
                    }
                }
                b.instructions.append(.jumpIfFalse(differs, skip))
                b.mark(encode)
            }
            if element.isNullable {
                let boxed = try b.convert(current, to: Self.anyOrNull)
                _ = try serialCall(
                    b,
                    "kotlinx/serialization/encoding/CompositeEncoder",
                    "encodeNullableSerializableElement",
                    [Self.serialDescriptorType, .int, Self.serializationStrategyType, Self.anyOrNull],
                    .unit,
                    receiver: output,
                    arguments: [desc, position, try strategy(b, element, as: Self.serializationStrategyType), boxed],
                    interface: true
                )
            } else {
                _ = try serialCall(
                    b,
                    "kotlinx/serialization/encoding/CompositeEncoder",
                    "encode" + element.kind.stem + "Element",
                    [Self.serialDescriptorType, .int, element.kind.primitive],
                    .unit,
                    receiver: output,
                    arguments: [desc, position, current],
                    interface: true
                )
            }
            b.mark(skip)
        }
        b.instructions.append(.returnValue(nil))
        return serialFinish(b, access: 0x1019)
    }

    private func decodeElement(
        _ b: JVMFunctionBuilder,
        composite: JVMValue,
        desc: JVMValue,
        index: Int,
        element: JVMSerialElement,
        into variable: JVMValue,
        seen: JVMValue
    ) throws {
        let position = try intConstant(b, index)
        let decoded: JVMValue
        if element.isNullable {
            let raw = try serialCall(
                b,
                "kotlinx/serialization/encoding/CompositeDecoder",
                "decodeNullableSerializableElement",
                [Self.serialDescriptorType, .int, Self.deserializationStrategyType, Self.anyOrNull],
                Self.anyOrNull,
                receiver: composite,
                arguments: [desc, position, try strategy(b, element, as: Self.deserializationStrategyType), try b.convert(variable, to: Self.anyOrNull)],
                interface: true
            )!
            decoded = try b.convert(raw, to: element.storageType)
        } else {
            decoded = try serialCall(
                b,
                "kotlinx/serialization/encoding/CompositeDecoder",
                "decode" + element.kind.stem + "Element",
                [Self.serialDescriptorType, .int],
                element.kind.primitive,
                receiver: composite,
                arguments: [desc, position],
                interface: true
            )!
        }
        b.instructions.append(.copy(decoded, variable))
        let bit = try b.constant(.int(Int32(1) << Int32(index)), .int)
        b.instructions.append(.binary(.bitwiseOr, seen, bit, seen))
    }

    private func deserializeMethod(
        _ helper: JVMClassPlan,
        _ plan: JVMClassPlan,
        _ serialization: JVMSerializationPlan,
        descriptor: JVMField,
        classType: JVMValueType
    ) throws -> JVMFunction {
        guard let primary = plan.constructors.first(where: { $0.2 }), let primaryMethod = methods[primary.0] else {
            throw JVMFrontendError(message: "Missing JVM primary constructor for serializable class.", range: plan.declaration?.range)
        }
        let b = try nominalBuilder(helper, name: "deserialize", parameters: [Self.decoderType], result: classType)
        let decoder = b.locals[1]
        let desc = try b.value(Self.serialDescriptorType)
        b.instructions.append(.getStatic(descriptor, desc))
        let seen = try intConstant(b, 0)
        var variables: [JVMValue] = []
        for element in serialization.elements { variables.append(try b.zero(element.storageType)) }
        let composite = try serialCall(b, "kotlinx/serialization/encoding/Decoder", "beginStructure", [Self.serialDescriptorType], Self.compositeDecoderType, receiver: decoder, arguments: [desc], interface: true)!

        let sequential = try serialCall(b, "kotlinx/serialization/encoding/CompositeDecoder", "decodeSequentially", [], .boolean, receiver: composite, interface: true)!
        let loop = b.label(), done = b.label()
        b.instructions.append(.jumpIfFalse(sequential, loop))
        for (index, element) in serialization.elements.enumerated() {
            try decodeElement(b, composite: composite, desc: desc, index: index, element: element, into: variables[index], seen: seen)
        }
        b.jump(done)

        b.mark(loop)
        let head = b.label()
        b.mark(head)
        let current = try serialCall(b, "kotlinx/serialization/encoding/CompositeDecoder", "decodeElementIndex", [Self.serialDescriptorType], .int, receiver: composite, arguments: [desc], interface: true)!
        let terminator = try b.constant(.int(-1), .int)
        let finished = try b.value(.boolean)
        b.instructions.append(.binary(.equal, current, terminator, finished))
        let continuing = b.label()
        b.instructions.append(.jumpIfFalse(finished, continuing))
        b.jump(done)
        b.mark(continuing)
        for (index, element) in serialization.elements.enumerated() {
            let next = b.label()
            let matches = try b.value(.boolean)
            b.instructions.append(.binary(.equal, current, try intConstant(b, index), matches))
            b.instructions.append(.jumpIfFalse(matches, next))
            try decodeElement(b, composite: composite, desc: desc, index: index, element: element, into: variables[index], seen: seen)
            b.jump(head)
            b.mark(next)
        }
        let unknown = try b.constructJDK("kotlinx/serialization/UnknownFieldException", parameters: [.int], arguments: [current])
        b.instructions.append(.throwValue(unknown))
        b.mark(done)

        _ = try serialCall(b, "kotlinx/serialization/encoding/CompositeDecoder", "endStructure", [Self.serialDescriptorType], .unit, receiver: composite, arguments: [desc], interface: true)

        let required = serialization.allMask & ~serialization.optionalMask
        if required != 0 {
            let mask = try b.constant(.int(required), .int)
            let present = try b.value(.int)
            b.instructions.append(.binary(.bitwiseAnd, seen, mask, present))
            let missing = try b.value(.boolean)
            b.instructions.append(.binary(.notEqual, present, mask, missing))
            let complete = b.label()
            b.instructions.append(.jumpIfFalse(missing, complete))
            _ = try serialCall(b, "kotlinx/serialization/internal/PluginExceptionsKt", "throwMissingFieldException", [.int, .int, Self.serialDescriptorType], .unit, arguments: [seen, mask, desc])
            b.mark(complete)
        }

        let object = try b.value(classType)
        b.instructions.append(.allocate(plan.name, object))
        if serialization.optionalMask != 0 {
            let everything = try b.constant(.int(-1), .int)
            let absent = try b.value(.int)
            b.instructions.append(.binary(.bitwiseXor, seen, everything, absent))
            let optional = try b.constant(.int(serialization.optionalMask), .int)
            let defaults = try b.value(.int)
            b.instructions.append(.binary(.bitwiseAnd, absent, optional, defaults))
            let marker = JVMValueType.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)
            let parameters = primaryMethod.parameters + [.int, marker]
            let target = JVMForeignMethod(
                owner: plan.name,
                name: "<init>",
                descriptor: "(" + parameters.map(\.descriptor).joined() + ")V",
                parameters: parameters,
                result: classType,
                isStatic: false,
                isInterface: false,
                isAbstract: false
            )
            let null = try b.constant(.null, marker)
            b.instructions.append(.foreignCall(target, receiver: object, arguments: variables + [defaults, null], result: nil))
        } else {
            b.instructions.append(.foreignCall(primaryMethod, receiver: object, arguments: variables, result: nil))
        }
        b.instructions.append(.returnValue(object))
        return serialFinish(b, access: 0x11)
    }

    private func companionSerializerMethod(_ companion: JVMClassPlan, _ owner: JVMClassPlan) throws -> JVMFunction {
        guard let serialization = serializationPlan(for: owner) else {
            throw JVMFrontendError(message: "Missing JVM serialization plan.", range: owner.declaration?.range)
        }
        let b = try nominalBuilder(companion, name: "serializer", result: Self.kSerializerType)
        let instanceType = JVMValueType.reference(serializerClassName(owner), nullable: false)
        let field = JVMField(owner: serializerClassName(owner), name: "INSTANCE", type: instanceType, access: 0x19)
        let loaded = try b.value(instanceType)
        b.instructions.append(.getStatic(field, loaded))
        let converted = try b.convert(loaded, to: Self.kSerializerType)
        b.instructions.append(.returnValue(converted))
        var function = serialFinish(b, access: 0x11)
        guard let signature = sema.symbols.functionSignature(for: serialization.serializerSymbol) else { return function }
        function = try describe(function, signature: signature, parameters: [])
        function.genericSignature = "()Lkotlinx/serialization/KSerializer<L" + owner.name + ";>;"
        return function
    }
}
