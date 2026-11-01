# S&HA Wholesale POS — iPhone-first PWA MVP

A static, offline-capable wholesale POS prototype. No server or API keys needed. **Data lives only in this browser/device** and may be erased by browser storage cleanup. It is not appropriate as the only record of a business. Export backups frequently.

## Features
- Customers: name, store, phone, address, opening balance, notes
- Products: sale price, cost, inventory, SKU, 12+1 promotion eligibility
- Invoice creation with paid and free quantities, discounts, immediate payments, stock deduction
- Invoice history and printable invoices; iPhone Print > Share > Save to Files creates a PDF
- Customer outstanding balances and subsequent payment entries
- JSON backup export/import
- Offline app shell after initial successful load on HTTPS

## Publish without a computer (GitHub Pages)
1. On iPhone Safari, create a GitHub account and a new **public** repository, e.g. `sha-pos-demo`. **Do not put customer or business data in the repository.**
2. Unzip the project using the iPhone Files app. On GitHub in Safari, open the repository and use **Add file > Upload files** (request desktop website if necessary) to upload `index.html`, `manifest.webmanifest`, `sw.js`, and `icon.svg` into the repository root. Commit the files.
3. Repository **Settings > Pages > Build and deployment > Deploy from a branch**, choose `main` and `/ (root)`, then Save.
4. Once deployed, visit `https://YOUR-USERNAME.github.io/sha-pos-demo/` in Safari.
5. Safari Share > Add to Home Screen > Add. Open S&HA POS from the Home Screen.

GitHub Pages is public hosting. The application source is public; customer data entered in the app stays in the iPhone's local browser storage, not GitHub. Anyone can access the empty app at the URL, and there is no account login. Do not use for sensitive or production data without authentication, server storage, secure backups, and testing.

## Important limitations
- This is a working **single-device MVP**, not cloud sync or a payment processor.
- Inventory is manually entered; no barcode scanning yet.
- Invoice numbers are sequential per local database; multiple devices could conflict.
- Customer-specific pricing and returns are not implemented yet.
- PDF is generated via browser print-to-PDF, not as a stored PDF file.
- Customer balances are opening balance + all invoices - all recorded payments; payments are not assigned to individual invoices.
- Stock cannot be negative during invoice creation; update stock in Products for restocking.
- Do not clear browser/site data without exporting a backup.
