# Invoicer for iPhone

A native SwiftUI port of the terminal invoice generator
([invoicer](https://github.com/aldoruizparra/invoicer)), built for non-technical users.
Pick a saved client, pick saved line items, confirm, and share a PDF.

## Two tools

- **Invoices**: your own invoices (= `invoice.py new` / `repeat`): saved clients and items,
  Review, Confirm, a PDF to share.
- **Weekly**: the contractor sheet for the client's `.xlsx` template (= `invoice.py from-email`).
  Add each house as you go (day, client, address, amount; recent clients, their addresses
  and last prices are one tap away), or **Paste from email** to fill the week in one go.
  At the end of the week, **Create spreadsheet** fills the template (+ optional PDF).

## Layout

```
InvoicerKit/      Swift package, Apple frameworks only (runs `swift test` on the Mac)
  Money            Decimal money, half-up tax rounding, $1,234.56 formatting   (money.py)
  Records          Sender, ContactInfo, LineItem, InvoiceData, validators      (store.py, flow.py)
  EmailLog         work-log email parser                                         (email_log.py)
  EmlReader        .eml MIME reader: multipart, quoted-printable, base64, HTML
  InvoicePDF       CoreGraphics/CoreText port of the CLI PDF, Helvetica Neue    (pdf.py, demo.py)
  Zip/XMLTree/XLSX no-dependency .xlsx read + in-place template fill
  WeeklyInvoice    fill the client's template + one-page PDF                     (weekly.py)
  CLIImport        reads the CLI's ~/.invoicer/data.json
Invoicer/         the app: SwiftData models, Store (numbering/MRU rules), screens, Industry styling
InvoicerTests/    app-level tests (numbering, cancel, duplicates, MRU, import, weekly sheet)
```

## Build & test

Open `Invoicer.xcodeproj` in Xcode 16.4+ and run the **Invoicer** scheme (iOS 18+).

```bash
cd InvoicerKit && swift test                      # 28 tests: money, parser, PDF, xlsx, import
xcodebuild -scheme Invoicer -destination 'platform=iOS Simulator,name=iPhone 16' test   # 15 app tests
```

`INVOICER_SNAPSHOT_DIR=/some/dir swift test` also writes the demo invoice PDF and the
filled weekly .xlsx/.pdf for a visual check.

Debug launch arguments (in-memory fake data, never touches real data):
`-demoData YES`, `-demoSetup YES`, `-openScreen newInvoice|review|contacts|item|saved|settings|weekly|addHouse|editHouse|paste|preview|demo`.

## Install on someone's iPhone with a free Apple ID

No paid developer account needed. The **Invoicer (Free Apple ID)** scheme builds without
iCloud and push notifications (free accounts can't sign those); everything is saved on the
phone, and PDFs/spreadsheets appear in Files › On My iPhone › Invoicer.

1. Plug the iPhone into the Mac, tap **Trust** on the phone.
2. Xcode › Settings › Accounts › **+** › Apple ID (yours; the phone keeps its own Apple ID).
3. Pick the **Invoicer (Free Apple ID)** scheme, select the project › Invoicer target ›
   Signing & Capabilities › Team: *your name (Personal Team)*. If the bundle ID is taken,
   change it to something unique, e.g. `com.yourname.Invoicer`.
4. Choose the iPhone as the destination and press ⌘R.
5. On the phone: Settings › Privacy & Security › **Developer Mode** on (restart), then
   Settings › General › VPN & Device Management › trust your developer certificate.

Free-account installs expire after 7 days: reconnect and press ⌘R again (data is kept).
Window › Devices and Simulators › *Connect via network* lets you do this over Wi-Fi.

## Before shipping to a device

- Set your **Development Team** in Signing & Capabilities. The iCloud container is
  `iCloud.com.aldoruizparra.Invoicer` (change the bundle ID/container together if needed).
- iCloud sync (CloudKit private database) and the iCloud Drive › Invoicer folder only work
  on a signed build with an iCloud account; otherwise the app keeps everything on the device.
- Building with Xcode 26 picks up iOS 26 Liquid Glass on the standard bars automatically.

## Rules carried over from the CLI

- Cancelling never uses up an invoice number; only **Confirm & create PDF** does.
- A number that already exists is rejected.
- Saved contacts, addresses and items are most-recently-used first; new contacts and
  addresses are saved as soon as they're added; saving a line remembers its price.
- Tax is rounded to cents half-up; all money is `Decimal` (stored as cents).

Fonts: Barlow and Barlow Condensed (SIL Open Font License, `Invoicer/Resources/Fonts/OFL.txt`).
