// DIFF_JVM
// KUU-4148: JVM treats the POSIX \p{Name} classes (\p{Lower} \p{Upper}
// \p{ASCII} \p{Alpha} \p{Digit} \p{Alnum} \p{Punct} \p{Graph} \p{Print}
// \p{Blank} \p{Cntrl} \p{XDigit} \p{Space}) as US-ASCII-only unless
// UNICODE_CHARACTER_CLASS ((?U)) is in effect. ICU (the backing regex
// engine) resolves \p{Name} against Unicode properties by default, so the
// runtime rewrites them to explicit ASCII classes while ASCII mode is active
// and passes them through under (?U), where ICU's UTS#18 compatibility
// properties match the JVM.
//
// ICU's `[:name:]` / `[.x.]` / `[=x=]` set operators have no java.util.regex
// counterpart: the JVM reads the inner `[` as an ordinary nested class of
// literal members, so the operator's second character is escaped
// (`[[:alpha:]]` matches `:alpha:` literally on both engines).
//
// Also covered: unbraced `\pL`-style single-letter categories, which the JVM
// accepts for exactly L M N P S Z C and ICU rejects unless braced.

fun show(label: String, r: Regex, input: String) {
    println(label + "=" + r.findAll(input).map { it.value }.toList())
}

fun check(label: String, r: Regex, input: String) {
    println(label + "=" + r.matches(input))
}

