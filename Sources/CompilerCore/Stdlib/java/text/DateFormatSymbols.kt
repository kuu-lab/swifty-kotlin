package java.text

import java.util.Locale

/**
 * Locale-sensitive date format symbols (`java.text.DateFormatSymbols`).
 *
 * This bundled shim carries the JDK (CLDR) symbol tables for the most common
 * locales. Locale lookup follows the JDK fallback chain: exact
 * `language_COUNTRY` match, then language-only match, then the CLDR root
 * (abbreviated English) table. Regional variants that are not listed fall
 * back to their language table; `zoneStrings` is intentionally empty.
 */
public class DateFormatSymbols private constructor(locale: Locale) {
    public constructor() : this(Locale.getDefault())

    public constructor(locale: Locale?) : this(locale!!)

    private var erasData: Array<String>
    private var monthsData: Array<String>
    private var shortMonthsData: Array<String>
    private var weekdaysData: Array<String>
    private var shortWeekdaysData: Array<String>
    private var amPmStringsData: Array<String>
    private var zoneStringsData: Array<Array<String>> = emptyArray()
    private var localPatternCharsData: String = "GyMdkHmsSEDFwWahKzZ"

    init {
        val data = resolveSymbolsData(locale)
        erasData = data.eras
        monthsData = data.months
        shortMonthsData = data.shortMonths
        weekdaysData = data.weekdays
        shortWeekdaysData = data.shortWeekdays
        amPmStringsData = data.amPmStrings
    }

    /** Era strings, e.g. `BC`/`AD` for `en`. Getter returns a copy like the JDK. */
    public var eras: Array<String>
        get() = erasData.copyOf()
        set(value) { erasData = value.copyOf() }

    /** Full month names; index 12 is the empty standalone slot (JDK layout). */
    public var months: Array<String>
        get() = monthsData.copyOf()
        set(value) { monthsData = value.copyOf() }

    /** Abbreviated month names; index 12 is the empty standalone slot. */
    public var shortMonths: Array<String>
        get() = shortMonthsData.copyOf()
        set(value) { shortMonthsData = value.copyOf() }

    /** Full weekday names; index 0 is empty, indices 1..7 are Sunday..Saturday. */
    public var weekdays: Array<String>
        get() = weekdaysData.copyOf()
        set(value) { weekdaysData = value.copyOf() }

    /** Abbreviated weekday names; index 0 is empty, indices 1..7 are Sunday..Saturday. */
    public var shortWeekdays: Array<String>
        get() = shortWeekdaysData.copyOf()
        set(value) { shortWeekdaysData = value.copyOf() }

    /** AM/PM strings, indices 0 and 1. */
    public var amPmStrings: Array<String>
        get() = amPmStringsData.copyOf()
        set(value) { amPmStringsData = value.copyOf() }

    /** Time zone display strings. The JDK bundles per-zone data; this shim returns an empty array. */
    public var zoneStrings: Array<Array<String>>
        get() = zoneStringsData.copyOf()
        set(value) { zoneStringsData = value.copyOf() }

    /** Pattern characters used by `java.text.SimpleDateFormat`; the JDK default is locale-independent. */
    public var localPatternChars: String
        get() = localPatternCharsData
        set(value) { localPatternCharsData = value }

