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
        fputs("ERROR: Calendar access denied. Grant permissions in System Settings > Privacy & Security > Calendars\n", stderr)
        exit(1)
    }
    sem.signal()
}

sem.wait()

// -----------------------------------------------------------------------------
// Helper: Get or create calendar by name
// -----------------------------------------------------------------------------
func getOrCreateCalendar(name: String) -> EKCalendar? {
    let calendars = store.calendars(for: .event)

    // Try to find existing calendar
    if let existing = calendars.first(where: { $0.title == name }) {
        return existing
    }

    // Create new calendar
    let newCal = EKCalendar(for: .event, eventStore: store)
    newCal.title = name

    // Use default source (usually iCloud or local)
    if let source = store.defaultCalendarForNewEvents?.source {
        newCal.source = source
    } else if let source = store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) {
        newCal.source = source
    } else {
        fputs("ERROR: No suitable calendar source found\n", stderr)
        return nil
    }

    do {
        try store.saveCalendar(newCal, commit: true)
        return newCal
    } catch {
        fputs("ERROR: Failed to create calendar: \(error)\n", stderr)
        return nil
    }
}

// -----------------------------------------------------------------------------
// Helper: Parse ISO 8601 date string
// -----------------------------------------------------------------------------
func parseISODate(_ isoString: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    return formatter.date(from: isoString)
}

// -----------------------------------------------------------------------------
// Command: Create event
// -----------------------------------------------------------------------------
func createEvent(calendarName: String, title: String, start: String, end: String, allDay: Bool, location: String?, notes: String?) -> String? {
    guard let calendar = getOrCreateCalendar(name: calendarName) else {
        return nil
    }

    guard let startDate = parseISODate(start),
          let endDate = parseISODate(end) else {
        fputs("ERROR: Invalid date format. Use ISO 8601 (YYYY-MM-DDTHH:MM:SS)\n", stderr)
        return nil
    }

    let event = EKEvent(eventStore: store)
    event.calendar = calendar
    event.title = title
    event.startDate = startDate
    event.endDate = endDate
    event.isAllDay = allDay

    if let loc = location, !loc.isEmpty {
        event.location = loc
    }

    if let n = notes, !n.isEmpty {
        event.notes = n
    }

    do {
        try store.save(event, span: .thisEvent)
        return event.calendarItemIdentifier
    } catch {
        fputs("ERROR: Failed to create event: \(error)\n", stderr)
        return nil
    }
}

// -----------------------------------------------------------------------------
// Command: Update event
// -----------------------------------------------------------------------------
func updateEvent(uid: String, calendarName: String, title: String?, start: String?, end: String?, allDay: Bool?, location: String?, notes: String?) -> Bool {
    guard let event = store.calendarItem(withIdentifier: uid) as? EKEvent else {
        fputs("ERROR: Event not found with UID: \(uid)\n", stderr)
        return false
    }

    // Update calendar if specified
    if let calName = calendarName.isEmpty ? nil : calendarName {
        if let calendar = getOrCreateCalendar(name: calName) {
            event.calendar = calendar
        }
    }

    // Update title
    if let t = title, !t.isEmpty {
        event.title = t
    }

    // Update dates
    if let startStr = start, let startDate = parseISODate(startStr) {
        event.startDate = startDate
    }

    if let endStr = end, let endDate = parseISODate(endStr) {
        event.endDate = endDate
    }

    // Update all-day flag
    if let ad = allDay {
        event.isAllDay = ad
    }

    // Update location
    if let loc = location {
        event.location = loc.isEmpty ? nil : loc
    }

    // Update notes
    if let n = notes {
        event.notes = n.isEmpty ? nil : n
    }

    do {
        try store.save(event, span: .thisEvent)
        return true
    } catch {
        fputs("ERROR: Failed to update event: \(error)\n", stderr)
        return false
    }
}

// -----------------------------------------------------------------------------
// Command: Delete event
// -----------------------------------------------------------------------------
func deleteEvent(uid: String) -> Bool {
    guard let event = store.calendarItem(withIdentifier: uid) as? EKEvent else {
        fputs("ERROR: Event not found with UID: \(uid)\n", stderr)
        return false
    }

    do {
        try store.remove(event, span: .thisEvent)
        return true
    } catch {
        fputs("ERROR: Failed to delete event: \(error)\n", stderr)
        return false
    }
}

// -----------------------------------------------------------------------------
// Command: Check access (for permission validation)
// -----------------------------------------------------------------------------
func checkAccess() -> Bool {
    // Access already granted if we got here (checked at top)
    print("Calendar access granted")
    return true
}

