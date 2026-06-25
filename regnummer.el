;;; regnummer.el --- Register Swedish licence plate endings 001-999 -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Free Software Foundation, Inc.

;; Author: Mathias
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.3"))

;;; Commentary:

;; Web app for tracking found Swedish licence plate numbers ending in
;; 001 through 999.  Runs locally in Emacs using the web-server package.

;;; Code:

(require 'web-server)
(require 'cl-lib)

(defvar regnummer-port 9099
  "TCP port for the Regnummer web server.")

(defvar regnummer-server nil
  "Running web-server instance, or nil.")

(defvar regnummer--root nil
  "Absolute directory containing regnummer.el.")

(defvar regnummer-html nil
  "Cached HTML page template.")

(defun regnummer--root-dir ()
  "Return the absolute directory containing regnummer.el."
  (or regnummer--root
      (error "Regnummer root directory is unknown; reload with (require 'regnummer)")))

(defun regnummer--file (name)
  "Expand NAME relative to the Regnummer package directory."
  (expand-file-name name (regnummer--root-dir)))

(defconst regnummer-data-file "found-plates.txt"
  "Data file name, relative to the package directory.")

(defun regnummer--data-file ()
  "Return absolute path to the data file."
  (regnummer--file regnummer-data-file))

(defun regnummer--write-data-file (start end)
  "Write buffer region START to END to the data file as UTF-8."
  (let ((coding-system-for-write 'utf-8-unix))
    (write-region start end (regnummer--data-file) nil 'silent)))

(defun regnummer--load-file (name)
  "Read file NAME from the regnummer directory."
  (with-temp-buffer
    (insert-file-contents (regnummer--file name))
    (buffer-string)))

(defun regnummer--ensure-data-file ()
  "Create the data file if it does not exist."
  (unless (file-exists-p (regnummer--data-file))
    (with-temp-buffer
      (insert "# Regnummer data file\n")
      (regnummer--write-data-file (point-min) (point-max)))))

(defun regnummer-escape (string)
  "HTML-escape STRING for safe inclusion in pages."
  (let ((s (or string "")))
    (if (fboundp 'xml-escape-string)
        (xml-escape-string s)
      (replace-regexp-in-string
       "[&<>\"']"
       '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;")
         ("\"" . "&quot;") ("'" . "&#39;"))
       s))))

(defun regnummer-format-number (number)
  "Format NUMBER as a three-digit plate suffix."
  (format "%03d" number))

(defun regnummer-parse-line (line)
  "Parse one pipe-delimited LINE into a property list, or nil."
  (let ((parts (split-string line "|")))
    (when (>= (length parts) 4)
      (list :number (string-to-number (nth 0 parts))
            :date (nth 1 parts)
            :name (nth 2 parts)
            :location (nth 3 parts)
            :plate (or (nth 4 parts) "")))))

(defun regnummer-read-entries ()
  "Return all entries from `regnummer-data-file', newest last."
  (regnummer--ensure-data-file)
  (with-temp-buffer
    (insert-file-contents (regnummer--data-file))
    (goto-char (point-min))
    (cl-loop while (not (eobp))
             for line = (string-trim
                         (buffer-substring-no-properties
                          (line-beginning-position)
                          (line-end-position)))
             unless (or (string-empty-p line)
                        (string-prefix-p "#" line))
             for entry = (regnummer-parse-line line)
             when entry
             collect entry
             do (forward-line 1))))

(defun regnummer-next-number (&optional entries)
  "Return the next number to find, or nil when 999 is complete."
  (let ((entries (or entries (regnummer-read-entries))))
    (if (null entries)
        1
      (let ((max-num (apply #'max (mapcar (lambda (e) (plist-get e :number))
                                          entries))))
        (if (>= max-num 999) nil (+ max-num 1))))))

(defun regnummer-last-name (entries)
  "Return the name from the most recent entry in ENTRIES."
  (when entries
    (plist-get (car (last entries)) :name)))

(defun regnummer-remove-last-entry ()
  "Remove the last data line from `regnummer-data-file'.
Return the removed entry plist, or nil if none."
  (let ((entries (regnummer-read-entries)))
    (when entries
      (let ((removed (car (last entries))))
        (with-temp-buffer
          (insert-file-contents (regnummer--data-file))
          (goto-char (point-min))
          (let (last-start)
            (while (not (eobp))
              (let ((line-start (line-beginning-position))
                    (line (string-trim
                           (buffer-substring-no-properties
                            (line-beginning-position)
                            (line-end-position)))))
                (unless (or (string-empty-p line) (string-prefix-p "#" line))
                  (setq last-start line-start))
                (forward-line 1)))
            (when last-start
              (goto-char last-start)
              (delete-region (line-beginning-position)
                             (min (1+ (line-end-position)) (point-max)))
              (regnummer--write-data-file (point-min) (point-max))))
        removed)))))

(defun regnummer-append-entry (number name location plate)
  "Append one entry to `regnummer-data-file'."
  (regnummer--ensure-data-file)
  (let ((line (format "%d|%s|%s|%s|%s\n"
                      number
                      (format-time-string "%Y-%m-%d %H:%M")
                      name
                      location
                      plate)))
    (with-temp-buffer
      (insert-file-contents (regnummer--data-file))
      (goto-char (point-max))
      (insert line)
      (regnummer--write-data-file (point-min) (point-max)))))

(defun regnummer-field (headers field)
  "Return form FIELD from request HEADERS."
  (let ((val (cdr (assoc field headers))))
    (cond
     ((null val) "")
     ((consp val) (or (cdr (assoc 'content val)) ""))
     (t val))))

(defun regnummer-trim (string)
  "Trim whitespace from STRING."
  (if (fboundp 'string-trim)
      (string-trim string)
    (replace-regexp-in-string "\\`[[:space:]]*\\|[[:space:]]*\\'" "" string)))

(defun regnummer-valid-plate-p (plate number)
  "Return non-nil when PLATE matches AAA NNN and suffix equals NUMBER."
  (and (string-match-p "\\`[A-ZÅÄÖa-zåäö]\\{3\\} [0-9]\\{3\\}\\'" plate)
       (= (string-to-number (substring plate 4)) number)))

(defun regnummer-request-path (headers)
  "Return the request path without a leading slash."
  (let ((path (or (cdr (assoc :GET headers))
                  (cdr (assoc :POST headers))
                  "/")))
    (if (string-prefix-p "/" path)
        (substring path 1)
      path)))

(defun regnummer--parse-date (date-str)
  "Parse DATE-STR (YYYY-MM-DD HH:MM) to decoded time, or nil."
  (when (and date-str (not (string-empty-p date-str)))
    (condition-case nil
        (if (string-match
             "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\) \\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)\\'"
             date-str)
            (encode-time 0
                         (string-to-number (match-string 5 date-str))
                         (string-to-number (match-string 4 date-str))
                         (string-to-number (match-string 3 date-str))
                         (string-to-number (match-string 2 date-str))
                         (string-to-number (match-string 1 date-str)))
          (let ((decoded (parse-time-string date-str)))
            (if (and (listp decoded) (>= (length decoded) 6))
                (apply #'encode-time decoded)
              (apply #'encode-time (decode-time decoded)))))
      (error nil))))

(defun regnummer--date-day (time)
  "Return calendar day YYYY-MM-DD for decoded TIME."
  (format-time-string "%Y-%m-%d" time))

(defun regnummer--days-between (t1 t2)
  "Return fractional days from decoded time T1 to T2."
  (/ (- (float-time t2) (float-time t1)) 86400.0))

(defun regnummer--format-days (days)
  "Format DAYS as a one-decimal Swedish-style string, or em dash."
  (if (null days)
      "–"
    (replace-regexp-in-string "\\." "," (format "%.1f" days))))

(defun regnummer--format-pct (fraction)
  "Format FRACTION (0–1) as an integer percentage string."
  (if (null fraction)
      "–"
    (format "%d %%" (round (* fraction 100)))))

(defun regnummer--mean (numbers)
  "Return arithmetic mean of NUMBERS, or nil when empty."
  (when numbers
    (/ (apply #'+ numbers) (float (length numbers)))))

(defun regnummer--median (numbers)
  "Return median of NUMBERS, or nil when empty."
  (when numbers
    (let* ((sorted (sort (copy-sequence numbers) #'<))
           (n (length sorted))
           (mid (/ n 2)))
      (if (cl-oddp n)
          (nth mid sorted)
        (/ (+ (nth (1- mid) sorted) (nth mid sorted)) 2.0)))))

(defun regnummer--add-days (time days)
  "Add DAYS (float) to decoded TIME."
  (time-add time (seconds-to-time (round (* days 86400.0)))))

(defun regnummer--format-date (time)
  "Format decoded TIME as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d" time))

(defun regnummer--entry-time (entry)
  "Return decoded time for ENTRY, or nil."
  (regnummer--parse-date (plist-get entry :date)))

(defun regnummer--times-with-days (entries)
  "Return alist of (decoded-time . calendar-day) for ENTRIES with valid dates."
  (cl-loop for entry in entries
           for time = (regnummer--entry-time entry)
           when time
           collect (cons time (regnummer--date-day time))))

(defun regnummer--gaps-days (times)
  "Return list of day gaps between consecutive decoded times."
  (when (cdr times)
    (cl-loop for prev = (car times) then curr
             for curr in (cdr times)
             collect (regnummer--days-between prev curr))))

(defun regnummer--consecutive-days-p (day1 day2)
  "Return non-nil when DAY2 is the calendar day after DAY1."
  (and day1 day2
       (string= day2
                (regnummer--date-day
                 (time-add (regnummer--parse-date (concat day1 " 12:00"))
                           (* 86400 1))))))

(defun regnummer--current-streak (day-strings)
  "Return consecutive-day streak ending on the last day in DAY-STRINGS."
  (when day-strings
    (let* ((days (sort (delete-dups (copy-sequence day-strings)) #'string<))
           (streak 1))
      (when (> (length days) 1)
        (cl-loop for i from (1- (length days)) downto 1
                 while (regnummer--consecutive-days-p (nth (1- i) days)
                                                        (nth i days))
                 do (cl-incf streak)))
      streak)))

(defun regnummer--rolling-mean (numbers window)
  "Mean of the last WINDOW items in NUMBERS, or nil."
  (when (and numbers (> (length numbers) 0))
    (regnummer--mean (nthcdr (max 0 (- (length numbers) window)) numbers))))

(defun regnummer--count-by (items key-fn)
  "Count ITEMS grouped by KEY-FN; return alist sorted by count descending."
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (item items)
      (let ((key (funcall key-fn item)))
        (when (and key (not (string-empty-p key)))
          (puthash key (1+ (gethash key counts 0)) counts))))
    (let (result)
      (maphash (lambda (k v) (push (cons k v) result)) counts)
      (sort result (lambda (a b) (> (cdr a) (cdr b)))))))

(defun regnummer--sessions (entries &optional gap-hours)
  "Group ENTRIES into sessions separated by GAP-HOURS (default 2)."
  (let* ((gap-secs (* 3600 (or gap-hours 2)))
         (sorted (sort (copy-sequence entries)
                       (lambda (a b)
                         (< (float-time (or (regnummer--entry-time a)
                                            '(0 0)))
                            (float-time (or (regnummer--entry-time b)
                                            '(0 0)))))))
         (sessions nil)
         (current nil)
         (last-time nil))
    (dolist (entry sorted)
      (let ((time (regnummer--entry-time entry)))
        (when time
          (if (and last-time
                   (> (- (float-time time) (float-time last-time)) gap-secs))
              (progn
                (when current (push (nreverse current) sessions))
                (setq current (list entry))
                (setq last-time time))
            (push entry current)
            (setq last-time time)))))
    (when current (push (nreverse current) sessions))
    (nreverse sessions)))

(defun regnummer--milestone-days (entries first-time)
  "Return alist of (milestone . days-from-start) for completed hundreds."
  (when (and entries first-time)
    (let ((by-num (cl-loop for e in entries
                           collect (cons (plist-get e :number) e))))
      (cl-loop for m from 100 to 900 by 100
               for entry = (cdr (assoc m by-num))
               for time = (and entry (regnummer--entry-time entry))
               when time
               collect (cons m (regnummer--days-between first-time time))))))

(defun regnummer-compute-stats (entries)
  "Compute statistics plist from ENTRIES."
  (let* ((count (length entries))
         (max-num (if entries
                      (apply #'max (mapcar (lambda (e) (plist-get e :number))
                                           entries))
                    0))
         (now (current-time))
         (times-days (regnummer--times-with-days entries))
         (times (mapcar #'car times-days))
         (day-strings (mapcar #'cdr times-days))
         (first-time (car times))
         (last-time (car (last times)))
         (gaps (regnummer--gaps-days times))
         (mean-gap (regnummer--mean gaps))
         (median-gap (regnummer--median gaps))
         (rolling-gap (regnummer--rolling-mean gaps 10))
         (remaining (- 999 max-num))
         (total-hunt-days (and first-time last-time
                               (regnummer--days-between first-time
                                                        (if (>= max-num 999)
                                                            last-time
                                                          now))))
         (days-since-last (and last-time
                               (regnummer--days-between last-time now)))
         (finds-per-week (and total-hunt-days (> total-hunt-days 0)
                              (* count (/ 7.0 total-hunt-days))))
         (finds-per-month (and total-hunt-days (> total-hunt-days 0)
                               (* count (/ 30.0 total-hunt-days))))
         (days-remaining (and mean-gap (>= count 2) (* remaining mean-gap)))
         (eta-full (and days-remaining last-time
                        (regnummer--add-days now days-remaining)))
         (eta-rolling (and rolling-gap (>= count 2)
                           (regnummer--add-days now (* remaining rolling-gap))))
         (longest-gap (when gaps (apply #'max gaps)))
         (shortest-gap (when gaps (apply #'min gaps)))
         (finder-counts (regnummer--count-by entries
                                             (lambda (e) (plist-get e :name))))
         (top-finder (car finder-counts))
         (locations (cl-remove-if #'string-empty-p
                                  (mapcar (lambda (e) (plist-get e :location))
                                          entries)))
         (location-counts (regnummer--count-by entries
                                               (lambda (e) (plist-get e :location))))
         (top-location (car location-counts))
         (with-plate (cl-count-if
                      (lambda (e)
                        (not (string-empty-p (plist-get e :plate))))
                      entries))
         (next-milestone (when (and (> max-num 0) (< max-num 999))
                           (* 100 (1+ (/ max-num 100)))))
         (to-milestone (and next-milestone (- next-milestone max-num)))
         (eta-milestone (and to-milestone mean-gap (>= count 2)
                             (regnummer--add-days now (* to-milestone mean-gap))))
         (day-counts (regnummer--count-by entries
                                          (lambda (e)
                                            (let ((entry-time (regnummer--entry-time e)))
                                              (and entry-time
                                                   (regnummer--date-day entry-time))))))
         (busiest-day (car day-counts))
         (night-count (cl-count-if
                       (lambda (e)
                         (let ((entry-time (regnummer--entry-time e)))
                           (when entry-time
                             (>= (string-to-number
                                  (format-time-string "%H" entry-time))
                                 18))))
                       entries))
         (sessions (regnummer--sessions entries))
         (avg-session (and sessions (/ count (float (length sessions)))))
         (milestones (regnummer--milestone-days entries first-time))
         (streak (regnummer--current-streak day-strings)))
    (list :count count
          :max-num max-num
          :progress-pct (if (> max-num 0) (/ max-num 999.0) 0)
          :mean-gap mean-gap
          :median-gap median-gap
          :rolling-gap rolling-gap
          :days-since-last days-since-last
          :total-hunt-days total-hunt-days
          :finds-per-week finds-per-week
          :finds-per-month finds-per-month
          :days-remaining days-remaining
          :eta-full eta-full
          :eta-rolling eta-rolling
          :longest-gap longest-gap
          :shortest-gap shortest-gap
          :top-finder top-finder
          :unique-locations (length (delete-dups locations))
          :top-location top-location
          :with-plate with-plate
          :plate-pct (if (> count 0) (/ with-plate (float count)) nil)
          :next-milestone next-milestone
          :to-milestone to-milestone
          :eta-milestone eta-milestone
          :busiest-day busiest-day
          :night-count night-count
          :day-count (- count night-count)
          :night-pct (if (> count 0) (/ night-count (float count)) nil)
          :avg-session avg-session
          :session-count (length sessions)
          :milestones milestones
          :streak streak
          :complete (>= max-num 999))))

(defun regnummer-render-stat-item (label value &optional hint)
  "Render one stat card with LABEL, VALUE, and optional HINT."
  (format "<div class=\"stat-item\">
  <span class=\"stat-label\">%s</span>
  <span class=\"stat-value\">%s</span>%s
</div>"
          (regnummer-escape label)
          value
          (if hint
              (format "\n  <span class=\"stat-hint\">%s</span>"
                      (regnummer-escape hint))
            "")))

(defun regnummer-render-stat-grid (items)
  "Render stat ITEMS alist of (label value &optional hint) as a grid."
  (format "<div class=\"stat-grid\">%s</div>"
          (mapconcat (lambda (item)
                       (apply #'regnummer-render-stat-item item))
                     items
                     "")))

(defun regnummer-render-stats (entries)
  "Render the statistics section for ENTRIES."
  (let ((s (regnummer-compute-stats entries)))
    (if (zerop (plist-get s :count))
        "<section class=\"stats-section section\">
  <h2>Statistik</h2>
  <p class=\"empty-table\">Ingen statistik ännu — registrera det första numret!</p>
</section>"
      (let* ((count (plist-get s :count))
             (max-num (plist-get s :max-num))
             (complete (plist-get s :complete))
             (fmt-days #'regnummer--format-days)
             (fmt-date (lambda (time)
                         (if time (regnummer--format-date time) "–")))
             (primary
              (list
               (list "Framsteg"
                     (format "%d / 999 <span class=\"stat-sub\">(%s)</span>"
                             max-num
                             (regnummer--format-pct (plist-get s :progress-pct))))
               (list "Snitt mellan fynd" (funcall fmt-days (plist-get s :mean-gap))
                     "dagar")
               (list "Median mellan fynd" (funcall fmt-days (plist-get s :median-gap))
                     "dagar")
               (list "Rullande snitt (10)" (funcall fmt-days (plist-get s :rolling-gap))
                     "dagar")
               (list "Dagar sedan senaste" (funcall fmt-days (plist-get s :days-since-last)))
               (list "Total jakttid" (funcall fmt-days (plist-get s :total-hunt-days))
                     "dagar")
               (list "Fynd per vecka"
                     (if (plist-get s :finds-per-week)
                         (replace-regexp-in-string
                          "\\." ","
                          (format "%.2f" (plist-get s :finds-per-week)))
                       "–"))
               (list "Fynd per månad"
                     (if (plist-get s :finds-per-month)
                         (replace-regexp-in-string
                          "\\." ","
                          (format "%.2f" (plist-get s :finds-per-month)))
                       "–"))))
             (projections
              (unless complete
                (list
                 (list "Kvar att hitta" (format "%d" (- 999 max-num)))
                 (list "Beräknade dagar kvar"
                       (funcall fmt-days (plist-get s :days-remaining)))
                 (list "Beräknad klar (snitt)"
                       (funcall fmt-date (plist-get s :eta-full))
                       "vid nuvarande snitt")
                 (list "Beräknad klar (rullande)"
                       (funcall fmt-date (plist-get s :eta-rolling))
                       "senaste 10 fynd"))))
             (gaps-streaks
              (list
               (list "Längsta paus" (funcall fmt-days (plist-get s :longest-gap)) "dagar")
               (list "Kortaste paus" (funcall fmt-days (plist-get s :shortest-gap)) "dagar")
               (list "Nuvarande streak"
                     (if (plist-get s :streak)
                         (format "%d dagar" (plist-get s :streak))
                       "–"))))
             (people-places
              (list
               (list "Mest aktiv spanare"
                     (if (plist-get s :top-finder)
                         (format "%s (%d)"
                                 (regnummer-escape (car (plist-get s :top-finder)))
                                 (cdr (plist-get s :top-finder)))
                       "–"))
               (list "Unika platser"
                     (format "%d" (plist-get s :unique-locations)))
               (list "Vanligaste plats"
                     (if (plist-get s :top-location)
                         (format "%s (%d)"
                                 (regnummer-escape (car (plist-get s :top-location)))
                                 (cdr (plist-get s :top-location)))
                       "–"))
               (list "Med registreringsnummer"
                     (format "%d / %d (%s)"
                             (plist-get s :with-plate) count
                             (regnummer--format-pct (plist-get s :plate-pct))))))
             (milestones-text
              (let ((ms (plist-get s :milestones))
                    (next (plist-get s :next-milestone))
                    (to (plist-get s :to-milestone)))
                (concat
                 (if ms
                     (format "<ul class=\"milestone-list\">%s</ul>"
                             (mapconcat
                              (lambda (m)
                                (format "<li>%03d: %s dagar från start</li>"
                                        (car m)
                                        (funcall fmt-days (cdr m))))
                              ms
                              ""))
                   "<p class=\"milestone-empty\">Inga hundratal nådda ännu.</p>")
                 (when next
                   (format "<p class=\"milestone-next\">Nästa milstolpe: %s (%d kvar, beräknad %s)</p>"
                           (regnummer-format-number next)
                           to
                           (funcall fmt-date (plist-get s :eta-milestone)))))))
             (fun
              (list
               (list "Mest produktiva dagen"
                     (if (plist-get s :busiest-day)
                         (format "%s (%d fynd)"
                                 (regnummer-escape (car (plist-get s :busiest-day)))
                                 (cdr (plist-get s :busiest-day)))
                       "–"))
               (list "Dags-/kvällsfynd"
                     (format "%d / %d"
                             (plist-get s :day-count)
                             (plist-get s :night-count))
                     "före / efter kl. 18")
               (list "Kvällsandel"
                     (regnummer--format-pct (plist-get s :night-pct)))
               (list "Snitt per session"
                     (if (plist-get s :avg-session)
                         (replace-regexp-in-string
                          "\\." ","
                          (format "%.1f" (plist-get s :avg-session)))
                       "–")
                     (format "%d sessioner" (plist-get s :session-count))))))
        (format "<section class=\"stats-section section\">
  <h2>Statistik</h2>
  <h3 class=\"stats-group-title\">Framsteg &amp; tempo</h3>
  %s
  %s
  <h3 class=\"stats-group-title\">Pauser &amp; streaks</h3>
  %s
  <h3 class=\"stats-group-title\">Spanare &amp; platser</h3>
  %s
  <h3 class=\"stats-group-title\">Milstolpar</h3>
  %s
  <h3 class=\"stats-group-title\">Kul statistik</h3>
  %s
</section>"
                (regnummer-render-stat-grid primary)
                (if projections
                    (concat "<h3 class=\"stats-group-title\">Prognos till 999</h3>\n"
                            (regnummer-render-stat-grid projections))
                  "")
                (regnummer-render-stat-grid gaps-streaks)
                (regnummer-render-stat-grid people-places)
                milestones-text
                (regnummer-render-stat-grid fun))))))

(defun regnummer-render-next-number (next)
  "Render the next-number banner for NEXT."
  (if next
      (format "<div class=\"next-number\">
  <span class=\"label\">Nästa nummer att hitta</span>
  <span class=\"value\">%s</span>
</div>"
              (regnummer-escape (regnummer-format-number next)))
    "<div class=\"next-number complete\">
  <span class=\"label\">Status</span>
  <span class=\"value\">Klart! Alla nummer 001–999 är registrerade.</span>
</div>"))

(defun regnummer-render-error (error)
  "Render optional ERROR banner."
  (when error
    (format "<div class=\"error-banner\">%s</div>"
            (regnummer-escape error))))

(defun regnummer-render-form (next &optional values)
  "Render the registration form for NEXT with optional VALUES alist."
  (unless next
    (cl-return-from regnummer-render-form ""))
  (let* ((vals (or values '()))
         (entries (regnummer-read-entries))
         (name (or (cdr (assoc "name" vals))
                   (regnummer-last-name entries)
                   ""))
         (location (or (cdr (assoc "location" vals)) ""))
         (plate (or (cdr (assoc "plate" vals)) "")))
    (format "<section>
  <h2>Registrera hittat nummer</h2>
  <form method=\"post\" action=\"/register\">
    <input type=\"hidden\" name=\"number\" value=\"%d\">
    <div class=\"form-row\">
      <label for=\"name\">Namn</label>
      <input type=\"text\" id=\"name\" name=\"name\" required
             value=\"%s\" autocomplete=\"name\">
    </div>
    <div class=\"form-row\">
      <label for=\"location\">Plats</label>
      <div class=\"location-row\">
        <input type=\"text\" id=\"location\" name=\"location\"
               value=\"%s\" autocomplete=\"off\"
               placeholder=\"Valfritt\">
        <button type=\"button\" id=\"location-btn\">Hämta min plats</button>
      </div>
      <div id=\"location-msg\" class=\"location-msg\"></div>
    </div>
    <div class=\"form-row\">
      <label for=\"plate\">Registreringsnummer</label>
      <input type=\"text\" id=\"plate\" name=\"plate\"
             value=\"%s\"
             placeholder=\"ABC %s\"
             autocomplete=\"off\">
    </div>
    <input type=\"submit\" value=\"Registrera\">
  </form>
</section>"
            next
            (regnummer-escape name)
            (regnummer-escape location)
            (regnummer-escape plate)
            (regnummer-format-number next))))

(defun regnummer-render-table (entries)
  "Render the entries table for ENTRIES."
  (let ((rows
         (mapconcat
          (lambda (entry)
            (format "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>"
                    (regnummer-escape
                     (regnummer-format-number (plist-get entry :number)))
                    (regnummer-escape (plist-get entry :date))
                    (regnummer-escape (plist-get entry :name))
                    (regnummer-escape (plist-get entry :location))))
          (reverse entries)
          "")))
    (format "<section>
  <h2>Hittade nummer</h2>
  %s
</section>"
            (if (string-empty-p rows)
                "<p class=\"empty-table\">Inga nummer registrerade ännu.</p>"
              (format "<table>
  <thead>
    <tr><th>Nummer</th><th>Datum</th><th>Hittad av</th><th>Plats</th></tr>
  </thead>
  <tbody>%s</tbody>
</table>
<form class=\"undo-form\" method=\"post\" action=\"/remove-last\"
      onsubmit=\"return confirm('Ta bort senaste registreringen?');\">
  <button type=\"submit\">Ta bort senaste</button>
</form>" rows)))))

(defun regnummer-render-page (&optional error values)
  "Render the full HTML page with optional ERROR and form VALUES."
  (unless regnummer-html
    (setq regnummer-html (regnummer--load-file "regnummer.html")))
  (let* ((entries (regnummer-read-entries))
         (next (regnummer-next-number entries))
         (body (concat "<main>"
                       "<h1>Regnummer</h1>"
                       "<p class=\"subtitle\">Ka-chow! Jakten på skyltar 001–999 — från Radiator Springs till 999.</p>"
                       (regnummer-render-error error)
                       (regnummer-render-next-number next)
                       (regnummer-render-form next values)
                       (regnummer-render-stats entries)
                       (regnummer-render-table entries)
                       "</main>")))
    (format regnummer-html body)))

(defun regnummer-send-page (process &optional error values)
  "Send the main page to PROCESS."
  (ws-response-header process 200
                      '("Content-type" . "text/html; charset=utf-8"))
  (process-send-string process (regnummer-render-page error values)))

(defun regnummer-handle-register (process headers)
  "Handle POST /register for PROCESS and HEADERS."
  (let* ((entries (regnummer-read-entries))
         (expected (regnummer-next-number entries))
         (number (string-to-number (regnummer-field headers "number")))
         (name (regnummer-trim (regnummer-field headers "name")))
         (location (regnummer-trim (regnummer-field headers "location")))
         (plate (regnummer-trim (regnummer-field headers "plate")))
         (values `(("name" . ,name)
                   ("location" . ,location)
                   ("plate" . ,plate))))
    (cond
     ((null expected)
      (regnummer-send-page process "Alla nummer är redan registrerade."))
     ((/= number expected)
      (regnummer-send-page process
                           (format "Fel nummer. Nästa nummer att registrera är %s."
                                   (regnummer-format-number expected))))
     ((string-empty-p name)
      (regnummer-send-page process "Namn måste anges." values))
     ((and (not (string-empty-p plate))
           (not (regnummer-valid-plate-p plate number)))
      (regnummer-send-page process
                           (format "Ogiltigt registreringsnummer. Ange formatet AAA %s."
                                   (regnummer-format-number number))
                           values))
     (t
      (regnummer-append-entry number name location plate)
      (ws-response-header process 303
                          (cons "Location"
                                (format "/?registered=%s"
                                        (regnummer-format-number number)))
                          '("Content-type" . "text/html; charset=utf-8"))
      (process-send-string process "")))))

(defun regnummer-handle-remove-last (process)
  "Handle POST /remove-last for PROCESS."
  (if (regnummer-remove-last-entry)
      (progn
        (ws-response-header process 303
                            '("Location" . "/")
                            '("Content-type" . "text/html; charset=utf-8"))
        (process-send-string process ""))
    (regnummer-send-page process "Inget att ta bort.")))

(defun regnummer-handler (request)
  "Handle one HTTP REQUEST."
  (with-slots (process headers) request
    (let ((path (regnummer-request-path headers)))
      (cond
       ((and (assoc :POST headers)
             (string-match "\\`register\\'" path))
        (regnummer-handle-register process headers))
       ((and (assoc :POST headers)
             (string-match "\\`remove-last\\'" path))
        (regnummer-handle-remove-last process))
       ((string-match "\\`static/regnummer\\.css\\'" path)
        (ws-send-file process (regnummer--file "regnummer.css")))
       ((string-match "\\`static/regnummer\\.js\\'" path)
        (ws-send-file process (regnummer--file "regnummer.js")))
       (t (regnummer-send-page process))))))

;;;###autoload
(defun regnummer-start (&optional port)
  "Start the Regnummer web server on PORT (default `regnummer-port')."
  (interactive)
  (when regnummer-server
    (user-error "Regnummer server already running on port %s"
                (ws-port regnummer-server)))
  (setq regnummer-server
        (ws-start #'regnummer-handler (or port regnummer-port)))
  (message "Regnummer server started: http://localhost:%s/"
           (ws-port regnummer-server)))

;;;###autoload
(defun regnummer-stop ()
  "Stop the Regnummer web server if it is running."
  (interactive)
  (when regnummer-server
    (ws-stop regnummer-server)
    (setq regnummer-server nil)
    (message "Regnummer server stopped")))

(setq regnummer--root
      (file-name-directory
       (or load-file-name (find-library-name "regnummer"))))

(provide 'regnummer)

;;; regnummer.el ends here