    public fun getEras(): Array<String> = eras
    public fun setEras(value: Array<String>) { eras = value }
    public fun getMonths(): Array<String> = months
    public fun setMonths(value: Array<String>) { months = value }
    public fun getShortMonths(): Array<String> = shortMonths
    public fun setShortMonths(value: Array<String>) { shortMonths = value }
    public fun getWeekdays(): Array<String> = weekdays
    public fun setWeekdays(value: Array<String>) { weekdays = value }
    public fun getShortWeekdays(): Array<String> = shortWeekdays
    public fun setShortWeekdays(value: Array<String>) { shortWeekdays = value }
    public fun getAmPmStrings(): Array<String> = amPmStrings
    public fun setAmPmStrings(value: Array<String>) { amPmStrings = value }
    public fun getZoneStrings(): Array<Array<String>> = zoneStrings
    public fun setZoneStrings(value: Array<Array<String>>) { zoneStrings = value }
    public fun getLocalPatternChars(): String = localPatternChars
    public fun setLocalPatternChars(value: String) { localPatternChars = value }

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DateFormatSymbols) return false
        return erasData.contentEquals(other.erasData) &&
            monthsData.contentEquals(other.monthsData) &&
            shortMonthsData.contentEquals(other.shortMonthsData) &&
            weekdaysData.contentEquals(other.weekdaysData) &&
            shortWeekdaysData.contentEquals(other.shortWeekdaysData) &&
            amPmStringsData.contentEquals(other.amPmStringsData)
    }

    public override fun hashCode(): Int {
        var result = erasData.contentHashCode()
        result = 31 * result + monthsData.contentHashCode()
        result = 31 * result + shortMonthsData.contentHashCode()
        result = 31 * result + weekdaysData.contentHashCode()
        result = 31 * result + shortWeekdaysData.contentHashCode()
        result = 31 * result + amPmStringsData.contentHashCode()
        return result
    }

    public companion object {
        /** Locales with bundled symbol data (a subset of the JDK's `getAvailableLocales`). */
        public fun getAvailableLocales(): Array<Locale> = arrayOf(
            Locale.ROOT,
            Locale.ENGLISH, Locale.US, Locale.UK, Locale.CANADA, Locale.CANADA_FRENCH,
            Locale.JAPANESE, Locale.JAPAN,
            Locale.GERMAN, Locale.GERMANY,
            Locale.FRENCH, Locale.FRANCE,
            Locale.CHINESE, Locale.CHINA, Locale.SIMPLIFIED_CHINESE, Locale.TRADITIONAL_CHINESE, Locale.TAIWAN,
            Locale.KOREAN, Locale.KOREA,
            Locale.ITALIAN, Locale.ITALY,
            Locale("es"), Locale("it"), Locale("pt"), Locale("ru"), Locale("ar"),
            Locale("hi"), Locale("nl"), Locale("sv"), Locale("tr"), Locale("pl"),
            Locale("en", "GB"), Locale("en", "IE"), Locale("en", "IN"), Locale("en", "AU"),
            Locale("en", "NZ"), Locale("en", "SG"), Locale("en", "HK"), Locale("en", "ZA"),
            Locale("fr", "CA"), Locale("zh", "HK"), Locale("zh", "MO"), Locale("pt", "PT"),
            Locale("es", "MX"), Locale("es", "ES")
        )

        /** Shared per-locale instance like the JDK cache; mutations via setters stay local to the returned object. */
        public fun getInstance(): DateFormatSymbols = DateFormatSymbols(Locale.getDefault())

        public fun getInstance(locale: Locale?): DateFormatSymbols = DateFormatSymbols(locale)
    }
}

private class DateFormatSymbolsData(
    val eras: Array<String>,
    val months: Array<String>,
    val shortMonths: Array<String>,
    val weekdays: Array<String>,
    val shortWeekdays: Array<String>,
    val amPmStrings: Array<String>,
)

private fun symbolsData(
    eras: String,
    months: String,
    shortMonths: String,
    weekdays: String,
    shortWeekdays: String,
    amPmStrings: String,
): DateFormatSymbolsData = DateFormatSymbolsData(
    eras = eras.split('|').toTypedArray(),
    months = months.split('|').toTypedArray(),
    shortMonths = shortMonths.split('|').toTypedArray(),
    weekdays = weekdays.split('|').toTypedArray(),
    shortWeekdays = shortWeekdays.split('|').toTypedArray(),
    amPmStrings = amPmStrings.split('|').toTypedArray(),
)

// NOTE: `|` inside a field is escaped by doubling? No — JVM data contains no '|'.
// Trailing '|' in the probe dumps marks the empty 13th month slot; split keeps it.

