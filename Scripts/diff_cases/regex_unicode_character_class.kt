// KUU-4073: JVM treats \w / \W / \d / \D / \s / \S / \b / \B as ASCII-only
// unless UNICODE_CHARACTER_CLASS ((?U)) is in effect. ICU (the backing regex
// engine) is Unicode-aware by default, so the runtime must translate the
// predefined classes and the word-boundary assertions to match the JVM.

fun show(label: String, r: Regex, input: String) {
    println("$label=" + r.findAll(input).map { it.value }.toList())
}

fun showB(label: String, r: Regex, input: String) {
    println("$label=" + r.findAll(input).map { it.range.first }.toList())
}

fun main() {
    val s = "Kästner föo_9 ٣ あ x́ ©  x"

    // Default (ASCII) predefined classes.
    show("w", Regex("\\w+"), s)
    show("W", Regex("\\W+"), s)
    show("d", Regex("\\d+"), s)
    show("D", Regex("\\D+"), s)
    show("ws", Regex("\\s+"), s)
    show("S", Regex("\\S+"), s)
    show("cls_w", Regex("[\\w]+"), s)
    show("cls_nw", Regex("[^\\w]+"), s)
    show("cls_W", Regex("[\\W]+"), s)
    show("cls_D", Regex("[\\D]+"), s)
    show("cls_S", Regex("[\\S]+"), s)

    // Default (ASCII) word boundaries.
    showB("b", Regex("\\b"), "Kästner")
    showB("B", Regex("\\B"), "Kästner")
    show("bcatb", Regex("\\bcat\\b"), "a.cat cat")
    println("matches_w=" + Regex("\\w+").matches("Kästner"))
    println("matches_allw=" + Regex("\\w+").matches("abc_9"))
    println("find_w=" + Regex("\\w+").find("Kästner")?.value)
    println("replace=" + "Kästner xy".replace(Regex("\\w+"), "#"))
    println("split=" + "a1b2é".split(Regex("\\d")).joinToString("|"))
    println("contains=" + Regex("\\w").containsMatchIn("é"))
    println("matchAt=" + Regex("\\w+").matchAt("aé", 0)?.value)

    // (?U) enables Unicode-aware classes, scoped and bare, with (?-U) opting
    // back out mid-pattern.
    show("U_w", Regex("(?U)\\w+"), s)
    show("U_W", Regex("(?U)\\W+"), s)
    show("U_d", Regex("(?U)\\d+"), s)
    show("U_s", Regex("(?U)\\s+"), s)
    showB("U_b", Regex("(?U)\\b"), "Kästner")
    showB("U_B", Regex("(?U)\\B"), "Kästner")
    show("U_bcatb", Regex("(?U)\\bcat\\b"), "a.cat cat")
    show("Ug_w", Regex("(?U:\\w+)"), s)
    show("mix_w", Regex("(?U)\\w+ x(?-U)\\w+"), "ä xé")
    show("Ug_mixed", Regex("\\w+ (?U:\\w+) \\w+"), "a é b ü")
    show("nest", Regex("[\\w&&[^xz]]+"), "axzby")

    // java.util.regex.Pattern.UNICODE_CHARACTER_CLASS behaves like a leading
    // (?U) and implies UNICODE_CASE (flags() reports 0x100 | 0x40 = 320).
    val jpattern = java.util.regex.Pattern.compile("\\w+", java.util.regex.Pattern.UNICODE_CHARACTER_CLASS)
    val jmatcher = jpattern.matcher(s)
    val jfound = mutableListOf<String>()
    while (jmatcher.find()) jfound.add(jmatcher.group())
    println("jpattern_U_w=$jfound")
    println("jpattern_flags=" + jpattern.flags())

    // Non-breaking/figure spaces: excluded from default \s, included under (?U).
    show("s_nbsp", Regex("\\s"), "\u00A0")
    show("U_s_nbsp", Regex("(?U)\\s"), "\u00A0")
    show("s_2007", Regex("\\s"), "\u2007")
    show("U_s_2007", Regex("(?U)\\s"), "\u2007")
}
