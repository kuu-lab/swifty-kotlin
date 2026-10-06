extension TokenKind {
    /// Kotlin labels use simpleIdentifier, including contextual and modifier keywords.
    var isLabelName: Bool {
        switch self {
        case .identifier, .backtickedIdentifier:
            true
        case let .softKeyword(keyword):
            keyword != .when
        case let .keyword(keyword):
            switch keyword {
            case .abstract, .annotation, .catch, .companion, .constructor, .crossinline,
                 .data, .dynamic, .enum, .external, .final, .finally, .import, .infix,
                 .inline, .inner, .internal, .lateinit, .noinline, .open, .operator,
                 .override, .private, .protected, .public, .reified, .sealed, .tailrec,
                 .vararg, .expect, .actual, .const, .suspend, .value:
                true
            default:
                false
            }
        default:
            false
        }
    }
}