private val SYMBOLS_EN = symbolsData(
    eras = "BC|AD",
    months = "January|February|March|April|May|June|July|August|September|October|November|December|",
    shortMonths = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|",
    weekdays = "|Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday",
    shortWeekdays = "|Sun|Mon|Tue|Wed|Thu|Fri|Sat",
    amPmStrings = "AM|PM",
)

private val SYMBOLS_EN_GB = symbolsData(
    eras = "BC|AD",
    months = "January|February|March|April|May|June|July|August|September|October|November|December|",
    shortMonths = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sept|Oct|Nov|Dec|",
    weekdays = "|Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday",
    shortWeekdays = "|Sun|Mon|Tue|Wed|Thu|Fri|Sat",
    amPmStrings = "am|pm",
)

private val SYMBOLS_EN_CA = symbolsData(
    eras = "BC|AD",
    months = "January|February|March|April|May|June|July|August|September|October|November|December|",
    shortMonths = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|",
    weekdays = "|Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday",
    shortWeekdays = "|Sun|Mon|Tue|Wed|Thu|Fri|Sat",
    amPmStrings = "a.m.|p.m.",
)

private val SYMBOLS_EN_IE = symbolsData(
    eras = "BC|AD",
    months = "January|February|March|April|May|June|July|August|September|October|November|December|",
    shortMonths = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sept|Oct|Nov|Dec|",
    weekdays = "|Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday",
    shortWeekdays = "|Sun|Mon|Tue|Wed|Thu|Fri|Sat",
    amPmStrings = "a.m.|p.m.",
)

private val SYMBOLS_EN_AU = symbolsData(
    eras = "BC|AD",
    months = "January|February|March|April|May|June|July|August|September|October|November|December|",
    shortMonths = "Jan|Feb|Mar|Apr|May|June|Jul|Aug|Sept|Oct|Nov|Dec|",
    weekdays = "|Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday",
    shortWeekdays = "|Sun|Mon|Tue|Wed|Thu|Fri|Sat",
    amPmStrings = "am|pm",
)

private val SYMBOLS_JA = symbolsData(
    eras = "紀元前|西暦",
    months = "1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月|",
    shortMonths = "1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月|",
    weekdays = "|日曜日|月曜日|火曜日|水曜日|木曜日|金曜日|土曜日",
    shortWeekdays = "|日|月|火|水|木|金|土",
    amPmStrings = "午前|午後",
)

private val SYMBOLS_DE = symbolsData(
    eras = "v. Chr.|n. Chr.",
    months = "Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember|",
    shortMonths = "Jan.|Feb.|März|Apr.|Mai|Juni|Juli|Aug.|Sept.|Okt.|Nov.|Dez.|",
    weekdays = "|Sonntag|Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag",
    shortWeekdays = "|So.|Mo.|Di.|Mi.|Do.|Fr.|Sa.",
    amPmStrings = "AM|PM",
)

private val SYMBOLS_FR = symbolsData(
    eras = "av. J.-C.|ap. J.-C.",
    months = "janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre|",
    shortMonths = "janv.|févr.|mars|avr.|mai|juin|juil.|août|sept.|oct.|nov.|déc.|",
    weekdays = "|dimanche|lundi|mardi|mercredi|jeudi|vendredi|samedi",
    shortWeekdays = "|dim.|lun.|mar.|mer.|jeu.|ven.|sam.",
    amPmStrings = "AM|PM",
)

private val SYMBOLS_FR_CA = symbolsData(
    eras = "av. J.-C.|ap. J.-C.",
    months = "janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre|",
    shortMonths = "janv.|févr.|mars|avr.|mai|juin|juill.|août|sept.|oct.|nov.|déc.|",
    weekdays = "|dimanche|lundi|mardi|mercredi|jeudi|vendredi|samedi",
    shortWeekdays = "|dim.|lun.|mar.|mer.|jeu.|ven.|sam.",
    amPmStrings = "a.m.|p.m.",
)