// -----------------------------------------------------------------------------
// Parse command line arguments
// -----------------------------------------------------------------------------
func printUsage() {
    fputs("""
Usage: calendar_push.swift [command] [options]

Commands:
  --create <calendar> --title <title> --start <iso-date> --end <iso-date> [options]
      Create a new event. Returns UID on success.
      Options:
        --all-day <true|false>  (default: false)
        --location <location>
        --notes <notes>

  --update <uid> <calendar> [options]
      Update an existing event by UID.
      Options:
        --title <title>
        --start <iso-date>
        --end <iso-date>
        --all-day <true|false>
        --location <location>
        --notes <notes>

  --delete <uid>
      Delete an event by UID.

  --check-access
      Check if Calendar access is granted.

Date format: ISO 8601 (YYYY-MM-DDTHH:MM:SS)
Example: 2025-12-10T14:00:00

""", stderr)
}

// Simple argument parser
var args = CommandLine.arguments
args.removeFirst() // Remove script name

guard !args.isEmpty else {
    printUsage()
    exit(1)
}

let command = args.removeFirst()

// -----------------------------------------------------------------------------
// Execute command
// -----------------------------------------------------------------------------
switch command {
case "--create":
    guard args.count >= 2 else {
        fputs("ERROR: --create requires <calendar> --title ... --start ... --end ...\n", stderr)
        printUsage()
        exit(1)
    }

    let calendarName = args.removeFirst()
    var title: String?
    var start: String?
    var end: String?
    var allDay = false
    var location: String?
    var notes: String?

    // Parse remaining arguments
    while !args.isEmpty {
        let flag = args.removeFirst()
        switch flag {
        case "--title":
            title = args.isEmpty ? nil : args.removeFirst()
        case "--start":
            start = args.isEmpty ? nil : args.removeFirst()
        case "--end":
            end = args.isEmpty ? nil : args.removeFirst()
        case "--all-day":
            let value = args.isEmpty ? "false" : args.removeFirst()
            allDay = value.lowercased() == "true"
        case "--location":
            location = args.isEmpty ? nil : args.removeFirst()
        case "--notes":
            notes = args.isEmpty ? nil : args.removeFirst()
        default:
            fputs("ERROR: Unknown flag: \(flag)\n", stderr)
            exit(1)
        }
    }

    guard let t = title, let s = start, let e = end else {
        fputs("ERROR: --create requires --title, --start, and --end\n", stderr)
        exit(1)
    }

    if let uid = createEvent(calendarName: calendarName, title: t, start: s, end: e, allDay: allDay, location: location, notes: notes) {
        print(uid)
        exit(0)
    } else {
        exit(1)
    }

case "--update":
    guard args.count >= 2 else {
        fputs("ERROR: --update requires <uid> <calendar> [options]\n", stderr)
        printUsage()
        exit(1)
    }

    let uid = args.removeFirst()
    let calendarName = args.removeFirst()
    var title: String?
    var start: String?
    var end: String?
    var allDay: Bool?
    var location: String?
    var notes: String?

    // Parse remaining arguments
    while !args.isEmpty {
        let flag = args.removeFirst()
        switch flag {
        case "--title":
            title = args.isEmpty ? nil : args.removeFirst()
        case "--start":
            start = args.isEmpty ? nil : args.removeFirst()
        case "--end":
            end = args.isEmpty ? nil : args.removeFirst()
        case "--all-day":
            let value = args.isEmpty ? "false" : args.removeFirst()
            allDay = value.lowercased() == "true"
        case "--location":
            location = args.isEmpty ? nil : args.removeFirst()
        case "--notes":
            notes = args.isEmpty ? nil : args.removeFirst()
        default:
            fputs("ERROR: Unknown flag: \(flag)\n", stderr)
            exit(1)
        }
    }

    if updateEvent(uid: uid, calendarName: calendarName, title: title, start: start, end: end, allDay: allDay, location: location, notes: notes) {
        print("Event updated successfully")
        exit(0)
    } else {
        exit(1)
    }

case "--delete":
    guard !args.isEmpty else {
        fputs("ERROR: --delete requires <uid>\n", stderr)
        exit(1)
    }

    let uid = args.removeFirst()
    if deleteEvent(uid: uid) {
        print("Event deleted successfully")
        exit(0)
    } else {
        exit(1)
    }

case "--check-access":
    if checkAccess() {
        exit(0)
    } else {
        exit(1)
    }

default:
    fputs("ERROR: Unknown command: \(command)\n", stderr)
    printUsage()
    exit(1)
}
