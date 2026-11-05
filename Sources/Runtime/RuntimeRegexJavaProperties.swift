//
//  RuntimeRegexJavaProperties.swift
//  Runtime
//
//  KUU-4169: java.util.regex \p{...} property-name validation.
//
//  ICU (the engine behind NSRegularExpression) resolves \p{Name} far more
//  leniently than java.util.regex.Pattern: it accepts case variants
//  (`\p{lower}`), aliases (`\p{sc=Old Italic}`), binary property names
//  (`\p{Any}`, `\p{word}`), and extra property keys (`scx=`, `age=`, `ccc=`,
//  `nv=`, `GCB=`, `lb=`, `WB=`, `ea=`, ...) that the JVM rejects with
//  PatternSyntaxException. Kotlin's Regex therefore compiled patterns the JVM
//  refuses. `jvmRegexPropertyError` scans a pattern the way
//  java.util.regex.Pattern does — tracking inline flags, group scope,
//  character classes and \Q...\E quotes — and reports the first property
//  escape whose name the JVM would reject, so `compileRegexPattern` can fail
//  the same way (IllegalArgumentException) instead of delegating to ICU.
//
//  The accepted-name tables below mirror JDK 25's
//  java.util.regex.Pattern#family / CharPredicates / Character.UnicodeScript /
//  Character.UnicodeBlock:
//
//  * `jvmRegexPropertyNames` — `CharPredicates.forProperty`: general
//    categories, the 13 POSIX-style names, `all`, and `java*` predicates.
//    Matched case-sensitively.
//  * `jvmRegexPosixNames` — `getPosixPredicate`: the 12 names reachable via
//    `forPOSIXName` for bare `\p{Name}` under UNICODE_CHARACTER_CLASS, and
//    via `forUnicodeProperty` for `Is*` names. Uppercase-matched.
//  * `jvmRegexUnicodePropertyNames` — `getUnicodePredicate`: binary property
//    names reachable only through `Is*` / `forUnicodeProperty`.
//    Uppercase-matched.
//  * `jvmRegexScriptNames` — `Character.UnicodeScript.forName`: ISO 15924
//    aliases plus enum names (incl. UNKNOWN). Uppercase-matched.
//  * `jvmRegexBlockNames` — `Character.UnicodeBlock.forName`: every
//    registered alias spelling. Uppercase-matched.
//

import Foundation

private let jvmRegexPropertyNames: Set<String> = [
    "ASCII", "Alnum", "Alpha", "Blank", "C", "Cc",
    "Cf", "Cn", "Cntrl", "Co", "Cs", "Digit",
    "Graph", "L", "L1", "LC", "LD", "Ll",
    "Lm", "Lo", "Lower", "Lt", "Lu", "M",
    "Mc", "Me", "Mn", "N", "Nd", "Nl",
    "No", "P", "Pc", "Pd", "Pe", "Pf",
    "Pi", "Po", "Print", "Ps", "Punct", "S",
    "Sc", "Sk", "Sm", "So", "Space", "Upper",
    "XDigit", "Z", "Zl", "Zp", "Zs", "all",
    "javaAlphabetic", "javaDefined", "javaDigit", "javaISOControl", "javaIdentifierIgnorable", "javaIdeographic",
    "javaJavaIdentifierPart", "javaJavaIdentifierStart", "javaLetter", "javaLetterOrDigit", "javaLowerCase", "javaMirrored",
    "javaSpaceChar", "javaTitleCase", "javaUnicodeIdentifierPart", "javaUnicodeIdentifierStart", "javaUpperCase", "javaWhitespace",
]

private let jvmRegexPosixNames: Set<String> = [
    "ALNUM", "ALPHA", "BLANK", "CNTRL", "DIGIT", "GRAPH",
    "LOWER", "PRINT", "PUNCT", "SPACE", "UPPER", "XDIGIT",
]

private let jvmRegexUnicodePropertyNames: Set<String> = [
    "ALPHABETIC", "ASSIGNED", "CONTROL", "EMOJI", "EMOJI_COMPONENT", "EMOJI_MODIFIER",
    "EMOJI_MODIFIER_BASE", "EMOJI_PRESENTATION", "EXTENDED_PICTOGRAPHIC", "HEXDIGIT", "HEX_DIGIT", "IDEOGRAPHIC",
    "JOINCONTROL", "JOIN_CONTROL", "LETTER", "LOWERCASE", "NONCHARACTERCODEPOINT", "NONCHARACTER_CODE_POINT",
    "PUNCTUATION", "TITLECASE", "UPPERCASE", "WHITESPACE", "WHITE_SPACE", "WORD",
]