private val SYMBOLS_ZH = symbolsData(
    eras = "公元前|公元",
    months = "一月|二月|三月|四月|五月|六月|七月|八月|九月|十月|十一月|十二月|",
    shortMonths = "1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月|",
    weekdays = "|星期日|星期一|星期二|星期三|星期四|星期五|星期六",
    shortWeekdays = "|周日|周一|周二|周三|周四|周五|周六",
    amPmStrings = "上午|下午",
)

private val SYMBOLS_ZH_TW = symbolsData(
    eras = "西元前|西元",
    months = "1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月|",
    shortMonths = "1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月|",
    weekdays = "|星期日|星期一|星期二|星期三|星期四|星期五|星期六",
    shortWeekdays = "|週日|週一|週二|週三|週四|週五|週六",
    amPmStrings = "上午|下午",
)

private val SYMBOLS_ZH_HK = symbolsData(
    eras = "公元前|公元",
    months = "1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月|",
    shortMonths = "1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月|",
    weekdays = "|星期日|星期一|星期二|星期三|星期四|星期五|星期六",
    shortWeekdays = "|週日|週一|週二|週三|週四|週五|週六",
    amPmStrings = "上午|下午",
)

private val SYMBOLS_KO = symbolsData(
    eras = "BC|AD",
    months = "1월|2월|3월|4월|5월|6월|7월|8월|9월|10월|11월|12월|",
    shortMonths = "1월|2월|3월|4월|5월|6월|7월|8월|9월|10월|11월|12월|",
    weekdays = "|일요일|월요일|화요일|수요일|목요일|금요일|토요일",
    shortWeekdays = "|일|월|화|수|목|금|토",
    amPmStrings = "오전|오후",
)

private val SYMBOLS_ES = symbolsData(
    eras = "a. C.|d. C.",
    months = "enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre|",
    shortMonths = "ene|feb|mar|abr|may|jun|jul|ago|sept|oct|nov|dic|",
    weekdays = "|domingo|lunes|martes|miércoles|jueves|viernes|sábado",
    shortWeekdays = "|dom|lun|mar|mié|jue|vie|sáb",
    amPmStrings = "a. m.|p. m.",
)

private val SYMBOLS_ES_MX = symbolsData(
    eras = "a.C.|d.C.",
    months = "enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre|",
    shortMonths = "ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic|",
    weekdays = "|domingo|lunes|martes|miércoles|jueves|viernes|sábado",
    shortWeekdays = "|dom|lun|mar|mié|jue|vie|sáb",
    amPmStrings = "a.m.|p.m.",
)

private val SYMBOLS_IT = symbolsData(
    eras = "a.C.|d.C.",
    months = "gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre|",
    shortMonths = "gen|feb|mar|apr|mag|giu|lug|ago|set|ott|nov|dic|",
    weekdays = "|domenica|lunedì|martedì|mercoledì|giovedì|venerdì|sabato",
    shortWeekdays = "|dom|lun|mar|mer|gio|ven|sab",
    amPmStrings = "AM|PM",
)

private val SYMBOLS_PT = symbolsData(
    eras = "a.C.|d.C.",
    months = "janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro|",
    shortMonths = "jan.|fev.|mar.|abr.|mai.|jun.|jul.|ago.|set.|out.|nov.|dez.|",
    weekdays = "|domingo|segunda-feira|terça-feira|quarta-feira|quinta-feira|sexta-feira|sábado",
    shortWeekdays = "|dom.|seg.|ter.|qua.|qui.|sex.|sáb.",
    amPmStrings = "AM|PM",
)

private val SYMBOLS_PT_PT = symbolsData(
    eras = "a.C.|d.C.",
    months = "janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro|",
    shortMonths = "jan.|fev.|mar.|abr.|mai.|jun.|jul.|ago.|set.|out.|nov.|dez.|",
    weekdays = "|domingo|segunda-feira|terça-feira|quarta-feira|quinta-feira|sexta-feira|sábado",
    shortWeekdays = "|domingo|segunda|terça|quarta|quinta|sexta|sábado",
    amPmStrings = "da manhã|da tarde",
)

