#!/usr/bin/env swift

import EventKit
import Foundation

let store = EKEventStore()

// -----------------------------------------------------------------------------
// Request calendar access (modern macOS 14+ API)
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// Parse command line arguments
// -----------------------------------------------------------------------------
// Usage: calendar_fetch.swift <calendar_name1>,<calendar_name2>,... <days_behind> <days_ahead>
guard CommandLine.arguments.count >= 4 else {
    fputs("Usage: \(CommandLine.arguments[0]) <calendar_names> <days_behind> <days_ahead>\n", stderr)
    fputs("Example: \(CommandLine.arguments[0]) 'icloud,work' 0 30\n", stderr)
    exit(1)
}

let calendarNames = CommandLine.arguments[1].split(separator: ",").map { String($0) }
let daysBehind = Int(CommandLine.arguments[2]) ?? 0
let daysAhead = Int(CommandLine.arguments[3]) ?? 30

// -----------------------------------------------------------------------------
// Calculate date range
// -----------------------------------------------------------------------------
let now = Date()
let calendar = Calendar.current
let startDate = calendar.date(byAdding: .day, value: -daysBehind, to: now)!
let endDate = calendar.date(byAdding: .day, value: daysAhead, to: now)!

// -----------------------------------------------------------------------------
// Lookup calendars
// -----------------------------------------------------------------------------
let allCalendars = store.calendars(for: .event)
let targetCalendars = calendarNames.compactMap { name in
    allCalendars.first(where: { $0.title == name })
}

if targetCalendars.isEmpty {
    fputs("ERROR: No matching calendars found\n", stderr)
    exit(1)
}

// -----------------------------------------------------------------------------
// Query events with EventKit predicate (fast!)
// -----------------------------------------------------------------------------
let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

// -----------------------------------------------------------------------------
// Date formatter for consistent output
// -----------------------------------------------------------------------------
let df = DateFormatter()
df.locale = Locale(identifier: "en_US_POSIX")
df.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"

// -----------------------------------------------------------------------------
// Output events in pipe-delimited format with extended fields
// Format: CALENDAR|TITLE|START|END|ALLDAY|LOCATION|URL|NOTES|UID
// -----------------------------------------------------------------------------
for ev in events {
    let calTitle = ev.calendar?.title ?? "Unknown"
    let title = ev.title ?? "(No title)"
    let start = df.string(from: ev.startDate)
    let end = df.string(from: ev.endDate)
    let allDay = ev.isAllDay ? "true" : "false"

    // Extended fields (Phase 3)
    let location = ev.location ?? ""
    let url = ev.url?.absoluteString ?? ""
    let notes = ev.notes ?? ""
    let uid = ev.calendarItemIdentifier

    // Escape pipe characters in text fields to prevent parsing issues
    let escapedTitle = title.replacingOccurrences(of: "|", with: "\\|")
    let escapedLocation = location.replacingOccurrences(of: "|", with: "\\|")
    let escapedNotes = notes.replacingOccurrences(of: "|", with: "\\|")

    print("\(calTitle)|\(escapedTitle)|\(start)|\(end)|\(allDay)|\(escapedLocation)|\(url)|\(escapedNotes)|\(uid)")
}
