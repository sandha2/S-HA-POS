# S&HA Retail & Wholesale Cloud POS

## Phone-only setup
1. In your original POS, use More > Export Backup and save the JSON to Files. Do not delete the original app.
2. Create a Supabase project. If new, run `schema.sql` once in Supabase SQL Editor. If you already ran the prior cloud schema, run **only** `upgrade_existing_cloud.sql`. Never rerun `schema.sql` over existing data.
3. In your GitHub repository `sandha2/S-HA-POS`, upload `index.html`, `manifest.webmanifest`, `sw.js`, `icon.svg`, `icon-192.png`, `icon-512.png`, replacing the old files. Do NOT upload SQL files, JSON backups, secrets, or customer records to public GitHub.
4. After GitHub Pages publishes, open the website in Safari. Enter your Supabase Project URL and **publishable/anon** key, never the service_role key. Sign in with the owner account.
5. Set each product's **wholesale** and **retail** price. Retail invoices do not automatically award free items; wholesale invoices use eligible 12+1 promotions. Choose sale type before adding invoice lines.
6. Verify invoice totals, stock deductions, employee permissions, and PDF printing with TEST data before using it for real business.

## Important
- This is a development build and has not been tested against your live Supabase project.
- Existing local POS records are not automatically deleted or synchronized. Import a saved JSON backup only once after testing.
- This version keeps the existing cloud schema's employee permissions; do not use with live staff until row-level security and access controls are verified.
- The public GitHub Pages site exposes its source code. Never paste database passwords or secret/service_role keys into the app.
- A PDF invoice is NOT a database backup.
- Product `retail_price` defaults to $0 after migration; configure prices before issuing retail invoices.
- Existing wholesale invoices remain marked wholesale.


## Branding update
The logo now appears in the dashboard header and invoice preview/print view. Upload `brand-logo.png`, `icon-192.png`, `icon-512.png`, and the updated `index.html` to the GitHub repository root. iPhone Home Screen icons may require removing and re-adding the shortcut after backing up data; do NOT remove an existing app that contains unsynced local invoices. This package does not migrate or clear local records.
