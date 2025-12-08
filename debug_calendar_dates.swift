#!/usr/bin/env swift

import EventKit
import Foundation

print("=== Calendar Debug Script ===\n")

let store = EKEventStore()

// Request calendar access
let sem = DispatchSemaphore(value: 0)
store.requestFullAccessToEvents { granted, error in
    if let error = error {
        fputs("ERROR: \(error)\n", stderr)
        exit(1)
    }
    if !granted {
        fputs("ERROR: Calendar access denied\n", stderr)
        exit(1)
    }
    sem.signal()
}
sem.wait()

// Print system locale information
print("System Locale Information:")
print("  Current Locale: \(Locale.current.identifier)")
print("  Preferred Languages: \(Locale.preferredLanguages)")
if #available(macOS 13, *) {
    print("  Region Code: \(Locale.current.region?.identifier ?? "unknown")")
} else {
    print("  Region Code: \(Locale.current.regionCode ?? "unknown")")
}
print("  Calendar: \(Locale.current.calendar.identifier)")
print()

// Get all calendars
print("Available Calendars:")
let allCalendars = store.calendars(for: .event)
for cal in allCalendars {
    print("  - \(cal.title)")
}
print()

// Get events from last 7 days to next 30 days
let calendar = Calendar.current
let now = Date()
let startDate = calendar.date(byAdding: .day, value: -7, to: now)!
let endDate = calendar.date(byAdding: .day, value: 30, to: now)!

print("Fetching events from \(startDate) to \(endDate)")
print()

// Query events
let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: allCalendars)
let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

print("Found \(events.count) events")
print()

// Print first 10 events with RAW date information
print("=== RAW EVENT DATA (first 10 events) ===\n")

for (idx, ev) in events.prefix(10).enumerated() {
    print("Event #\(idx + 1):")
    print("  Calendar: \(ev.calendar?.title ?? "Unknown")")
    print("  Title: \(ev.title ?? "(No title)")")
    print("  All Day: \(ev.isAllDay)")
    print()

    // Print raw Date objects
    print("  Raw Date Objects:")
    print("    Start Date: \(String(describing: ev.startDate))")
    print("    End Date: \(String(describing: ev.endDate))")
    print()

    // Print with various DateFormatter configurations
    print("  Formatted Dates:")

    // en_US_POSIX (what the plugin uses)
    let df1 = DateFormatter()
    df1.locale = Locale(identifier: "en_US_POSIX")
    df1.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
    print("    [en_US_POSIX] Start: \(df1.string(from: ev.startDate))")
    print("    [en_US_POSIX] End:   \(df1.string(from: ev.endDate))")
    print()

    // Current system locale
    let df2 = DateFormatter()
    df2.locale = Locale.current
    df2.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
    print("    [System Locale] Start: \(df2.string(from: ev.startDate))")
    print("    [System Locale] End:   \(df2.string(from: ev.endDate))")
    print()

    // ISO8601
    let df3 = ISO8601DateFormatter()
    print("    [ISO8601] Start: \(df3.string(from: ev.startDate))")
    print("    [ISO8601] End:   \(df3.string(from: ev.endDate))")
    print()

    print("---")
    print()
}

print("=== END DEBUG OUTPUT ===")
