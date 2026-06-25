# Regnummer

Web app for tracking found Swedish licence plate numbers ending in **001** through **999** (format `AAA NNN`). Runs locally in Emacs via [emacs-web-server](https://github.com/eschulte/emacs-web-server).

## Setup

```elisp
(add-to-list 'load-path "~/prj/emacs-web-server")
(add-to-list 'load-path "~/prj/regnummer")
(require 'regnummer)
(regnummer-start)
```

Open [http://localhost:9099/](http://localhost:9099/) in your browser.

Stop the server with `M-x regnummer-stop`.

## Usage

The page shows the next number to find based on the highest number in the data file. Fill in **Namn** (required), optionally **Plats** (use **Hämta min plats** for browser geolocation), and optionally the full **Registreringsnummer**, then click **Registrera**.

**Namn** is prefilled from the most recent registration. After a successful registration, a short celebration with fireworks and an uplifting quote is shown. Use **Ta bort senaste** below the table to undo the last entry (for mistakes or demos).

All found entries are listed in a table with number, date, finder, and location.

## Data file

Entries are stored in `found-plates.txt`, one per line:

```text
number|date|name|location|plate
```

Example:

```text
42|2026-06-25 14:30|Anna|Göteborg|XYZ 042
43|2026-06-25 16:05|Erik|Stockholm|
```

- **number**: integer 1–999 (no leading zeros in the file)
- **date**: `YYYY-MM-DD HH:MM`
- **name**: who found the plate
- **location**: optional place name
- **plate**: optional full plate (`AAA NNN`)

Lines starting with `#` are ignored.

## Importing existing data

Paste or append lines into `found-plates.txt` using the format above. Reload the page — the next number updates automatically from the highest registered number.
