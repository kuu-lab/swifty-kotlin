// KUU-4169: java.util.regex rejects \p{...} property names that ICU accepts
// — case variants (\p{lower}), ICU-only property keys (scx=, age=, ccc=, ...),
// bare binary property names (\p{Any}, \p{word}), and aliases
// (\p{sc=Old Italic}, \p{gc=Decimal_Number}). Kotlin Regex must reject them
// with the same accept/reject verdict as the JVM (PatternSyntaxException vs
// the runtime's IllegalArgumentException — both surface as a caught
// exception here, so only the verdict is compared).

fun probe(label: String, pattern: String) {
    try {
        val r = Regex(pattern)
        println(label + "=ok")
    } catch (e: Exception) {
        println(label + "=rejected")
    }
}

fun main() {
    // Case variants of the POSIX names: rejected by the JVM, accepted by ICU.
    probe("lower", "\\p{lower}+")
    probe("LOWER", "\\p{LOWER}")
    probe("lOWER", "\\p{lOWER}")
    probe("P_lower", "\\P{lower}")
    probe("upper", "\\p{upper}")
    probe("ascii", "\\p{ascii}")
    probe("alpha", "\\p{alpha}")
    probe("digit", "\\p{digit}")
    probe("islatin", "\\p{islatin}")
    probe("inGreek", "\\p{inGreek}")
    probe("cls_lower", "[\\p{lower}]")
    probe("gc_lu", "\\p{gc=lu}")
    probe("gc_LU", "\\p{gc=LU}")

    // Property keys java.util.regex does not know (ICU accepts them).
    probe("scx", "\\p{scx=Latn}")
    probe("age", "\\p{age=3.0}")
    probe("ccc", "\\p{ccc=0}")
    probe("nv", "\\p{nv=1}")
    probe("GCB", "\\p{GCB=XX}")
    probe("lb", "\\p{lb=XX}")
    probe("WB", "\\p{WB=XX}")
    probe("ea", "\\p{ea=F}")
    probe("scx_long", "\\p{Script_Extensions=Latin}")

    // Bare binary property names need the Is prefix on the JVM.
    probe("Any", "\\p{Any}")
    probe("any", "\\p{any}")
    probe("word", "\\p{word}")
    probe("Word", "\\p{Word}")
    probe("perl", "\\p{perl}")
    probe("join_control", "\\p{join_control}")
    probe("ids_binop", "\\p{IDS_Binary_Operator}")
    probe("cwu", "\\p{Changes_When_Uppercased}")
    probe("graph_lower", "\\p{graph}")
    probe("gc_decimal", "\\p{gc=Decimal_Number}")
    probe("sc_old_italic", "\\p{sc=Old Italic}")
    probe("is_basiclatin", "\\p{IsBasicLatin}")
    probe("blk_no_block", "\\p{blk=No_Block}")
    probe("in_no_block", "\\p{InNo_Block}")

    // Canonical names stay valid, including (?U) POSIX case variants and
    // Is/In/script/block/gc forms.
    probe("Lower", "\\p{Lower}+")
    probe("Lu", "\\p{Lu}+")
    probe("L", "\\p{L}+")
    probe("pL", "\\pL+")
    probe("InGreek", "\\p{InGreek}+")
    probe("IsLatin", "\\p{IsLatin}")
    probe("Islower", "\\p{Islower}")
    probe("IsAlphabetic", "\\p{IsAlphabetic}")
    probe("gc_Lu", "\\p{gc=Lu}")
    probe("gc_L", "\\p{gc=L}")
    probe("gc_LC", "\\p{gc=LC}")
    probe("gc_Nd", "\\p{gc=Nd}")
    probe("sc_Latin", "\\p{sc=Latin}")
    probe("sc_Ital", "\\p{sc=Ital}")
    probe("blk_basic", "\\p{blk=Basic Latin}")
    probe("U_lower", "(?U)\\p{lower}+")
    probe("U_LOWER", "(?U)\\p{LOWER}")
    probe("U_xdigit", "(?U)\\p{xdigit}")
    probe("U_mixed", "(?U:\\p{lower})x(?-U:\\p{Lower})")
    probe("quoted", "\\Q\\p{lower}\\E")
    probe("cls_IsLatin", "[\\p{IsLatin}]")

    // (?U) does not rescue names outside the 12 POSIX spellings, and flag
    // groups inside classes are literals.
    probe("U_word", "(?U)\\p{word}")
    probe("cls_U_lower", "[(?U)\\p{lower}]")
    probe("U_cls_lower", "(?U)[\\p{lower}]")

    // RegexOption.COMMENTS permits whitespace inside \p{...} on the JVM.
    try {
        Regex("\\p{ Lu}", RegexOption.COMMENTS)
        println("comments_opt=ok")
    } catch (e: Exception) {
        println("comments_opt=rejected")
    }
    probe("ws_name", "\\p{ Lu}")

    // Accepted names keep their match semantics.
    println("Lower_match=" + Regex("\\p{Lower}+").findAll("AbCäü").map { it.value }.toList())
    println("U_lower_match=" + Regex("(?U)\\p{lower}+").findAll("aéb").map { it.value }.toList())
    println("Lu_match=" + Regex("\\p{Lu}+").findAll("aBcD").map { it.value }.toList())
}