private let jvmRegexScriptNames: Set<String> = [
    "ADLAM", "ADLM", "AGHB", "AHOM", "ANATOLIAN_HIEROGLYPHS", "ARAB",
    "ARABIC", "ARMENIAN", "ARMI", "ARMN", "AVESTAN", "AVST",
    "BALI", "BALINESE", "BAMU", "BAMUM", "BASS", "BASSA_VAH",
    "BATAK", "BATK", "BENG", "BENGALI", "BHAIKSUKI", "BHKS",
    "BOPO", "BOPOMOFO", "BRAH", "BRAHMI", "BRAI", "BRAILLE",
    "BUGI", "BUGINESE", "BUHD", "BUHID", "CAKM", "CANADIAN_ABORIGINAL",
    "CANS", "CARI", "CARIAN", "CAUCASIAN_ALBANIAN", "CHAKMA", "CHAM",
    "CHER", "CHEROKEE", "CHORASMIAN", "CHRS", "COMMON", "COPT",
    "COPTIC", "CPMN", "CPRT", "CUNEIFORM", "CYPRIOT", "CYPRO_MINOAN",
    "CYRILLIC", "CYRL", "DESERET", "DEVA", "DEVANAGARI", "DIAK",
    "DIVES_AKURU", "DOGR", "DOGRA", "DSRT", "DUPL", "DUPLOYAN",
    "EGYP", "EGYPTIAN_HIEROGLYPHS", "ELBA", "ELBASAN", "ELYM", "ELYMAIC",
    "ETHI", "ETHIOPIC", "GARA", "GARAY", "GEOR", "GEORGIAN",
    "GLAG", "GLAGOLITIC", "GONG", "GONM", "GOTH", "GOTHIC",
    "GRAN", "GRANTHA", "GREEK", "GREK", "GUJARATI", "GUJR",
    "GUKH", "GUNJALA_GONDI", "GURMUKHI", "GURU", "GURUNG_KHEMA", "HAN",
    "HANG", "HANGUL", "HANI", "HANIFI_ROHINGYA", "HANO", "HANUNOO",
    "HATR", "HATRAN", "HEBR", "HEBREW", "HIRA", "HIRAGANA",
    "HLUW", "HMNG", "HMNP", "HUNG", "IMPERIAL_ARAMAIC", "INHERITED",
    "INSCRIPTIONAL_PAHLAVI", "INSCRIPTIONAL_PARTHIAN", "ITAL", "JAVA", "JAVANESE", "KAITHI",
    "KALI", "KANA", "KANNADA", "KATAKANA", "KAWI", "KAYAH_LI",
    "KHAR", "KHAROSHTHI", "KHITAN_SMALL_SCRIPT", "KHMER", "KHMR", "KHOJ",
    "KHOJKI", "KHUDAWADI", "KIRAT_RAI", "KITS", "KNDA", "KRAI",
    "KTHI", "LANA", "LAO", "LAOO", "LATIN", "LATN",
    "LEPC", "LEPCHA", "LIMB", "LIMBU", "LINA", "LINB",
    "LINEAR_A", "LINEAR_B", "LISU", "LYCI", "LYCIAN", "LYDI",
    "LYDIAN", "MAHAJANI", "MAHJ", "MAKA", "MAKASAR", "MALAYALAM",
    "MAND", "MANDAIC", "MANI", "MANICHAEAN", "MARC", "MARCHEN",
    "MASARAM_GONDI", "MEDEFAIDRIN", "MEDF", "MEETEI_MAYEK", "MEND", "MENDE_KIKAKUI",
    "MERC", "MERO", "MEROITIC_CURSIVE", "MEROITIC_HIEROGLYPHS", "MIAO", "MLYM",
    "MODI", "MONG", "MONGOLIAN", "MRO", "MROO", "MTEI",
    "MULT", "MULTANI", "MYANMAR", "MYMR", "NABATAEAN", "NAGM",
    "NAG_MUNDARI", "NAND", "NANDINAGARI", "NARB", "NBAT", "NEWA",
    "NEW_TAI_LUE", "NKO", "NKOO", "NSHU", "NUSHU", "NYIAKENG_PUACHUE_HMONG",
    "OGAM", "OGHAM", "OLCK", "OLD_HUNGARIAN", "OLD_ITALIC", "OLD_NORTH_ARABIAN",
    "OLD_PERMIC", "OLD_PERSIAN", "OLD_SOGDIAN", "OLD_SOUTH_ARABIAN", "OLD_TURKIC", "OLD_UYGHUR",
    "OL_CHIKI", "OL_ONAL", "ONAO", "ORIYA", "ORKH", "ORYA",
    "OSAGE", "OSGE", "OSMA", "OSMANYA", "OUGR", "PAHAWH_HMONG",
    "PALM", "PALMYRENE", "PAUC", "PAU_CIN_HAU", "PERM", "PHAG",
    "PHAGS_PA", "PHLI", "PHLP", "PHNX", "PHOENICIAN", "PLRD",
    "PRTI", "PSALTER_PAHLAVI", "REJANG", "RJNG", "ROHG", "RUNIC",
    "RUNR", "SAMARITAN", "SAMR", "SARB", "SAUR", "SAURASHTRA",
    "SGNW", "SHARADA", "SHAVIAN", "SHAW", "SHRD", "SIDD",
    "SIDDHAM", "SIGNWRITING", "SIND", "SINH", "SINHALA", "SOGD",
    "SOGDIAN", "SOGO", "SORA", "SORA_SOMPENG", "SOYO", "SOYOMBO",
    "SUND", "SUNDANESE", "SUNU", "SUNUWAR", "SYLO", "SYLOTI_NAGRI",
    "SYRC", "SYRIAC", "TAGALOG", "TAGB", "TAGBANWA", "TAI_LE",
    "TAI_THAM", "TAI_VIET", "TAKR", "TAKRI", "TALE", "TALU",
    "TAMIL", "TAML", "TANG", "TANGSA", "TANGUT", "TAVT",
    "TELU", "TELUGU", "TFNG", "TGLG", "THAA", "THAANA",
    "THAI", "TIBETAN", "TIBT", "TIFINAGH", "TIRH", "TIRHUTA",
    "TNSA", "TODHRI", "TODR", "TOTO", "TULU_TIGALARI", "TUTG",
    "UGAR", "UGARITIC", "UNKNOWN", "VAI", "VAII", "VITH",
    "VITHKUQI", "WANCHO", "WARA", "WARANG_CITI", "WCHO", "XPEO",
    "XSUX", "YEZI", "YEZIDI", "YI", "YIII", "ZANABAZAR_SQUARE",
    "ZANB", "ZINH", "ZYYY", "ZZZZ",
]

