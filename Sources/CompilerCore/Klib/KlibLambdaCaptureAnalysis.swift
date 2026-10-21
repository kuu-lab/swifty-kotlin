/// Find lexical captures in serialized lambda bodies, including references
/// used only by a nested lambda. Signature indices are unique within a file;
/// intersecting with the outer bindings excludes the lambda's own locals.
package struct KlibLambdaCaptureAnalysis {
    private let module: KlibIrModule
    private let fileIndex: Int
    private let available: Set<Int>
    private var visitedBodies: Set<Int32> = []
    private var references: Set<Int> = []

    package static func captures(
        of function: KlibFunction, module: KlibIrModule, fileIndex: Int, available: Set<Int>
    ) throws -> [Int] {
        var analysis = Self(module: module, fileIndex: fileIndex, available: available)
        try analysis.visitFunction(function.base)
        return analysis.references.sorted()
    }

    private mutating func visitBody(_ index: Int32?) throws {
        guard let index, visitedBodies.insert(index).inserted else { return }
        try visitStatement(module.body(index, fileIndex: fileIndex))
    }

    private mutating func visitExpressionBody(_ index: Int32?) throws {
        guard let index, visitedBodies.insert(index).inserted else { return }
        try visit(module.expressionBody(index, fileIndex: fileIndex))
    }

    private mutating func visitFunction(_ function: KlibFunctionBase) throws {
        try visitBody(function.bodyIndex)
    }

    private mutating func visitDeclaration(_ declaration: KlibIrDeclaration) throws {
        switch declaration {
        case .variable(let variable): try visitOptional(variable.initializer)
        case .function(let function): try visitFunction(function.base)
        case .constructor(let constructor): try visitFunction(constructor.base)
        case .class(let klass):
            for member in klass.declarations { try visitDeclaration(member) }
        case .field(let field): try visitExpressionBody(field.initializerIndex)
        case .anonymousInit(let initializer): try visitBody(initializer.bodyIndex)
        case .property(let property):
            if let field = property.backingField { try visitExpressionBody(field.initializerIndex) }
            if let getter = property.getter { try visitFunction(getter.base) }
            if let setter = property.setter { try visitFunction(setter.base) }
        case .localDelegatedProperty(let property):
            if let delegate = property.delegate { try visitOptional(delegate.initializer) }
            if let getter = property.getter { try visitFunction(getter.base) }
            if let setter = property.setter { try visitFunction(setter.base) }
        case .enumEntry, .typeParameter, .typeAlias, .valueParameter: break
        }
    }

    private mutating func visitStatement(_ statement: KlibIrStatement) throws {
        switch statement.kind {
        case .expression(let expression): try visit(expression)
        case .declaration(let declaration): try visitDeclaration(declaration)
        case .blockBody(let statements): try visitStatements(statements)
        case .branch(let condition, let result): try visit(condition); try visit(result)
        case .catch(let caught): try visit(caught.result)
        case .syntheticBody: break
        }
    }

    private mutating func visitStatements(_ statements: [KlibIrStatement]) throws {
        for statement in statements { try visitStatement(statement) }
    }

    private mutating func visitOptional(_ expression: KlibIrExpression?) throws {
        if let expression { try visit(expression) }
    }

    private mutating func visitAccess(_ access: KlibMemberAccess) throws {
        try visitOptional(access.dispatchReceiver)
        try visitOptional(access.extensionReceiver)
        for argument in access.arguments { try visit(argument) }
        for argument in access.argumentsPre240 + access.regularArguments { try visitOptional(argument) }
    }

    private mutating func record(_ reference: KlibSymbolRef) {
        if available.contains(reference.signatureIndex) { references.insert(reference.signatureIndex) }
    }

    private mutating func visit(_ expression: KlibIrExpression) throws {
        switch expression.kind {
        case .getValue(let reference, _): record(reference)
        case .setValue(let reference, let value, _): record(reference); try visit(value)
        case .call(_, let access, _, _), .constructorCall(_, _, let access, _),
             .delegatingConstructorCall(_, let access), .enumConstructorCall(_, let access),
             .functionReference(_, let access, _, _), .propertyReference(_, _, _, _, let access, _):
            try visitAccess(access)
        case .block(let statements, _), .composite(let statements, _), .when(let statements, _),
             .returnableBlock(_, let statements, _), .inlinedFunctionBlock(_, _, _, let statements, _, _, _):
            try visitStatements(statements)
        case .return(_, let value), .throw(let value), .getClass(let value), .typeOp(_, _, let value):
            try visit(value)
        case .getField(let access, _): try visitOptional(access.receiver)
        case .setField(let access, let value, _): try visitOptional(access.receiver); try visit(value)
        case .while(let loop), .doWhile(let loop):
            try visit(loop.condition); try visitOptional(loop.body)
        case .stringConcat(let values):
            for value in values { try visit(value) }
        case .try(let result, let catches, let finally):
            try visit(result); try visitStatements(catches); try visitOptional(finally)
        case .vararg(_, let elements):
            for element in elements {
                switch element {
                case .expression(let value), .spread(let value, _, _): try visit(value)
                }
            }
        case .functionExpression(let function, _): try visitFunction(function.base)
        case .richFunctionReference(let values, _, _, let function, _, _):
            for value in values { try visit(value) }
            try visitFunction(function.base)
        case .richPropertyReference(let values, _, let getter, let setter, _):
            for value in values { try visit(value) }
            try visitFunction(getter.base)
            if let setter { try visitFunction(setter.base) }
        case .dynamicMember(_, let receiver): try visit(receiver)
        case .dynamicOperator(_, let receiver, let arguments):
            try visit(receiver)
            for argument in arguments { try visit(argument) }
        case .errorCallExpression(_, let receiver, let arguments):
            try visitOptional(receiver)
            for argument in arguments { try visit(argument) }
        case .constNull, .constBool, .constChar, .constByte, .constShort, .constInt, .constLong,
             .constFloat, .constDouble, .constString, .getObject, .getEnumValue, .classReference,
             .break, .continue, .instanceInitializerCall, .localDelegatedPropertyReference,
             .errorExpression, .missingExpression:
            break
        }
    }
}
