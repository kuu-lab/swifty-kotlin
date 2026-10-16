/// Recognizes field initializers that write the value already supplied by a
/// freshly allocated instance.
enum KIRDefaultFieldInitializer {
    static func isDefaultValue(
        _ value: KIRExprKind,
        for fieldType: TypeID,
        types: TypeSystem
    ) -> Bool {
        let type = types.kind(of: fieldType)
        if case .null = value {
            return acceptsNullDefault(type)
        }

        guard case let .primitive(primitive, .nonNull) = type else {
            return false
        }
        return switch primitive {
        case .boolean:
            value == .boolLiteral(false)
        case .char:
            value == .charLiteral(0)
        case .byte, .short, .int:
            isSignedIntegerZero(value)
        case .long:
            isSignedIntegerZero(value)
        case .uint, .ulong, .ubyte, .ushort:
            isIntegerZero(value)
        case .float:
            isFloatZero(value)
        case .double:
            isDoubleZero(value)
        }
    }

    private static func acceptsNullDefault(_ type: TypeKind) -> Bool {
        switch type {
        case .nullableUnit, .platformUnit, .nothing(.nullable), .any(.nullable), .stringStruct(.nullable):
            true
        case let .primitive(_, nullability):
            nullability == .nullable
        case let .classType(classType):
            classType.nullability == .nullable
        case let .typeParam(typeParam):
            typeParam.nullability == .nullable
        case let .functionType(functionType):
            functionType.nullability == .nullable
        case let .kClassType(kClassType):
            kClassType.nullability == .nullable
        default:
            false
        }
    }

    private static func isSignedIntegerZero(_ value: KIRExprKind) -> Bool {
        switch value {
        case .intLiteral(0), .longLiteral(0): true
        default: false
        }
    }

    private static func isIntegerZero(_ value: KIRExprKind) -> Bool {
        switch value {
        case .intLiteral(0), .longLiteral(0), .uintLiteral(0), .ulongLiteral(0): true
        default: false
        }
    }

    private static func isFloatZero(_ value: KIRExprKind) -> Bool {
        switch value {
        case let .floatLiteral(number): Float(number).bitPattern == 0
        case let .doubleLiteral(number): Float(number).bitPattern == 0
        default: false
        }
    }

    private static func isDoubleZero(_ value: KIRExprKind) -> Bool {
        switch value {
        case let .floatLiteral(number): Double(Float(number)).bitPattern == 0
        case let .doubleLiteral(number): number.bitPattern == 0
        default: false
        }
    }
}