private let jvmRegexBlockNames: Set<String> = [
    "ADLAM", "AEGEAN NUMBERS", "AEGEANNUMBERS", "AEGEAN_NUMBERS", "AHOM", "ALCHEMICAL SYMBOLS",
    "ALCHEMICALSYMBOLS", "ALCHEMICAL_SYMBOLS", "ALPHABETIC PRESENTATION FORMS", "ALPHABETICPRESENTATIONFORMS", "ALPHABETIC_PRESENTATION_FORMS", "ANATOLIAN HIEROGLYPHS",
    "ANATOLIANHIEROGLYPHS", "ANATOLIAN_HIEROGLYPHS", "ANCIENT GREEK MUSICAL NOTATION", "ANCIENT GREEK NUMBERS", "ANCIENT SYMBOLS", "ANCIENTGREEKMUSICALNOTATION",
    "ANCIENTGREEKNUMBERS", "ANCIENTSYMBOLS", "ANCIENT_GREEK_MUSICAL_NOTATION", "ANCIENT_GREEK_NUMBERS", "ANCIENT_SYMBOLS", "ARABIC",
    "ARABIC EXTENDED-A", "ARABIC EXTENDED-B", "ARABIC EXTENDED-C", "ARABIC MATHEMATICAL ALPHABETIC SYMBOLS", "ARABIC PRESENTATION FORMS-A", "ARABIC PRESENTATION FORMS-B",
    "ARABIC SUPPLEMENT", "ARABICEXTENDED-A", "ARABICEXTENDED-B", "ARABICEXTENDED-C", "ARABICMATHEMATICALALPHABETICSYMBOLS", "ARABICPRESENTATIONFORMS-A",
    "ARABICPRESENTATIONFORMS-B", "ARABICSUPPLEMENT", "ARABIC_EXTENDED_A", "ARABIC_EXTENDED_B", "ARABIC_EXTENDED_C", "ARABIC_MATHEMATICAL_ALPHABETIC_SYMBOLS",
    "ARABIC_PRESENTATION_FORMS_A", "ARABIC_PRESENTATION_FORMS_B", "ARABIC_SUPPLEMENT", "ARMENIAN", "ARROWS", "AVESTAN",
    "BALINESE", "BAMUM", "BAMUM SUPPLEMENT", "BAMUMSUPPLEMENT", "BAMUM_SUPPLEMENT", "BASIC LATIN",
    "BASICLATIN", "BASIC_LATIN", "BASSA VAH", "BASSAVAH", "BASSA_VAH", "BATAK",
    "BENGALI", "BHAIKSUKI", "BLOCK ELEMENTS", "BLOCKELEMENTS", "BLOCK_ELEMENTS", "BOPOMOFO",
    "BOPOMOFO EXTENDED", "BOPOMOFOEXTENDED", "BOPOMOFO_EXTENDED", "BOX DRAWING", "BOXDRAWING", "BOX_DRAWING",
    "BRAHMI", "BRAILLE PATTERNS", "BRAILLEPATTERNS", "BRAILLE_PATTERNS", "BUGINESE", "BUHID",
    "BYZANTINE MUSICAL SYMBOLS", "BYZANTINEMUSICALSYMBOLS", "BYZANTINE_MUSICAL_SYMBOLS", "CARIAN", "CAUCASIAN ALBANIAN", "CAUCASIANALBANIAN",
    "CAUCASIAN_ALBANIAN", "CHAKMA", "CHAM", "CHEROKEE", "CHEROKEE SUPPLEMENT", "CHEROKEESUPPLEMENT",
    "CHEROKEE_SUPPLEMENT", "CHESS SYMBOLS", "CHESSSYMBOLS", "CHESS_SYMBOLS", "CHORASMIAN", "CJK COMPATIBILITY",
    "CJK COMPATIBILITY FORMS", "CJK COMPATIBILITY IDEOGRAPHS", "CJK COMPATIBILITY IDEOGRAPHS SUPPLEMENT", "CJK RADICALS SUPPLEMENT", "CJK STROKES", "CJK SYMBOLS AND PUNCTUATION",
    "CJK UNIFIED IDEOGRAPHS", "CJK UNIFIED IDEOGRAPHS EXTENSION A", "CJK UNIFIED IDEOGRAPHS EXTENSION B", "CJK UNIFIED IDEOGRAPHS EXTENSION C", "CJK UNIFIED IDEOGRAPHS EXTENSION D", "CJK UNIFIED IDEOGRAPHS EXTENSION E",
    "CJK UNIFIED IDEOGRAPHS EXTENSION F", "CJK UNIFIED IDEOGRAPHS EXTENSION G", "CJK UNIFIED IDEOGRAPHS EXTENSION H", "CJK UNIFIED IDEOGRAPHS EXTENSION I", "CJKCOMPATIBILITY", "CJKCOMPATIBILITYFORMS",
    "CJKCOMPATIBILITYIDEOGRAPHS", "CJKCOMPATIBILITYIDEOGRAPHSSUPPLEMENT", "CJKRADICALSSUPPLEMENT", "CJKSTROKES", "CJKSYMBOLSANDPUNCTUATION", "CJKUNIFIEDIDEOGRAPHS",
    "CJKUNIFIEDIDEOGRAPHSEXTENSIONA", "CJKUNIFIEDIDEOGRAPHSEXTENSIONB", "CJKUNIFIEDIDEOGRAPHSEXTENSIONC", "CJKUNIFIEDIDEOGRAPHSEXTENSIOND", "CJKUNIFIEDIDEOGRAPHSEXTENSIONE", "CJKUNIFIEDIDEOGRAPHSEXTENSIONF",
    "CJKUNIFIEDIDEOGRAPHSEXTENSIONG", "CJKUNIFIEDIDEOGRAPHSEXTENSIONH", "CJKUNIFIEDIDEOGRAPHSEXTENSIONI", "CJK_COMPATIBILITY", "CJK_COMPATIBILITY_FORMS", "CJK_COMPATIBILITY_IDEOGRAPHS",
    "CJK_COMPATIBILITY_IDEOGRAPHS_SUPPLEMENT", "CJK_RADICALS_SUPPLEMENT", "CJK_STROKES", "CJK_SYMBOLS_AND_PUNCTUATION", "CJK_UNIFIED_IDEOGRAPHS", "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_A",
    "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_B", "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_C", "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_D", "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_E", "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_F", "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_G",
    "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_H", "CJK_UNIFIED_IDEOGRAPHS_EXTENSION_I", "COMBINING DIACRITICAL MARKS", "COMBINING DIACRITICAL MARKS EXTENDED", "COMBINING DIACRITICAL MARKS FOR SYMBOLS", "COMBINING DIACRITICAL MARKS SUPPLEMENT",
    "COMBINING HALF MARKS", "COMBINING MARKS FOR SYMBOLS", "COMBININGDIACRITICALMARKS", "COMBININGDIACRITICALMARKSEXTENDED", "COMBININGDIACRITICALMARKSFORSYMBOLS", "COMBININGDIACRITICALMARKSSUPPLEMENT",
    "COMBININGHALFMARKS", "COMBININGMARKSFORSYMBOLS", "COMBINING_DIACRITICAL_MARKS", "COMBINING_DIACRITICAL_MARKS_EXTENDED", "COMBINING_DIACRITICAL_MARKS_SUPPLEMENT", "COMBINING_HALF_MARKS",
    "COMBINING_MARKS_FOR_SYMBOLS", "COMMON INDIC NUMBER FORMS", "COMMONINDICNUMBERFORMS", "COMMON_INDIC_NUMBER_FORMS", "CONTROL PICTURES", "CONTROLPICTURES",
    "CONTROL_PICTURES", "COPTIC", "COPTIC EPACT NUMBERS", "COPTICEPACTNUMBERS", "COPTIC_EPACT_NUMBERS", "COUNTING ROD NUMERALS",
    "COUNTINGRODNUMERALS", "COUNTING_ROD_NUMERALS", "CUNEIFORM", "CUNEIFORM NUMBERS AND PUNCTUATION", "CUNEIFORMNUMBERSANDPUNCTUATION", "CUNEIFORM_NUMBERS_AND_PUNCTUATION",
    "CURRENCY SYMBOLS", "CURRENCYSYMBOLS", "CURRENCY_SYMBOLS", "CYPRIOT SYLLABARY", "CYPRIOTSYLLABARY", "CYPRIOT_SYLLABARY",
    "CYPRO-MINOAN", "CYPRO_MINOAN", "CYRILLIC", "CYRILLIC EXTENDED-A", "CYRILLIC EXTENDED-B", "CYRILLIC EXTENDED-C",
    "CYRILLIC EXTENDED-D", "CYRILLIC SUPPLEMENT", "CYRILLIC SUPPLEMENTARY", "CYRILLICEXTENDED-A", "CYRILLICEXTENDED-B", "CYRILLICEXTENDED-C",
    "CYRILLICEXTENDED-D", "CYRILLICSUPPLEMENT", "CYRILLICSUPPLEMENTARY", "CYRILLIC_EXTENDED_A", "CYRILLIC_EXTENDED_B", "CYRILLIC_EXTENDED_C",
    "CYRILLIC_EXTENDED_D", "CYRILLIC_SUPPLEMENTARY", "DESERET", "DEVANAGARI", "DEVANAGARI EXTENDED", "DEVANAGARI EXTENDED-A",
    "DEVANAGARIEXTENDED", "DEVANAGARIEXTENDED-A", "DEVANAGARI_EXTENDED", "DEVANAGARI_EXTENDED_A", "DINGBATS", "DIVES AKURU",
    "DIVESAKURU", "DIVES_AKURU", "DOGRA", "DOMINO TILES", "DOMINOTILES", "DOMINO_TILES",
    "DUPLOYAN", "EARLY DYNASTIC CUNEIFORM", "EARLYDYNASTICCUNEIFORM", "EARLY_DYNASTIC_CUNEIFORM", "EGYPTIAN HIEROGLYPH FORMAT CONTROLS", "EGYPTIAN HIEROGLYPHS",
    "EGYPTIAN HIEROGLYPHS EXTENDED-A", "EGYPTIANHIEROGLYPHFORMATCONTROLS", "EGYPTIANHIEROGLYPHS", "EGYPTIANHIEROGLYPHSEXTENDED-A", "EGYPTIAN_HIEROGLYPHS", "EGYPTIAN_HIEROGLYPHS_EXTENDED_A",
    "EGYPTIAN_HIEROGLYPH_FORMAT_CONTROLS", "ELBASAN", "ELYMAIC", "EMOTICONS", "ENCLOSED ALPHANUMERIC SUPPLEMENT", "ENCLOSED ALPHANUMERICS",
    "ENCLOSED CJK LETTERS AND MONTHS", "ENCLOSED IDEOGRAPHIC SUPPLEMENT", "ENCLOSEDALPHANUMERICS", "ENCLOSEDALPHANUMERICSUPPLEMENT", "ENCLOSEDCJKLETTERSANDMONTHS", "ENCLOSEDIDEOGRAPHICSUPPLEMENT",
    "ENCLOSED_ALPHANUMERICS", "ENCLOSED_ALPHANUMERIC_SUPPLEMENT", "ENCLOSED_CJK_LETTERS_AND_MONTHS", "ENCLOSED_IDEOGRAPHIC_SUPPLEMENT", "ETHIOPIC", "ETHIOPIC EXTENDED",
    "ETHIOPIC EXTENDED-A", "ETHIOPIC EXTENDED-B", "ETHIOPIC SUPPLEMENT", "ETHIOPICEXTENDED", "ETHIOPICEXTENDED-A", "ETHIOPICEXTENDED-B",
    "ETHIOPICSUPPLEMENT", "ETHIOPIC_EXTENDED", "ETHIOPIC_EXTENDED_A", "ETHIOPIC_EXTENDED_B", "ETHIOPIC_SUPPLEMENT", "GARAY",
    "GENERAL PUNCTUATION", "GENERALPUNCTUATION", "GENERAL_PUNCTUATION", "GEOMETRIC SHAPES", "GEOMETRIC SHAPES EXTENDED", "GEOMETRICSHAPES",
    "GEOMETRICSHAPESEXTENDED", "GEOMETRIC_SHAPES", "GEOMETRIC_SHAPES_EXTENDED", "GEORGIAN", "GEORGIAN EXTENDED", "GEORGIAN SUPPLEMENT",
    "GEORGIANEXTENDED", "GEORGIANSUPPLEMENT", "GEORGIAN_EXTENDED", "GEORGIAN_SUPPLEMENT", "GLAGOLITIC", "GLAGOLITIC SUPPLEMENT",
    "GLAGOLITICSUPPLEMENT", "GLAGOLITIC_SUPPLEMENT", "GOTHIC", "GRANTHA", "GREEK", "GREEK AND COPTIC",
    "GREEK EXTENDED", "GREEKANDCOPTIC", "GREEKEXTENDED", "GREEK_EXTENDED", "GUJARATI", "GUNJALA GONDI",
    "GUNJALAGONDI", "GUNJALA_GONDI", "GURMUKHI", "GURUNG KHEMA", "GURUNGKHEMA", "GURUNG_KHEMA",
    "HALFWIDTH AND FULLWIDTH FORMS", "HALFWIDTHANDFULLWIDTHFORMS", "HALFWIDTH_AND_FULLWIDTH_FORMS", "HANGUL COMPATIBILITY JAMO", "HANGUL JAMO", "HANGUL JAMO EXTENDED-A",
    "HANGUL JAMO EXTENDED-B", "HANGUL SYLLABLES", "HANGULCOMPATIBILITYJAMO", "HANGULJAMO", "HANGULJAMOEXTENDED-A", "HANGULJAMOEXTENDED-B",
    "HANGULSYLLABLES", "HANGUL_COMPATIBILITY_JAMO", "HANGUL_JAMO", "HANGUL_JAMO_EXTENDED_A", "HANGUL_JAMO_EXTENDED_B", "HANGUL_SYLLABLES",
    "HANIFI ROHINGYA", "HANIFIROHINGYA", "HANIFI_ROHINGYA", "HANUNOO", "HATRAN", "HEBREW",
    "HIGH PRIVATE USE SURROGATES", "HIGH SURROGATES", "HIGHPRIVATEUSESURROGATES", "HIGHSURROGATES", "HIGH_PRIVATE_USE_SURROGATES", "HIGH_SURROGATES",
    "HIRAGANA", "IDEOGRAPHIC DESCRIPTION CHARACTERS", "IDEOGRAPHIC SYMBOLS AND PUNCTUATION", "IDEOGRAPHICDESCRIPTIONCHARACTERS", "IDEOGRAPHICSYMBOLSANDPUNCTUATION", "IDEOGRAPHIC_DESCRIPTION_CHARACTERS",
    "IDEOGRAPHIC_SYMBOLS_AND_PUNCTUATION", "IMPERIAL ARAMAIC", "IMPERIALARAMAIC", "IMPERIAL_ARAMAIC", "INDIC SIYAQ NUMBERS", "INDICSIYAQNUMBERS",
    "INDIC_SIYAQ_NUMBERS", "INSCRIPTIONAL PAHLAVI", "INSCRIPTIONAL PARTHIAN", "INSCRIPTIONALPAHLAVI", "INSCRIPTIONALPARTHIAN", "INSCRIPTIONAL_PAHLAVI",
    "INSCRIPTIONAL_PARTHIAN", "IPA EXTENSIONS", "IPAEXTENSIONS", "IPA_EXTENSIONS", "JAVANESE", "KAITHI",
    "KAKTOVIK NUMERALS", "KAKTOVIKNUMERALS", "KAKTOVIK_NUMERALS", "KANA EXTENDED-A", "KANA EXTENDED-B", "KANA SUPPLEMENT",
    "KANAEXTENDED-A", "KANAEXTENDED-B", "KANASUPPLEMENT", "KANA_EXTENDED_A", "KANA_EXTENDED_B", "KANA_SUPPLEMENT",
    "KANBUN", "KANGXI RADICALS", "KANGXIRADICALS", "KANGXI_RADICALS", "KANNADA", "KATAKANA",
    "KATAKANA PHONETIC EXTENSIONS", "KATAKANAPHONETICEXTENSIONS", "KATAKANA_PHONETIC_EXTENSIONS", "KAWI", "KAYAH LI", "KAYAHLI",
    "KAYAH_LI", "KHAROSHTHI", "KHITAN SMALL SCRIPT", "KHITANSMALLSCRIPT", "KHITAN_SMALL_SCRIPT", "KHMER",
    "KHMER SYMBOLS", "KHMERSYMBOLS", "KHMER_SYMBOLS", "KHOJKI", "KHUDAWADI", "KIRAT RAI",
    "KIRATRAI", "KIRAT_RAI", "LAO", "LATIN EXTENDED ADDITIONAL", "LATIN EXTENDED-A", "LATIN EXTENDED-B",
    "LATIN EXTENDED-C", "LATIN EXTENDED-D", "LATIN EXTENDED-E", "LATIN EXTENDED-F", "LATIN EXTENDED-G", "LATIN-1 SUPPLEMENT",
    "LATIN-1SUPPLEMENT", "LATINEXTENDED-A", "LATINEXTENDED-B", "LATINEXTENDED-C", "LATINEXTENDED-D", "LATINEXTENDED-E",
    "LATINEXTENDED-F", "LATINEXTENDED-G", "LATINEXTENDEDADDITIONAL", "LATIN_1_SUPPLEMENT", "LATIN_EXTENDED_A", "LATIN_EXTENDED_ADDITIONAL",
    "LATIN_EXTENDED_B", "LATIN_EXTENDED_C", "LATIN_EXTENDED_D", "LATIN_EXTENDED_E", "LATIN_EXTENDED_F", "LATIN_EXTENDED_G",
    "LEPCHA", "LETTERLIKE SYMBOLS", "LETTERLIKESYMBOLS", "LETTERLIKE_SYMBOLS", "LIMBU", "LINEAR A",
    "LINEAR B IDEOGRAMS", "LINEAR B SYLLABARY", "LINEARA", "LINEARBIDEOGRAMS", "LINEARBSYLLABARY", "LINEAR_A",
    "LINEAR_B_IDEOGRAMS", "LINEAR_B_SYLLABARY", "LISU", "LISU SUPPLEMENT", "LISUSUPPLEMENT", "LISU_SUPPLEMENT",
    "LOW SURROGATES", "LOWSURROGATES", "LOW_SURROGATES", "LYCIAN", "LYDIAN", "MAHAJANI",
    "MAHJONG TILES", "MAHJONGTILES", "MAHJONG_TILES", "MAKASAR", "MALAYALAM", "MANDAIC",
    "MANICHAEAN", "MARCHEN", "MASARAM GONDI", "MASARAMGONDI", "MASARAM_GONDI", "MATHEMATICAL ALPHANUMERIC SYMBOLS",
    "MATHEMATICAL OPERATORS", "MATHEMATICALALPHANUMERICSYMBOLS", "MATHEMATICALOPERATORS", "MATHEMATICAL_ALPHANUMERIC_SYMBOLS", "MATHEMATICAL_OPERATORS", "MAYAN NUMERALS",
    "MAYANNUMERALS", "MAYAN_NUMERALS", "MEDEFAIDRIN", "MEETEI MAYEK", "MEETEI MAYEK EXTENSIONS", "MEETEIMAYEK",
    "MEETEIMAYEKEXTENSIONS", "MEETEI_MAYEK", "MEETEI_MAYEK_EXTENSIONS", "MENDE KIKAKUI", "MENDEKIKAKUI", "MENDE_KIKAKUI",
    "MEROITIC CURSIVE", "MEROITIC HIEROGLYPHS", "MEROITICCURSIVE", "MEROITICHIEROGLYPHS", "MEROITIC_CURSIVE", "MEROITIC_HIEROGLYPHS",
    "MIAO", "MISCELLANEOUS MATHEMATICAL SYMBOLS-A", "MISCELLANEOUS MATHEMATICAL SYMBOLS-B", "MISCELLANEOUS SYMBOLS", "MISCELLANEOUS SYMBOLS AND ARROWS", "MISCELLANEOUS SYMBOLS AND PICTOGRAPHS",
    "MISCELLANEOUS TECHNICAL", "MISCELLANEOUSMATHEMATICALSYMBOLS-A", "MISCELLANEOUSMATHEMATICALSYMBOLS-B", "MISCELLANEOUSSYMBOLS", "MISCELLANEOUSSYMBOLSANDARROWS", "MISCELLANEOUSSYMBOLSANDPICTOGRAPHS",
    "MISCELLANEOUSTECHNICAL", "MISCELLANEOUS_MATHEMATICAL_SYMBOLS_A", "MISCELLANEOUS_MATHEMATICAL_SYMBOLS_B", "MISCELLANEOUS_SYMBOLS", "MISCELLANEOUS_SYMBOLS_AND_ARROWS", "MISCELLANEOUS_SYMBOLS_AND_PICTOGRAPHS",
    "MISCELLANEOUS_TECHNICAL", "MODI", "MODIFIER TONE LETTERS", "MODIFIERTONELETTERS", "MODIFIER_TONE_LETTERS", "MONGOLIAN",
    "MONGOLIAN SUPPLEMENT", "MONGOLIANSUPPLEMENT", "MONGOLIAN_SUPPLEMENT", "MRO", "MULTANI", "MUSICAL SYMBOLS",
    "MUSICALSYMBOLS", "MUSICAL_SYMBOLS", "MYANMAR", "MYANMAR EXTENDED-A", "MYANMAR EXTENDED-B", "MYANMAR EXTENDED-C",
    "MYANMAREXTENDED-A", "MYANMAREXTENDED-B", "MYANMAREXTENDED-C", "MYANMAR_EXTENDED_A", "MYANMAR_EXTENDED_B", "MYANMAR_EXTENDED_C",
    "NABATAEAN", "NAG MUNDARI", "NAGMUNDARI", "NAG_MUNDARI", "NANDINAGARI", "NEW TAI LUE",
    "NEWA", "NEWTAILUE", "NEW_TAI_LUE", "NKO", "NUMBER FORMS", "NUMBERFORMS",
    "NUMBER_FORMS", "NUSHU", "NYIAKENG PUACHUE HMONG", "NYIAKENGPUACHUEHMONG", "NYIAKENG_PUACHUE_HMONG", "OGHAM",
    "OL CHIKI", "OL ONAL", "OLCHIKI", "OLD HUNGARIAN", "OLD ITALIC", "OLD NORTH ARABIAN",
    "OLD PERMIC", "OLD PERSIAN", "OLD SOGDIAN", "OLD SOUTH ARABIAN", "OLD TURKIC", "OLD UYGHUR",
    "OLDHUNGARIAN", "OLDITALIC", "OLDNORTHARABIAN", "OLDPERMIC", "OLDPERSIAN", "OLDSOGDIAN",
    "OLDSOUTHARABIAN", "OLDTURKIC", "OLDUYGHUR", "OLD_HUNGARIAN", "OLD_ITALIC", "OLD_NORTH_ARABIAN",
    "OLD_PERMIC", "OLD_PERSIAN", "OLD_SOGDIAN", "OLD_SOUTH_ARABIAN", "OLD_TURKIC", "OLD_UYGHUR",
    "OLONAL", "OL_CHIKI", "OL_ONAL", "OPTICAL CHARACTER RECOGNITION", "OPTICALCHARACTERRECOGNITION", "OPTICAL_CHARACTER_RECOGNITION",
    "ORIYA", "ORNAMENTAL DINGBATS", "ORNAMENTALDINGBATS", "ORNAMENTAL_DINGBATS", "OSAGE", "OSMANYA",
    "OTTOMAN SIYAQ NUMBERS", "OTTOMANSIYAQNUMBERS", "OTTOMAN_SIYAQ_NUMBERS", "PAHAWH HMONG", "PAHAWHHMONG", "PAHAWH_HMONG",
    "PALMYRENE", "PAU CIN HAU", "PAUCINHAU", "PAU_CIN_HAU", "PHAGS-PA", "PHAGS_PA",
    "PHAISTOS DISC", "PHAISTOSDISC", "PHAISTOS_DISC", "PHOENICIAN", "PHONETIC EXTENSIONS", "PHONETIC EXTENSIONS SUPPLEMENT",
    "PHONETICEXTENSIONS", "PHONETICEXTENSIONSSUPPLEMENT", "PHONETIC_EXTENSIONS", "PHONETIC_EXTENSIONS_SUPPLEMENT", "PLAYING CARDS", "PLAYINGCARDS",
    "PLAYING_CARDS", "PRIVATE USE AREA", "PRIVATEUSEAREA", "PRIVATE_USE_AREA", "PSALTER PAHLAVI", "PSALTERPAHLAVI",
    "PSALTER_PAHLAVI", "REJANG", "RUMI NUMERAL SYMBOLS", "RUMINUMERALSYMBOLS", "RUMI_NUMERAL_SYMBOLS", "RUNIC",
    "SAMARITAN", "SAURASHTRA", "SHARADA", "SHAVIAN", "SHORTHAND FORMAT CONTROLS", "SHORTHANDFORMATCONTROLS",
    "SHORTHAND_FORMAT_CONTROLS", "SIDDHAM", "SINHALA", "SINHALA ARCHAIC NUMBERS", "SINHALAARCHAICNUMBERS", "SINHALA_ARCHAIC_NUMBERS",
    "SMALL FORM VARIANTS", "SMALL KANA EXTENSION", "SMALLFORMVARIANTS", "SMALLKANAEXTENSION", "SMALL_FORM_VARIANTS", "SMALL_KANA_EXTENSION",
    "SOGDIAN", "SORA SOMPENG", "SORASOMPENG", "SORA_SOMPENG", "SOYOMBO", "SPACING MODIFIER LETTERS",
    "SPACINGMODIFIERLETTERS", "SPACING_MODIFIER_LETTERS", "SPECIALS", "SUNDANESE", "SUNDANESE SUPPLEMENT", "SUNDANESESUPPLEMENT",
    "SUNDANESE_SUPPLEMENT", "SUNUWAR", "SUPERSCRIPTS AND SUBSCRIPTS", "SUPERSCRIPTSANDSUBSCRIPTS", "SUPERSCRIPTS_AND_SUBSCRIPTS", "SUPPLEMENTAL ARROWS-A",
    "SUPPLEMENTAL ARROWS-B", "SUPPLEMENTAL ARROWS-C", "SUPPLEMENTAL MATHEMATICAL OPERATORS", "SUPPLEMENTAL PUNCTUATION", "SUPPLEMENTAL SYMBOLS AND PICTOGRAPHS", "SUPPLEMENTALARROWS-A",
    "SUPPLEMENTALARROWS-B", "SUPPLEMENTALARROWS-C", "SUPPLEMENTALMATHEMATICALOPERATORS", "SUPPLEMENTALPUNCTUATION", "SUPPLEMENTALSYMBOLSANDPICTOGRAPHS", "SUPPLEMENTAL_ARROWS_A",
    "SUPPLEMENTAL_ARROWS_B", "SUPPLEMENTAL_ARROWS_C", "SUPPLEMENTAL_MATHEMATICAL_OPERATORS", "SUPPLEMENTAL_PUNCTUATION", "SUPPLEMENTAL_SYMBOLS_AND_PICTOGRAPHS", "SUPPLEMENTARY PRIVATE USE AREA-A",
    "SUPPLEMENTARY PRIVATE USE AREA-B", "SUPPLEMENTARYPRIVATEUSEAREA-A", "SUPPLEMENTARYPRIVATEUSEAREA-B", "SUPPLEMENTARY_PRIVATE_USE_AREA_A", "SUPPLEMENTARY_PRIVATE_USE_AREA_B", "SURROGATES_AREA",
    "SUTTON SIGNWRITING", "SUTTONSIGNWRITING", "SUTTON_SIGNWRITING", "SYLOTI NAGRI", "SYLOTINAGRI", "SYLOTI_NAGRI",
    "SYMBOLS AND PICTOGRAPHS EXTENDED-A", "SYMBOLS FOR LEGACY COMPUTING", "SYMBOLS FOR LEGACY COMPUTING SUPPLEMENT", "SYMBOLSANDPICTOGRAPHSEXTENDED-A", "SYMBOLSFORLEGACYCOMPUTING", "SYMBOLSFORLEGACYCOMPUTINGSUPPLEMENT",
    "SYMBOLS_AND_PICTOGRAPHS_EXTENDED_A", "SYMBOLS_FOR_LEGACY_COMPUTING", "SYMBOLS_FOR_LEGACY_COMPUTING_SUPPLEMENT", "SYRIAC", "SYRIAC SUPPLEMENT", "SYRIACSUPPLEMENT",
    "SYRIAC_SUPPLEMENT", "TAGALOG", "TAGBANWA", "TAGS", "TAI LE", "TAI THAM",
    "TAI VIET", "TAI XUAN JING SYMBOLS", "TAILE", "TAITHAM", "TAIVIET", "TAIXUANJINGSYMBOLS",
    "TAI_LE", "TAI_THAM", "TAI_VIET", "TAI_XUAN_JING_SYMBOLS", "TAKRI", "TAMIL",
    "TAMIL SUPPLEMENT", "TAMILSUPPLEMENT", "TAMIL_SUPPLEMENT", "TANGSA", "TANGUT", "TANGUT COMPONENTS",
    "TANGUT SUPPLEMENT", "TANGUTCOMPONENTS", "TANGUTSUPPLEMENT", "TANGUT_COMPONENTS", "TANGUT_SUPPLEMENT", "TELUGU",
    "THAANA", "THAI", "TIBETAN", "TIFINAGH", "TIRHUTA", "TODHRI",
    "TOTO", "TRANSPORT AND MAP SYMBOLS", "TRANSPORTANDMAPSYMBOLS", "TRANSPORT_AND_MAP_SYMBOLS", "TULU-TIGALARI", "TULU_TIGALARI",
    "UGARITIC", "UNIFIED CANADIAN ABORIGINAL SYLLABICS", "UNIFIED CANADIAN ABORIGINAL SYLLABICS EXTENDED", "UNIFIED CANADIAN ABORIGINAL SYLLABICS EXTENDED-A", "UNIFIEDCANADIANABORIGINALSYLLABICS", "UNIFIEDCANADIANABORIGINALSYLLABICSEXTENDED",
    "UNIFIEDCANADIANABORIGINALSYLLABICSEXTENDED-A", "UNIFIED_CANADIAN_ABORIGINAL_SYLLABICS", "UNIFIED_CANADIAN_ABORIGINAL_SYLLABICS_EXTENDED", "UNIFIED_CANADIAN_ABORIGINAL_SYLLABICS_EXTENDED_A", "VAI", "VARIATION SELECTORS",
    "VARIATION SELECTORS SUPPLEMENT", "VARIATIONSELECTORS", "VARIATIONSELECTORSSUPPLEMENT", "VARIATION_SELECTORS", "VARIATION_SELECTORS_SUPPLEMENT", "VEDIC EXTENSIONS",
    "VEDICEXTENSIONS", "VEDIC_EXTENSIONS", "VERTICAL FORMS", "VERTICALFORMS", "VERTICAL_FORMS", "VITHKUQI",
    "WANCHO", "WARANG CITI", "WARANGCITI", "WARANG_CITI", "YEZIDI", "YI RADICALS",
    "YI SYLLABLES", "YIJING HEXAGRAM SYMBOLS", "YIJINGHEXAGRAMSYMBOLS", "YIJING_HEXAGRAM_SYMBOLS", "YIRADICALS", "YISYLLABLES",
    "YI_RADICALS", "YI_SYLLABLES", "ZANABAZAR SQUARE", "ZANABAZARSQUARE", "ZANABAZAR_SQUARE", "ZNAMENNY MUSICAL NOTATION",
    "ZNAMENNYMUSICALNOTATION", "ZNAMENNY_MUSICAL_NOTATION",
]

