import Foundation

public struct DiagnosticTextEdit: Hashable, Sendable {
    /// An empty range represents insertion.
    public let range: SourceRange
    /// The replacement text, or an empty string for deletion.
    public let newText: String

    public init(range: SourceRange, newText: String) {
        self.range = range
        self.newText = newText
    }
}

public struct DiagnosticCodeAction: Hashable, Sendable {
    public let title: String
    /// LSP code action kind (e.g. "quickfix", "refactor").
    public let kind: String
    public let edits: [DiagnosticTextEdit]

    public init(
        title: String,
        kind: String = "quickfix",
        edits: [DiagnosticTextEdit] = []
    ) {
        self.title = title
        self.kind = kind
        self.edits = edits
    }
}

struct DiagnosticDescriptor: Equatable, Sendable, CustomStringConvertible {
    let code: String
    let pass: String
    let defaultSeverity: DiagnosticSeverity
    let summary: String
    let codeActions: [DiagnosticCodeAction]

    var description: String {
        return "[\(code)] \(defaultSeverity): \(summary)"
    }

    init(
        code: String,
        pass: String,
        defaultSeverity: DiagnosticSeverity,
        summary: String,
        codeActions: [DiagnosticCodeAction] = []
    ) {
        self.code = code
        self.pass = pass
        self.defaultSeverity = defaultSeverity
        self.summary = summary
        self.codeActions = codeActions
    }
}

/// Every diagnostic follows the `KSWIFTK-{PASS}-{CODE}` naming convention where
/// `{PASS}` identifies the compiler pass (LEX, PARSE, SEMA, TYPE, LIB, KIR,
/// CORO, BACKEND, LINK, PIPELINE, ICE) and `{CODE}` is a numeric or mnemonic
/// identifier unique within that pass.
enum DiagnosticRegistry {
    static let descriptors: [String: DiagnosticDescriptor] = {
        var map: [String: DiagnosticDescriptor] = [:]
        for descriptor in allDescriptors {
            map[descriptor.code] = descriptor
        }
        return map
    }()

    static func lookup(_ code: String) -> DiagnosticDescriptor? {
        descriptors[code]
    }

