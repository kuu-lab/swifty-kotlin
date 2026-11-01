private let abi = RuntimeABISectionBuilder("DateTime")

public extension RuntimeABISpec {
    static let dateTimeFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_calendar_create", "timeZoneRaw"),
        abi.nt("__kk_calendar_create_fields", "timeZoneRaw year month day hour minute second"),
        abi.nt("__kk_calendar_get_time_in_millis", "calendarRaw"),
        abi.nt("__kk_calendar_set_time_in_millis", "calendarRaw value", ret: .void),
        abi.nt("__kk_calendar_get_field", "calendarRaw field"),
        abi.nt("__kk_calendar_set_field", "calendarRaw field value", ret: .void),
        abi.nt("__kk_calendar_add_field", "calendarRaw field amount", ret: .void),
        abi.nt("__kk_calendar_get_time_zone", "calendarRaw"),
        abi.nt("__kk_calendar_set_time_zone", "calendarRaw timeZoneRaw", ret: .void),
        abi.nt("__kk_time_zone_get_default"),
        abi.nt("__kk_time_zone_get_time_zone", "idRaw"),
        abi.nt("__kk_time_zone_get_id", "timeZoneRaw"),
        abi.nt("__kk_time_zone_get_raw_offset", "timeZoneRaw"),
        abi.nt("__kk_time_zone_get_offset", "timeZoneRaw epochMilliseconds"),
    ]
}