// MARK: - Name resolution (mirrors Pattern.family)

/// Whether `name` — the raw text inside `\p{...}` / `\P{...}` — is accepted
/// by java.util.regex.Pattern#family. `unicodeClasses` is the
/// UNICODE_CHARACTER_CLASS ((?U)) state at the escape's position; it only
/// affects the bare-name POSIX lookup, exactly like the JVM.
func jvmRegexPropertyNameValid(_ name: String, unicodeClasses: Bool) -> Bool {
    if let eq = name.firstIndex(of: "=") {
        // \p{name=value}: the key is lowercased before dispatch; the value is
        // resolved by the family-specific lookup (scripts/blocks are
        // case-insensitive, gc values match forProperty case-sensitively).
        let key = name[..<eq].lowercased()
        let value = name[name.index(after: eq)...]
        switch key {
        case "sc", "script": return jvmRegexScriptNames.contains(value.uppercased())
        case "blk", "block": return jvmRegexBlockNames.contains(value.uppercased())
        case "gc", "general_category": return jvmRegexPropertyNames.contains(String(value))
        default: return false
        }
    }
    if name.hasPrefix("In") {
        // \p{InBlockName}: Unicode blocks only.
        return jvmRegexBlockNames.contains(name.dropFirst(2).uppercased())
    }
    if name.hasPrefix("Is") {
        // \p{IsX}: forUnicodeProperty (binary props + POSIX, uppercase),
        // then forProperty (exact), then forUnicodeScript (uppercase).
        let short = name.dropFirst(2)
        return jvmRegexUnicodePropertyNames.contains(short.uppercased())
            || jvmRegexPosixNames.contains(short.uppercased())
            || jvmRegexPropertyNames.contains(String(short))
            || jvmRegexScriptNames.contains(short.uppercased())
    }
    if unicodeClasses, jvmRegexPosixNames.contains(name.uppercased()) { return true }
    // Bare names never consult getUnicodePredicate — binary property names
    // require the Is prefix (or gc=/etc.).
    return jvmRegexPropertyNames.contains(name)
}

