# Calendar Date Debug Script

This script prints raw calendar date information to help debug date parsing issues on different machines.

## Usage

Run the script:

```bash
./debug_calendar_dates.swift > calendar_debug_output.txt 2>&1
```

This will:
1. Request calendar access (you may see a system prompt)
2. Print system locale information
3. List all available calendars
4. Fetch events from the last 7 days and next 30 days
5. Print the first 10 events with their raw date data in multiple formats

## What it outputs

For each event, you'll see:
- **Calendar name** and **title**
- **Raw Date objects** (Swift's native format)
- **en_US_POSIX format** (what the plugin expects): `"Saturday, November 22, 2025 at 2:00:00 PM"`
- **System locale format** (what your machine might be using)
- **ISO8601 format** (for reference)

## Send the output

After running the script, send the `calendar_debug_output.txt` file for analysis. This will help identify:
- Locale differences between machines
- Date format variations
- System configuration issues

## Example command

```bash
# Run and save output
./debug_calendar_dates.swift > calendar_debug_output.txt 2>&1

# View the output
cat calendar_debug_output.txt

# Or open in your editor
vim calendar_debug_output.txt
```
