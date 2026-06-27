# Regnummer

Web app for tracking found Swedish licence plate numbers ending in **001** through **999** (format `AAA NNN`). Runs locally in Emacs via [emacs-web-server](https://github.com/eschulte/emacs-web-server).

## Setup

```elisp
(add-to-list 'load-path "~/prj/emacs-web-server")
(add-to-list 'load-path "~/prj/regnummer")
(require 'regnummer)
(regnummer-start)
```

All files (HTML, CSS, JS, and `found-plates.txt`) are loaded relative to the package directory, so Emacs's current directory does not matter.

Open [http://localhost:9099/](http://localhost:9099/) in your browser.

Stop the server with `M-x regnummer-stop`.

## Reverse proxy (subpath)

When the app is served under a URL prefix (e.g. `https://example.com/muureg/`), set the base path before starting:

```elisp
(setq regnummer-base-path "/muureg")
(setq regnummer-port 9070)
(require 'regnummer)
(regnummer-start)
```

Or copy [`regnummer-local.el.example`](regnummer-local.el.example) to `regnummer-local.el` in the package directory — it is loaded automatically on `(require 'regnummer)`.

Apache example:

```apache
RedirectMatch 301 ^/muureg$ /muureg/
RequestHeader set X-Forwarded-Prefix "/muureg"
ProxyPass        /muureg/  http://127.0.0.1:9070/
ProxyPassReverse /muureg/  http://127.0.0.1:9070/
```

`RequestHeader` requires `mod_headers` (`a2enmod headers`). The app also reads `X-Forwarded-Prefix` when `regnummer-base-path` is empty.

After deploying, restart Emacs or run `M-x regnummer-stop` then `M-x regnummer-start` so the HTML template cache is cleared.

Verify in the browser (View Source): CSS should be `/muureg/static/regnummer.css`, not `/static/regnummer.css`.

The backend still receives paths without the prefix (`/static/…`, `/register`, etc.); the base path ensures HTML links, forms, and redirects use the public URL.

## Usage

The page shows the next number to find based on the highest number in the data file. Fill in **Namn** (required), optionally **Plats** (use **Hämta min plats** for browser geolocation), and optionally the full **Registreringsnummer**, then click **Registrera**.

**Namn** is remembered in your browser (localStorage) so it stays filled in across visits. After a successful registration, a short celebration with fireworks and an uplifting quote is shown. Use **Ta bort senaste** below the table to undo the last entry (for mistakes or demos).

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