// MARK: - Pattern scanner

private struct JVMRegexScanMode {
    var unicodeClasses = false
    var comments = false
    var unixLines = false
}

private func jvmRegexIsSpace(_ c: Character) -> Bool {
    switch c {
    case " ", "\t", "\n", "\u{0B}", "\u{0C}", "\r": return true
    default: return false
    }
}

private func jvmRegexIsLineSeparator(_ c: Character, unixLines: Bool) -> Bool {
    if unixLines { return c == "\n" }
    switch c {
    case "\n", "\r", "\u{2028}", "\u{2029}", "\u{0085}": return true
    default: return false
    }
}

/// Returns the first java.util.regex syntax error found while scanning for
/// \p/\P property escapes, or nil when every property escape is valid.
///
/// Mirrors the parts of java.util.regex.Pattern that decide which `\p{...}`
/// names are legal: inline flag groups `(?flags)` / `(?flags:...)` /
/// `(?flags-flags...)`, group scoping, character classes (including nested
/// classes, where `#` comments and whitespace still apply in COMMENTS mode
/// but flag groups are literal), and `\Q...\E` quoting. Only property-name
/// validity is reported — other syntax errors remain ICU's concern.
func jvmRegexPropertyError(
    _ pattern: String,
    commentsInitially: Bool = false,
    unixLinesInitially: Bool = false,
    unicodeClassesInitially: Bool = false
) -> String? {
    var mode = JVMRegexScanMode()
    mode.comments = commentsInitially
    mode.unixLines = unixLinesInitially
    mode.unicodeClasses = unicodeClassesInitially
    var stack: [JVMRegexScanMode] = []
    let chars = Array(pattern)
    var index = 0
    var classDepth = 0
    var error: String? = nil

    func isFlag(_ c: Character) -> Bool { "idmsucxU".contains(c) }

    // Skips whitespace and #-comments the way java.util.regex does in
    // COMMENTS mode (ASCII.isSpace + '#'-to-EOL).
    func skipCommentsAndSpace(_ i: inout Int) {
        guard mode.comments else { return }
        while i < chars.count {
            let c = chars[i]
            if jvmRegexIsSpace(c) { i += 1; continue }
            if c == "#" {
                i += 1
                while i < chars.count, !jvmRegexIsLineSeparator(chars[i], unixLines: mode.unixLines) { i += 1 }
                continue
            }
            break
        }
    }

    while index < chars.count, error == nil {
        let c = chars[index]
        if c == "\\" {
            guard index + 1 < chars.count else { index += 1; continue }
            let escape = chars[index + 1]
            if escape == "Q" {
                // \Q ... \E literal quote (unterminated runs to end).
                var end = index + 2
                while end < chars.count, !(chars[end] == "\\" && end + 1 < chars.count && chars[end + 1] == "E") {
                    end += 1
                }
                index = min(end + 2, chars.count)
                continue
            }
            if escape == "p" || escape == "P" {
                var cursor = index + 2
                skipCommentsAndSpace(&cursor)
                if cursor >= chars.count {
                    error = "Unknown character property name"
                    break
                }
                if chars[cursor] == "{" {
                    // Braced \p{...}: leading whitespace/comments inside the
                    // braces are skipped in COMMENTS mode; the name then runs
                    // raw to the next '}' (which comment text can also supply,
                    // matching java.util.regex' read()-based scan closely
                    // enough that the accept/reject verdict is identical).
                    var nameStart = cursor + 1
                    skipCommentsAndSpace(&nameStart)
                    var nameEnd = nameStart
                    while nameEnd < chars.count, chars[nameEnd] != "}" { nameEnd += 1 }
                    if nameEnd >= chars.count {
                        error = "Unclosed character family"
                        break
                    }
                    let name = String(chars[nameStart..<nameEnd])
                    if name.isEmpty {
                        error = "Empty character family"
                    } else if !jvmRegexPropertyNameValid(name, unicodeClasses: mode.unicodeClasses) {
                        error = "Unknown character property name {\(name)}"
                    }
                    index = nameEnd + 1
                    continue
                }
                // Unbraced \pX: a single-letter category — the JVM accepts
                // exactly L M N P S Z C without braces.
                let scalar = chars[cursor].unicodeScalars.first!
                if !"LMNPSZC".unicodeScalars.contains(scalar) {
                    error = "Unknown character property name {\(chars[cursor])}"
                }
                index = cursor + 1
                continue
            }
            index += 2
            continue
        }
        if mode.comments, c == "#" {
            index += 1
            while index < chars.count, !jvmRegexIsLineSeparator(chars[index], unixLines: mode.unixLines) { index += 1 }
            continue
        }
        if classDepth > 0 {
            if c == "[" { classDepth += 1 }
            else if c == "]" { classDepth -= 1 }
            index += 1
            continue
        }
        if c == "[" {
            classDepth = 1
            index += 1
            // A leading `^` and a leading `]` are literal members.
            if index < chars.count, chars[index] == "^" { index += 1 }
            if index < chars.count, chars[index] == "]" { index += 1 }
            continue
        }
        if c == ")" {
            if let saved = stack.popLast() { mode = saved }
            index += 1
            continue
        }
        if c == "(", index + 1 < chars.count, chars[index + 1] == "?" {
            var cursor = index + 2
            var on = ""
            var off = ""
            var onU = false, offU = false, onD = false, offD = false, onX = false, offX = false
            var seenMinus = false
            while cursor < chars.count {
                let f = chars[cursor]
                if mode.comments {
                    if jvmRegexIsSpace(f) { cursor += 1; continue }
                    if f == "#" {
                        cursor += 1
                        while cursor < chars.count, !jvmRegexIsLineSeparator(chars[cursor], unixLines: mode.unixLines) { cursor += 1 }
                        continue
                    }
                }
                if f == "-", !seenMinus { seenMinus = true; cursor += 1; continue }
                guard isFlag(f) else { break }
                if f == "U" { if seenMinus { offU = true } else { onU = true } }
                else if f == "u" { }
                else {
                    if seenMinus { off.append(f) } else { on.append(f) }
                    if f == "x" { if seenMinus { offX = true } else { onX = true } }
                    if f == "d" { if seenMinus { offD = true } else { onD = true } }
                }
                cursor += 1
            }
            let isFlagGroup = cursor > index + 2
                && cursor < chars.count
                && (chars[cursor] == ")" || chars[cursor] == ":")
            if isFlagGroup {
                let terminator = chars[cursor]
                if terminator == ":" { stack.append(mode) }
                if onU { mode.unicodeClasses = true }
                if offU { mode.unicodeClasses = false }
                if onX { mode.comments = true }
                if offX { mode.comments = false }
                if onD { mode.unixLines = true }
                if offD { mode.unixLines = false }
                index = cursor + 1
                continue
            }
            // Some other `(?...)` construct (lookaround, named group, atomic
            // group, ...): it still opens a group, so flag directives inside
            // it end at its `)`.
            stack.append(mode)
            index += 1
            continue
        }
        if c == "(" {
            stack.append(mode)
            index += 1
            continue
        }
        index += 1
    }
    return error
}