fun main() {
    val s = "AbCäü9 ٣中xY_!.«»\t "
    // NEL (Cc), NBSP (Zs) and FIGURE SPACE (Zs) are built explicitly so they
    // stay visible in the source instead of as raw control/space characters.
    val nel = "a" + 133.toChar() + "b"
    val hexs = "aFg9 Ｆｆ９"
    val sp = "q\tw\ne" + 133.toChar() + "f" + 160.toChar() + "g" + 8199.toChar() + "h"

    // Default (ASCII) POSIX classes.
    show("Lower", Regex("\\p{Lower}+"), s)
    show("Upper", Regex("\\p{Upper}+"), s)
    show("ASCII", Regex("\\p{ASCII}+"), s)
    show("Alpha", Regex("\\p{Alpha}+"), s)
    show("Digit", Regex("\\p{Digit}+"), s)
    show("Alnum", Regex("\\p{Alnum}+"), s)
    show("Punct", Regex("\\p{Punct}+"), s)
    show("Graph", Regex("\\p{Graph}+"), s)
    show("Print", Regex("\\p{Print}+"), s)
    show("Blank", Regex("\\p{Blank}+"), s)
    show("Cntrl", Regex("\\p{Cntrl}+"), nel)
    show("XDigit", Regex("\\p{XDigit}+"), hexs)
    show("Space", Regex("\\p{Space}+"), sp)

    // (?U) restores Unicode semantics; ICU's \p{Name} compatibility
    // properties match the JVM definitions (Lt excluded from Lower/Upper,
    // Cntrl = gc=Cc, Blank = TAB + Zs, Space = White_Space).
    show("U_Lower", Regex("(?U)\\p{Lower}+"), s)
    show("U_Upper", Regex("(?U)\\p{Upper}+"), s)
    show("U_ASCII", Regex("(?U)\\p{ASCII}+"), s)
    show("U_Alpha", Regex("(?U)\\p{Alpha}+"), s)
    show("U_Digit", Regex("(?U)\\p{Digit}+"), s)
    show("U_Alnum", Regex("(?U)\\p{Alnum}+"), s)
    show("U_Punct", Regex("(?U)\\p{Punct}+"), s)
    show("U_Graph", Regex("(?U)\\p{Graph}+"), s)
    show("U_Print", Regex("(?U)\\p{Print}+"), s)
    show("U_Blank", Regex("(?U)\\p{Blank}+"), s)
    show("U_Cntrl", Regex("(?U)\\p{Cntrl}+"), nel)
    show("U_XDigit", Regex("(?U)\\p{XDigit}+"), hexs)
    show("U_Space", Regex("(?U)\\p{Space}+"), sp)

    // Complements \P{Name}.
    show("P_Lower", Regex("\\P{Lower}+"), s)
    show("P_Punct", Regex("\\P{Punct}+"), s)
    show("P_Space", Regex("\\P{Space}+"), sp)
    show("U_P_Lower", Regex("(?U)\\P{Lower}+"), s)

    // Inside character classes: nested union, negation, intersection, and
    // adjacency where `-` stays literal.
    show("cls_Lower", Regex("[\\p{Lower}]+"), s)
    show("cls_nLower", Regex("[^\\p{Lower}]+"), s)
    show("cls_Lower_u", Regex("[\\p{Lower}_]+"), s)
    show("cls_U_Lower", Regex("(?U)[\\p{Lower}]+"), s)
    show("cls_isect", Regex("[\\p{Alpha}&&\\p{Lower}]+"), s)
    show("cls_P", Regex("[\\P{Lower}]+"), s)
    show("cls_nPunct", Regex("[^\\p{Punct}]+"), s)
    show("cls_range", Regex("[\\p{Lower}-~]+"), "a-zä")

    // `[:name:]` / `[.x.]` / `[=x=]` are literal nested classes on the JVM.
    show("posix_alpha", Regex("[[:alpha:]]+"), "AbCäü")
    check("posix_lbr", Regex("[[:alpha:]]"), "[")
    check("posix_a2", Regex("[[:alpha:]]"), "a]")
    check("posix_colon", Regex("[[:alpha:]]"), ":")
    check("posix_A", Regex("[[:alpha:]]"), "A")
    show("posix_lower", Regex("[[:lower:]]+"), "AbCäü")
    show("posix_mixed", Regex("[x[:digit:]y]+"), "x5y-")
    show("posix_neg", Regex("[^[:alpha:]]+"), "Ab9 Cä")
    show("U_posix", Regex("(?U)[[:alpha:]]+"), "AbCäü")
    show("posix_negcaret", Regex("[[:^alpha:]0-9]+"), "Ab9 Cä")
    show("posix_extra", Regex("[[:alpha:]x]+"), ":xa")
    show("posix_eq", Regex("[[=a=]]+"), "a=b:é")
    show("posix_coll", Regex("[[.a.]]+"), "a.b:é")

    // Unbraced single-letter categories \pL / \PL (JVM accepts L M N P S Z C).
    show("pL", Regex("\\pL+"), "aB中9")
    show("pN", Regex("\\pN+"), "a9５")
    show("PL", Regex("\\PL+"), "aB中9")
    show("pLC", Regex("\\pLC+"), "aǅC")

    // Unicode categories/scripts are untouched by the ASCII rewrite.
    show("Lu", Regex("\\p{Lu}+"), "AbCäü中")
    show("L", Regex("\\p{L}+"), "AbCäü中9")
    show("InGreek", Regex("\\p{InGreek}+"), "αβ中")

    // (?U) scoping: bare flag ends at the enclosing group, scoped group
    // restores, (?-U) opts back out.
    show("U_scoped", Regex("\\p{Lower}+ (?U:\\p{Lower}+) \\p{Lower}+"), "ab ü cd")
    show("U_off", Regex("(?U)\\p{Lower}+ (?-U)\\p{Lower}+"), "äü aB")
    show("U_bare_grp", Regex("(x(?U)\\p{Lower}) \\p{Lower}"), "xä b")

    // Whole-match / replace / split and \Q...\E quoting.
    check("me", Regex("\\p{Lower}+"), "abc")
    check("me2", Regex("\\p{Lower}+"), "äbc")
    println("replace=" + "AbCäü".replace(Regex("\\p{Alpha}"), "#"))
    println("split=" + "a1b٢c".split(Regex("\\p{Digit}")).joinToString("|"))
    println("contains=" + Regex("\\p{Lower}").containsMatchIn("ÄÖÜ"))
    println("findAt=" + (Regex("\\p{Digit}+").find("a٣b9")?.value ?: "null"))
    show("qd", Regex("\\Q\\p{Lower}\\E"), "p{L}")
}