private val SYMBOLS_RU = symbolsData(
    eras = "до н. э.|н. э.",
    months = "января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|",
    shortMonths = "янв.|февр.|мар.|апр.|мая|июн.|июл.|авг.|сент.|окт.|нояб.|дек.|",
    weekdays = "|воскресенье|понедельник|вторник|среда|четверг|пятница|суббота",
    shortWeekdays = "|вс|пн|вт|ср|чт|пт|сб",
    amPmStrings = "AM|PM",
)

private val SYMBOLS_AR = symbolsData(
    eras = "ق.م|م",
    months = "يناير|فبراير|مارس|أبريل|مايو|يونيو|يوليو|أغسطس|سبتمبر|أكتوبر|نوفمبر|ديسمبر|",
    shortMonths = "يناير|فبراير|مارس|أبريل|مايو|يونيو|يوليو|أغسطس|سبتمبر|أكتوبر|نوفمبر|ديسمبر|",
    weekdays = "|الأحد|الاثنين|الثلاثاء|الأربعاء|الخميس|الجمعة|السبت",
    shortWeekdays = "|الأحد|الاثنين|الثلاثاء|الأربعاء|الخميس|الجمعة|السبت",
    amPmStrings = "ص|م",
)

private val SYMBOLS_HI = symbolsData(
    eras = "ईसा-पूर्व|ईस्वी",
    months = "जनवरी|फ़रवरी|मार्च|अप्रैल|मई|जून|जुलाई|अगस्त|सितंबर|अक्टूबर|नवंबर|दिसंबर|",
    shortMonths = "जन॰|फ़र॰|मार्च|अप्रैल|मई|जून|जुल॰|अग॰|सित॰|अक्टू॰|नव॰|दिस॰|",
    weekdays = "|रविवार|सोमवार|मंगलवार|बुधवार|गुरुवार|शुक्रवार|शनिवार",
    shortWeekdays = "|रवि|सोम|मंगल|बुध|गुरु|शुक्र|शनि",
    amPmStrings = "am|pm",
)

private val SYMBOLS_NL = symbolsData(
    eras = "v.Chr.|n.Chr.",
    months = "januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december|",
    shortMonths = "jan|feb|mrt|apr|mei|jun|jul|aug|sep|okt|nov|dec|",
    weekdays = "|zondag|maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag",
    shortWeekdays = "|zo|ma|di|wo|do|vr|za",
    amPmStrings = "a.m.|p.m.",
)

private val SYMBOLS_SV = symbolsData(
    eras = "f.Kr.|e.Kr.",
    months = "januari|februari|mars|april|maj|juni|juli|augusti|september|oktober|november|december|",
    shortMonths = "jan.|feb.|mars|apr.|maj|juni|juli|aug.|sep.|okt.|nov.|dec.|",
    weekdays = "|söndag|måndag|tisdag|onsdag|torsdag|fredag|lördag",
    shortWeekdays = "|sön|mån|tis|ons|tors|fre|lör",
    amPmStrings = "fm|em",
)

private val SYMBOLS_TR = symbolsData(
    eras = "MÖ|MS",
    months = "Ocak|Şubat|Mart|Nisan|Mayıs|Haziran|Temmuz|Ağustos|Eylül|Ekim|Kasım|Aralık|",
    shortMonths = "Oca|Şub|Mar|Nis|May|Haz|Tem|Ağu|Eyl|Eki|Kas|Ara|",
    weekdays = "|Pazar|Pazartesi|Salı|Çarşamba|Perşembe|Cuma|Cumartesi",
    shortWeekdays = "|Paz|Pzt|Sal|Çar|Per|Cum|Cmt",
    amPmStrings = "ÖÖ|ÖS",
)

private val SYMBOLS_PL = symbolsData(
    eras = "p.n.e.|n.e.",
    months = "stycznia|lutego|marca|kwietnia|maja|czerwca|lipca|sierpnia|września|października|listopada|grudnia|",
    shortMonths = "sty|lut|mar|kwi|maj|cze|lip|sie|wrz|paź|lis|gru|",
    weekdays = "|niedziela|poniedziałek|wtorek|środa|czwartek|piątek|sobota",
    shortWeekdays = "|niedz.|pon.|wt.|śr.|czw.|pt.|sob.",
    amPmStrings = "AM|PM",
)

