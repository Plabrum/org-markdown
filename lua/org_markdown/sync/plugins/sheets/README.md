# Google Sheets Sync Plugin

Sync data from Google Sheets into your markdown files. Perfect for tracking data, importing tables, or managing structured information.

## What This Plugin Does

The Sheets plugin fetches data from specified Google Sheets and formats them into markdown tables in a dedicated sync file. The file is auto-managed (completely replaced on each sync), so your spreadsheet data is always up-to-date.

## Prerequisites

1. **gcloud CLI** - Google's command-line tool for API access
   - Check if installed: `gcloud --version`
   - Install if needed: https://cloud.google.com/sdk/docs/install

2. **Google Account** - You'll need access to Google Cloud Console

## Setup Instructions

### Step 1: Authenticate with Google Cloud

```bash
gcloud auth login
```

This opens your browser for Google OAuth. Log in with your Google account.

### Step 2: Create or Select a Project

```bash
# List your existing projects
gcloud projects list

# If you have a project, set it as default
gcloud config set project YOUR-PROJECT-ID

# Or create a new project
gcloud projects create my-org-markdown-project --name="org-markdown"
gcloud config set project my-org-markdown-project
```

### Step 3: Enable Google Sheets API

```bash
gcloud services enable sheets.googleapis.com
```

This allows your project to access Google Sheets data.

### Step 4: Create an API Key

```bash
# Install alpha commands (if not already installed)
gcloud components install alpha --quiet

# Create a restricted API key
gcloud alpha services api-keys create \
  --display-name="org-markdown-sync" \
  --api-target=service=sheets.googleapis.com
```

The command will output your API key. It looks like:
```
AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

**Copy this key!** You'll need it for configuration.

## Configuration

Add the Sheets plugin configuration to your Neovim config:

```lua
require('org_markdown').setup({
  sync = {
    plugins = {
      sheets = {
        enabled = true,
        api_key = "AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",  -- Your API key from Step 4
        sheets = {
          {
            name = "My Data",                          -- Name for the section
            spreadsheet_id = "1ABC...xyz",             -- From the sheets URL
            range = "Sheet1!A1:D10",                   -- Which cells to fetch
          },
          -- Add more sheets as needed
          {
            name = "Weekly Goals",
            spreadsheet_id = "1XYZ...abc",
            range = "Goals!A:C",
          },
        },
      },
    },
  },
})
```

### Finding Your Spreadsheet ID

The spreadsheet ID is in the Google Sheets URL:
```
https://docs.google.com/spreadsheets/d/1ABC123xyz456/edit
                                      └─── this part ───┘
```

### Range Format

Use A1 notation to specify which cells to fetch:
- `Sheet1!A1:D10` - Cells A1 through D10 on Sheet1
- `Data!A:C` - All rows in columns A, B, C on the "Data" tab
- `A1:B5` - Uses the default sheet

## Usage

### Sync Manually

```vim
:MarkdownSyncSheets
```

Or use the default keymap (if configured):
```
<leader>oss
```

### Auto-Sync (Optional)

Enable automatic syncing to keep data fresh:

```lua
sync = {
  plugins = {
    sheets = {
      enabled = true,
      api_key = "...",
      auto_sync = true,              -- Enable auto-sync
      sync_interval = 3600,           -- Sync every hour (in seconds)
      sheets = { ... },
    },
  },
}
```

## Output Format

The plugin creates a file at `~/org/sheets.md` (configurable) with markdown tables:

```markdown
# Google Sheets Sync

Last synced: 2025-12-06 08:15:32

## My Data

| Column A | Column B | Column C | Column D |
|----------|----------|----------|----------|
| Value 1  | Value 2  | Value 3  | Value 4  |
| ...      | ...      | ...      | ...      |

## Weekly Goals

| Goal | Status | Notes |
|------|--------|-------|
| ... | ... | ... |

---
Synced 2 sheets (15 total rows)
```

## Troubleshooting

### "API key not valid"
- Make sure you enabled the Sheets API: `gcloud services enable sheets.googleapis.com`
- Check that your API key isn't restricted to different APIs
- Verify the key is correct (no extra spaces or characters)

### "Permission denied" or "Spreadsheet not found"
- Make sure the spreadsheet is shared with "Anyone with the link can view"
- Or share it with your Google account email
- Check that the spreadsheet ID is correct

### "Range not found"
- Verify the sheet tab name matches exactly (case-sensitive)
- Check that the range exists in your spreadsheet
- Use simpler ranges like `A:D` if specific ranges fail

## Security Notes

- **API Key Security**: Your API key is stored in your Neovim config. Don't commit it to public repositories.
- **Restricted Access**: The API key created above is restricted to only access Google Sheets (safe)
- **Read-Only**: This plugin only reads data from sheets, it never modifies them

## Advanced Configuration

```lua
sync = {
  plugins = {
    sheets = {
      enabled = true,
      api_key = "...",
      sync_file = "~/org/sheets.md",           -- Custom output file
      auto_sync = true,
      sync_interval = 1800,                    -- 30 minutes
      sheets = {
        {
          name = "Budget",
          spreadsheet_id = "...",
          range = "2025!A:F",                  -- Specific tab
          header_row = true,                   -- First row as headers
        },
      },
    },
  },
}
```

## Need Help?

- Check Google Sheets API docs: https://developers.google.com/sheets/api
- gcloud CLI reference: https://cloud.google.com/sdk/gcloud/reference
- File an issue: https://github.com/Plabrum/org-markdown/issues