    static func suppressionCodes(for requestedCode: String) -> [String] {
        let normalized = requestedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return []
        }
        let upper = normalized.uppercased()
        var expanded: Set<String> = [normalized]
        if let aliases = suppressionAliases[normalized] {
            expanded.formUnion(aliases)
        }
        if let aliases = suppressionAliases[upper] {
            expanded.formUnion(aliases)
        }
        return expanded.sorted()
    }

    /// Severity constraint for a user-facing suppression name, or nil when the
    /// name suppresses the expanded codes at any severity. kotlinc keeps
    /// DEPRECATION (warning-level) and DEPRECATION_ERROR (error-level) as
    /// separate diagnostics, so `DEPRECATION` must not silence an error-level
    /// deprecation and `DEPRECATION_ERROR` must not silence a warning-level one.
    static func suppressionSeverityConstraint(for requestedCode: String) -> DiagnosticSeverity? {
        let normalized = requestedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return suppressionSeverityConstraints[normalized]
            ?? suppressionSeverityConstraints[normalized.uppercased()]
    }

    private static let suppressionSeverityConstraints: [String: DiagnosticSeverity] = [
        "DEPRECATION": .warning,
        "DEPRECATION_ERROR": .error,
        // kotlinc K2 splits the "check for instance is always 'false'"
        // diagnostic by severity: IMPOSSIBLE_IS_CHECK_ERROR is raised when the
        // subject's declared type is incompatible with the target, while
        // IMPOSSIBLE_IS_CHECK_WARNING covers checks that are impossible only
        // under a smart-cast type. Each name suppresses only its severity.
        "IMPOSSIBLE_IS_CHECK_ERROR": .error,
        "IMPOSSIBLE_IS_CHECK_DEPRECATION_ERROR": .error,
        "IMPOSSIBLE_IS_CHECK_WARNING": .warning,
        "IMPOSSIBLE_IS_CHECK_DEPRECATION": .warning,
    ]

    private static let suppressionAliases: [String: [String]] = [
        "UPPER_BOUND_VIOLATED_IN_TYPE_OPERATOR_OR_PARAMETER_BOUNDS_WARNING": ["KSWIFTK-SEMA-BOUND"],
        "UPPER_BOUND_VIOLATED_IN_TYPE_OPERATOR_OR_PARAMETER_BOUNDS_ERROR": ["KSWIFTK-SEMA-BOUND"],
        "UNCHECKED_CAST": ["KSWIFTK-SEMA-UNCHECKED-CAST"],
        // kotlinc reports an impossible `is` check as IMPOSSIBLE_IS_CHECK_ERROR
        // (the pre-2.4 name was IMPOSSIBLE_IS_CHECK_DEPRECATION). The K1 name
        // INCOMPATIBLE_TYPES deliberately does not map here: kotlinc does not
        // let it suppress IMPOSSIBLE_IS_CHECK_ERROR.
        "IMPOSSIBLE_IS_CHECK_ERROR": ["KSWIFTK-SEMA-0415"],
        "IMPOSSIBLE_IS_CHECK_DEPRECATION_ERROR": ["KSWIFTK-SEMA-0415"],
        "IMPOSSIBLE_IS_CHECK_WARNING": ["KSWIFTK-SEMA-0415"],
        "IMPOSSIBLE_IS_CHECK_DEPRECATION": ["KSWIFTK-SEMA-0415"],
        "INVISIBLE_MEMBER": ["KSWIFTK-SEMA-0040", "KSWIFTK-SEMA-0041", "KSWIFTK-SEMA-0044"],
        "INVISIBLE_REFERENCE": ["KSWIFTK-SEMA-0040", "KSWIFTK-SEMA-0041", "KSWIFTK-SEMA-0044"],
        "NON_PUBLIC_CALL_FROM_PUBLIC_INLINE": ["KSWIFTK-SEMA-0045"],
        "PROTECTED_CALL_FROM_PUBLIC_INLINE": ["KSWIFTK-SEMA-0045"],
        "DEPRECATION": ["KSWIFTK-SEMA-DEPRECATED"],
        "DEPRECATION_ERROR": ["KSWIFTK-SEMA-DEPRECATED"],
        "API_VERSION": ["KSWIFTK-SEMA-API-VERSION"],
        "OPT_IN_USAGE": ["KSWIFTK-SEMA-OPT-IN"],
        "UNCHECKED_IS": ["KSWIFTK-SEMA-ERASED-TYPE"],
        "CANNOT_CHECK_FOR_ERASED": ["KSWIFTK-SEMA-ERASED-TYPE"],
        "ANNOTATION_TARGET": ["KSWIFTK-SEMA-ANNOTATION-TARGET"],
        "NON_REPEATABLE_ANNOTATION": ["KSWIFTK-SEMA-ANNOTATION-NOT-REPEATABLE"],
        "ANNOTATION_ARGUMENT_MUST_BE_CONST": ["KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST"],
        "ARGUMENT_TYPE_MISMATCH": ["KSWIFTK-SEMA-ANNOTATION-ARGUMENT-TYPE"],
        "TOO_MANY_ARGUMENTS": ["KSWIFTK-SEMA-ANNOTATION-ARGUMENT-ARITY"],
        "NO_VALUE_FOR_PARAMETER": ["KSWIFTK-SEMA-ANNOTATION-ARGUMENT-ARITY"],
        "DATA_CLASS_COPY_VISIBILITY": ["KSWIFTK-SEMA-DATA-COPY-VISIBILITY"],
        // kotlinc gates local `inline` functions behind this diagnostic name;
        // the local-function modifier check reports it as KSWIFTK-SEMA-0400.
        "NOT_YET_SUPPORTED_LOCAL_INLINE_FUNCTION": ["KSWIFTK-SEMA-0400"],
    ]


    static let lexDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0001",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Unterminated string literal.",
            codeActions: [DiagnosticCodeAction(title: "Close string literal with matching quote")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0002",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Unexpected character in input.",
            codeActions: [DiagnosticCodeAction(title: "Remove unexpected character")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0003",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Invalid numeric literal."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0004",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Unescaped line break in string literal."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0005",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Leading zeros are not allowed in integer literals."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0006",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Malformed number literal (overflow or bad format)."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0007",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "String template nesting exceeds the supported depth."
        ),
    ]


    static let parseDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0001",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected keyword in declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0002",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected declaration name.",
            codeActions: [DiagnosticCodeAction(title: "Insert placeholder name")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0003",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected name in package or import path."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0004",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0005",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected type name or alias name."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0006",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Unexpected token in declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0010",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected closing delimiter in statement."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0011",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Malformed statement."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0012",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expression nesting exceeds the maximum supported depth."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0013",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Structured syntax nesting exceeds the maximum supported depth."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0014",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected an identifier after '::'."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0015",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected ',' or ')' after call argument."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0016",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected 'catch' or 'finally' after 'try' block."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0017",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Imports are only allowed in the beginning of file."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0018",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Unexpected token after expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0019",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Unexpected '?' after declaration name."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0020",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected type after ':'."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0021",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "A for-loop variable cannot be declared with 'val' or 'var'."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0022",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected an argument."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0023",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expecting member name after '.'."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0024",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Unexpected token after type reference."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0025",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Top-level statements are only allowed in '.kts' script files."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0026",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected '}' to close block."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0027",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "The 'else' branch must be the last branch in a 'when' expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0028",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Malformed catch parameter declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0029",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expecting 'val' keyword in destructuring declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-TYPE-DEPTH",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Type nesting exceeds the maximum supported depth."
        ),
    ]


    static let semaDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0002",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "No matching overload found for call."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0003",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Ambiguous overload resolution."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0004",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Return type mismatch.",
            codeActions: [DiagnosticCodeAction(title: "Change return type annotation to match expression")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0005",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Missing return type annotation.",
            codeActions: [DiagnosticCodeAction(title: "Add explicit return type annotation")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0007",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Reserved bundled stdlib annotation used outside bundled stdlib."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0008",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Reserved external declaration used outside bundled stdlib."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0009",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Function declaration requires a body."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0013",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved reference in local scope."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0014",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type mismatch in assignment or initialization.",
            codeActions: [DiagnosticCodeAction(title: "Add explicit type cast")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0018",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply unary operator to operand type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0019",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply binary operator to operand types."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0021",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Duplicate declaration in scope."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0022",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved reference.",
            codeActions: [DiagnosticCodeAction(title: "Check spelling or add import for symbol")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0023",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved type reference."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0024",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved member function call."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-UNRESOLVED-IMPORT",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved import path."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0025",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type mismatch in argument."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0026",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0027",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot import on demand from an object."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0031",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Null safety violation on non-nullable type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0032",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Incompatible types in when-branch condition."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0033",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "An explicit type is required on a local function value parameter."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0040",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot access private member.",
            codeActions: [DiagnosticCodeAction(title: "Change visibility to 'internal'")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0041",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot access protected member.",
            codeActions: [DiagnosticCodeAction(title: "Change visibility to 'public'")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0430",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Worker.execute requires a non-capturing job."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0431",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'infix' modifier is inapplicable to this function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0042",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid operator application."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0044",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot access internal member of the bundled stdlib."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0045",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Public-API inline function cannot access a non-public-API declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0050",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid is-check target type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0051",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid as-cast source type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0052",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid as-cast target type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0053",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unsafe cast requires 'as?' form."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0054",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid is-check on non-class type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0057",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'super' cannot be a callee."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-UNCHECKED-CAST",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Unchecked cast to a generic type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-ERASED-TYPE",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Cannot check for instance of erased generic type; type arguments are not available at runtime."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-DEPRECATED",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Reference to deprecated declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-API-VERSION",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Reference to an API unavailable in the selected Kotlin API version."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-OPT-IN",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Use of API that requires an explicit opt-in annotation."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-ANNOTATION-TARGET",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Annotation is not applicable to this declaration target."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-ANNOTATION-NOT-REPEATABLE",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Annotation is not repeatable."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-ARITY",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Annotation argument count does not match its constructor."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-TYPE",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Annotation argument has an incompatible type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Annotation argument is not a compile-time constant."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0061",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Conflicting member declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0062",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type parameter constraint violation."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0063",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot extract inner type from star projection."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0071",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Non-exhaustive when expression (missing branches)."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0072",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Redundant branch in when expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0073",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Unreachable branch in when expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0080",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const property not initialized with compile-time constant.",
            codeActions: [DiagnosticCodeAction(title: "Remove 'const' modifier")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0081",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const property must have an initializer."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0082",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const property must be of a primitive type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0083",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const val initializer must be a compile-time constant expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0084",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid use in constant context."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0085",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved exception type in catch clause."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0086",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Destructuring declaration requires componentN() operator."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0087",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Iterable element type does not support destructuring with componentN()."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0096",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Unnecessary safe call on non-nullable receiver."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0097",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply prefix operator to operand type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0098",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply postfix operator to operand type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0101",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Property in object literal must have a type annotation or initializer."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0102",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Synthetic stdlib stub duplicates a bundled Kotlin source declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0103",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Property delegate type is missing a 'getValue' operator function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0104",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Mutable property delegate type is missing a 'setValue' operator function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0105",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Callable references to properties with context parameters are unsupported."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-TAILREC",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Function marked 'tailrec' but last expression is not a self-recursive call."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-SUPER-CYCLE",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cyclic supertype reference detected during nominal layout synthesis."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-SUPER-DEPTH",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Inheritance chain exceeds the maximum supported depth."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-SUPER-COUNT",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Nominal type count exceeds the supported maximum."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0171",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Diamond inheritance conflict requires explicit override.",
            codeActions: [DiagnosticCodeAction(title: "Add explicit override to resolve diamond conflict")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-FIELD",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved member access.",
            codeActions: [DiagnosticCodeAction(title: "Check member name spelling")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-FINAL",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot override final member.",
            codeActions: [DiagnosticCodeAction(title: "Remove 'final' modifier from base declaration")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-INFER",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type inference constraint failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-OVERRIDE",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Missing 'override' keyword on overriding member.",
            codeActions: [DiagnosticCodeAction(title: "Add 'override' keyword")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-OVERRIDE-NOTHING",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Member marked 'override' does not override an inherited member."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-DATA-INHERIT",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot inherit from data class.",
            codeActions: [DiagnosticCodeAction(title: "Remove inheritance from data class")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-DATA-CTOR",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Primary constructor of data class must only have property ('val' / 'var') parameters."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Data class copy() visibility does not match a non-public primary constructor.",
            codeActions: [DiagnosticCodeAction(title: "Add '@ConsistentCopyVisibility'")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-REIFIED",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot use non-reified type parameter in reified context."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-BOUND",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type argument does not satisfy upper bound constraint."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0305",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type parameter's upper bounds combine two or more mutually exclusive class types."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0306",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Super-call omits an argument with a default value.",
            codeActions: [DiagnosticCodeAction(title: "Specify all arguments explicitly")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0307",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Infix notation requires the infix modifier."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0308",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Suspend function can only be called from a coroutine or another suspend function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0309",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Function accessed with property syntax requires invocation parentheses."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0310",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Restricted SequenceScope suspension requires the same receiver."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0311",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Returns are not allowed for functions with expression body."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0312",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Returns are not allowed in initializer blocks."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0313",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Suspend property can only be accessed from a coroutine or suspend function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-PLATFORM",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Platform-typed expression used without null check; may throw NullPointerException at runtime.",
            codeActions: [DiagnosticCodeAction(title: "Add null check before use")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-DSLMARKER",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "@DslMarker restriction: implicit access to outer receiver is prohibited when an inner receiver shares the same DSL marker."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0400",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Modifier is not applicable to this declaration kind."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0401",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Modifier is not applicable inside this declaration kind."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0402",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Two modifiers on the same declaration are mutually incompatible."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0403",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "const 'val' is only allowed on top level, in named objects, in companion objects or companion blocks."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0404",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Data class must have at least one primary constructor parameter."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0405",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Enum classes cannot extend classes."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0406",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Functional interface must have exactly one abstract function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0407",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Functional interface cannot have abstract properties."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0408",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Anonymous initializers in interfaces are prohibited."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0409",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Interfaces cannot have constructors."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0410",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "actual declaration has no corresponding expected declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0411",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid type of annotation member."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0412",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "There is a cycle in the delegation calls chain."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0413",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Catch parameter type is not a subtype of Throwable."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0414",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Throw operand type is not a subtype of Throwable."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0415",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Check for instance is always 'false' because the types are incompatible."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0416",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'operator' modifier is not applicable: illegal function name."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0417",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Constructors are not allowed for objects."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0418",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'lateinit' modifier is allowed only on mutable properties."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0419",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Members are prohibited in annotation classes."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0420",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Value class can be only final."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0421",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'val' keyword is missing in annotation parameter."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0422",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Value class cannot be local or inner."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0423",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Value class primary constructor must only have final read-only ('val') property parameters."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0424",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Property must be initialized or be abstract."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0425",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Extension property must have accessors or be abstract."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0426",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Function is declared without a body where a body is required."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0427",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "An annotation parameter cannot be 'var'."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0428",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Abstract members in interfaces cannot be private."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0429",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Declaration kind cannot be local."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0432",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Operator convention call requires the 'operator' modifier on the convention function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0433",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Lambda parameter count does not match the expected function type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0434",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'if' used as an expression must have an 'else' branch."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0435",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "A declaration can have only one companion object."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0436",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Conflicting type parameter declarations."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0438",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "An interface cannot extend a class."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0439",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "An inner-class supertype requires a receiver of the containing class."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0440",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "An enclosing this of a non-inner class cannot back an inner-class supertype."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0441",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Multiple vararg parameters are prohibited."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0442",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Generated data class componentN() conflicts with a supertype member."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0443",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Variance annotations are only allowed for type parameters of classes and interfaces."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0444",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'val' and 'var' parameters are only allowed in primary constructors."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0445",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type constraints are not allowed when no type parameters are declared."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0446",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "A data class componentN() conflicts with a user-declared member."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0447",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "A comma-separated list of conditions in a when branch cannot have a guard."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0448",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "When branch guards are only allowed in 'when' with a subject."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0449",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Illegal usage of an inline function parameter that is not 'noinline'."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0450",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "An inline parameter cannot be inlined in a context where non-local returns are not allowed."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0451",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Declaration kind is prohibited here."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0448",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Modifier is repeated."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0449",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Modifier is only allowed for function parameters of an inline function."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0450",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Primary constructor properties cannot be abstract."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0451",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'expect' declaration cannot be private."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0452",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'expect' declaration cannot have a body."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0453",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'expect' property cannot have an initializer."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0454",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "'expect' property cannot be delegated."
        ),
    ]


    static let typeDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-TYPE-0003",
            pass: "TYPE",
            defaultSeverity: .error,
            summary: "Unresolved type in declaration."
        ),
    ]


    static let libDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0001",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library metadata format version mismatch."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0002",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Inline function body not available from library."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0003",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library layout field not found."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0004",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library layout size mismatch."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0005",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library layout hint ignored."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0007",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Imported library symbol not resolved."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0010",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: unresolvable import."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0011",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: module not found."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0012",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: metadata parse failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0013",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: symbol conflict."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0014",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library discovery: partial metadata."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0015",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library search path not found."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0016",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library discovery: search path warning."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0025",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Kotlin .klib container is unreadable."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0026",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Kotlin .klib manifest is missing or invalid."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0027",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Kotlin .klib version is unsupported."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0028",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Kotlin .klib recognized; declaration import pending."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0029",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Kotlin .klib body contains unsupported serialized IR."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0030",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Kotlin .klib dependency missing from the library search path."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0031",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Duplicate library declaration ignored; first on the search path wins."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0035",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Stdlib artifact was built for a different --profile than this compilation uses."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0036",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Import refers to a stdlib package excluded from the minimal profile."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0032",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "A deferred inline body could not be registered into the stdlib Sema snapshot."
        ),
    ]


    static let kirDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-KIR-0001",
            pass: "KIR",
            defaultSeverity: .warning,
            summary: "KIR generation encountered unsupported construct."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-KIR-0002",
            pass: "KIR",
            defaultSeverity: .error,
            summary: "emitDelegateInit called for a property without a delegate expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-KIR-0003",
            pass: "KIR",
            defaultSeverity: .error,
            summary: "KIR verifier detected a malformed function body."
        ),
    ]


    static let coroDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-CORO-0001",
            pass: "CORO",
            defaultSeverity: .error,
            summary: "Suspend function call outside coroutine context."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-CORO-0002",
            pass: "CORO",
            defaultSeverity: .error,
            summary: "Invalid coroutine state transition."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-CORO-0003",
            pass: "CORO",
            defaultSeverity: .error,
            summary: "Coroutine lowering failure."
        ),
    ]


    static let inlDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-INL-0001",
            pass: "INL",
            defaultSeverity: .error,
            summary: "Mandatory inline expansion left an unexpanded call to a bodyless callee."
        ),
    ]


    static let backendDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-1006",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "LLVM backend emission failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-1007",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "LLVM backend bindings unavailable."
        ),
    ]


    static let linkDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-LINK-0001",
            pass: "LINK",
            defaultSeverity: .error,
            summary: "Linker invocation failed."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LINK-0002",
            pass: "LINK",
            defaultSeverity: .error,
            summary: "Link input not available."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LINK-0004",
            pass: "LINK",
            defaultSeverity: .error,
            summary: "Generated object file missing before link."
        ),
    ]


    static let pipelineDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0001",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Compiler pipeline failed while loading input sources."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0002",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Compiler pipeline received invalid intermediate state."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0003",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Compiler pipeline could not produce requested output."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0004",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Codegen phase failed to emit requested artifacts."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0005",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Per-file diagnostic limit reached; further diagnostics were suppressed."
        ),
    ]


    static let iceDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-ICE-0001",
            pass: "ICE",
            defaultSeverity: .error,
            summary: "Internal compiler error."
        ),
    ]


    static let sourceDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-SOURCE-0001",
            pass: "SOURCE",
            defaultSeverity: .error,
            summary: "No input files were specified."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SOURCE-0002",
            pass: "SOURCE",
            defaultSeverity: .error,
            summary: "Cannot read input file."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SOURCE-0101",
            pass: "SOURCE",
            defaultSeverity: .error,
            summary: "Bundled stdlib resource directory is missing."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SOURCE-0102",
            pass: "SOURCE",
            defaultSeverity: .error,
            summary: "Failed to read bundled stdlib source."
        ),
    ]


    static let allDescriptors: [DiagnosticDescriptor] =
        lexDescriptors
            + parseDescriptors
            + semaDescriptors
            + typeDescriptors
            + libDescriptors
            + kirDescriptors
            + inlDescriptors
            + coroDescriptors
            + backendDescriptors
            + linkDescriptors
            + pipelineDescriptors
            + iceDescriptors
            + sourceDescriptors
}