private val SYMBOLS_ROOT = symbolsData(
    eras = "BCE|CE",
    months = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|",
    shortMonths = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|",
    weekdays = "|Sun|Mon|Tue|Wed|Thu|Fri|Sat",
    shortWeekdays = "|Sun|Mon|Tue|Wed|Thu|Fri|Sat",
    amPmStrings = "AM|PM",
)

// Exact `language_COUNTRY` lookups (country upper-cased, language lower-cased).
private val SYMBOLS_EXACT_TABLES: Map<String, DateFormatSymbolsData> = mapOf(
    "en_GB" to SYMBOLS_EN_GB,
    "en_IE" to SYMBOLS_EN_IE,
    "en_IN" to SYMBOLS_EN_GB,
    "en_AU" to SYMBOLS_EN_AU,
    "en_NZ" to SYMBOLS_EN_GB,
    "en_SG" to SYMBOLS_EN_GB,
    "en_HK" to SYMBOLS_EN_GB,
    "en_ZA" to SYMBOLS_EN_GB,
    "en_001" to SYMBOLS_EN_GB,
    "en_CA" to SYMBOLS_EN_CA,
    "en_US" to SYMBOLS_EN,
    "en_PH" to SYMBOLS_EN,
    "fr_CA" to SYMBOLS_FR_CA,
    "zh_TW" to SYMBOLS_ZH_TW,
    "zh_HK" to SYMBOLS_ZH_HK,
    "zh_MO" to SYMBOLS_ZH_HK,
    "pt_PT" to SYMBOLS_PT_PT,
    "es_MX" to SYMBOLS_ES_MX,
    "es_ES" to SYMBOLS_ES,
    "pt_BR" to SYMBOLS_PT,
    "ja_JP" to SYMBOLS_JA,
    "de_DE" to SYMBOLS_DE,
    "fr_FR" to SYMBOLS_FR,
    "zh_CN" to SYMBOLS_ZH,
    "ko_KR" to SYMBOLS_KO,
    "it_IT" to SYMBOLS_IT,
)

private val SYMBOLS_LANG_TABLES: Map<String, DateFormatSymbolsData> = mapOf(
    "en" to SYMBOLS_EN,
    "ja" to SYMBOLS_JA,
    "de" to SYMBOLS_DE,
    "fr" to SYMBOLS_FR,
    "zh" to SYMBOLS_ZH,
    "ko" to SYMBOLS_KO,
    "es" to SYMBOLS_ES,
    "it" to SYMBOLS_IT,
    "pt" to SYMBOLS_PT,
    "ru" to SYMBOLS_RU,
    "ar" to SYMBOLS_AR,
    "hi" to SYMBOLS_HI,
    "nl" to SYMBOLS_NL,
    "sv" to SYMBOLS_SV,
    "tr" to SYMBOLS_TR,
    "pl" to SYMBOLS_PL,
)

private fun localeKeyParts(locale: Locale): Pair<String, String> {
    var language = locale.language.lowercase()
    var country = locale.country.uppercase()
    // The runtime's single-argument Locale(identifier) keeps the whole
    // identifier inside `language` ("en_US" -> "en_us"); recover the parts.
    for (separator in charArrayOf('_', '-')) {
        val index = language.indexOf(separator)
        if (index >= 0) {
            val tail = language.substring(index + 1)
            language = language.substring(0, index)
            if (country.isEmpty()) {
                country = tail.uppercase()
            }
        }
    }
    return language to country
}

private fun resolveSymbolsData(locale: Locale): DateFormatSymbolsData {
    val (language, country) = localeKeyParts(locale)
    if (country.isNotEmpty()) {
        SYMBOLS_EXACT_TABLES["${language}_$country"]?.let { return it }
    }
    SYMBOLS_LANG_TABLES[language]?.let { return it }
    return SYMBOLS_ROOT
}
