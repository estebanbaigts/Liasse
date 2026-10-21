# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

<!-- Native macOS app. The schema lists web/ios/android/adaptive; none fits a Mac-only SwiftUI app, so the real value is recorded. Follow macOS Human Interface Guidelines. -->

## Stack

SwiftUI natif (confirmed by the user): macOS app + WidgetKit extension, financial and tax engine in a local Swift package (`Cockpit/CockpitCore`) with unit tests. Exploratory mockups may be HTML for fast comparison; they are not the product.

## Users

- Primary: the user themself, a French freelancer in micro-entreprise with a non-regulated liberal activity (BNC, SSI), who wants to know at a glance where their money stands.
- Secondary (confirmed): French freelancers in general — the product must work for other activity categories (BIC services, vente, Cipav) and regimes through configuration, never by assuming one rate fits everyone.
- Situation: on their Mac, daily or weekly, between client work; invoicing a client, recording a payment, checking what they can spend, preparing an URSSAF declaration.

## Product Purpose

A private financial cockpit that answers five questions immediately: how much did I really earn, how much can I really use, how much must I set aside for URSSAF / taxes / other obligations, who owes me and what must I pay, and how can I improve my situation without unnecessary risk. Success: the user stops juggling invoices, spreadsheets and administrative sites.

## Positioning

Local-first and explainable. Every amount traces back to its source transactions; estimates are never presented as official debts; tax rules carry their value, base, scope, effective date, official source and verification date. No bank connection, no cloud, no AI service by default.

## Operating Context

- Workflows: client and quote management, quote → invoice conversion, invoice issuance with non-reusable numbering, PDF export, payment recording (partial included), payment reminders drafted for the user to send, expense entry with local receipts, bank CSV import, URSSAF declaration calendar (monthly or quarterly), VAT if applicable, CFE, income tax (versement libératoire or estimate).
- Glanceable surface: macOS desktop / Notification Center widget, with hideable amounts.
- Documents produced: invoices, quotes, credit notes (avoirs) as printable PDF.

## Capabilities and Constraints

- Distinguish strictly: invoiced vs collected revenue, receivables, committed vs paid expenses, estimated vs declared vs paid obligations, forecasts vs actuals.
- Micro regime: real expenses never reduce the legal base for contributions or tax; economic profitability is shown separately.
- All rates and thresholds live in an editable rule catalogue; nothing hard-coded in views. Uncertain rules are flagged "à vérifier".
- Money in integer cents with explicit rounding; no floating-point money.
- Sensitive actions (issue invoice, send message, delete data, change a tax rule, mark payment) require explicit confirmation.
- Fully automatic computation only for micro-entreprise; other legal forms are flagged as requiring a professional.
- Release path (confirmed 2026-10-21): phase 1 = personal testing on the user's Mac without an Apple Developer account (ad-hoc "Sign to Run Locally"); phase 2 = Apple Developer Program expected around 2026-11-04, then distribution to other freelancers. Until then the App Group shared container (needed for the widget to read app data) cannot be provisioned: the team ID and App Group identifier must stay in one build setting so enabling them later is a one-line change. Distribution channel (Mac App Store vs Developer ID + notarization) is undecided.

## Brand Commitments

- Name: **Liasse** (chosen 2026-10-21, replacing the working name "Cockpit", which is widely used). User-facing name only; bundle id `fr.cockpit.app` and repo/code names unchanged to keep existing data. Trademark/App Store availability not yet verified.
- App icon: "Enveloppes" premium direction chosen by the user — graphite background, ivory/sand/sage envelopes, brushed-gold € medal; no flashy colors on the icon.

- Voice: French, tutoiement, direct and factual ("Tu peux utiliser 4 200 €", "Deux factures sont en retard"). Confirmed by the user.
- Visual personality (updated by the user on 2026-10-21, replacing the earlier "sober Apple-premium" direction, which the user found too office-like): friendly, lively and animated, while staying a native macOS SwiftUI app with the same features. Rounded system type, warm vivid colors, colored icon bubbles, soft cards, animated numbers and small celebratory moments (e.g. an invoice fully paid). Motion must stay quick and respect Reduce Motion; color is never the only carrier of meaning; estimates stay clearly labelled.

## Evidence on Hand

- No real user data, customers, testimonials or brand assets exist. Mockups use clearly fictional sample data; never present it as real.
- Verified official sources (2026-10-21): entreprendre.service-public.gouv.fr fiches F36232, F23267, F23459, F21746, F23257.

## Product Principles

1. The money you can really use comes first, without hiding debts or reserves.
2. Every figure is explainable down to its sources.
3. An estimate is labelled as an estimate; uncertainty is said plainly.
4. Private by default: nothing leaves the Mac without an informed action.
5. Each screen has one clear job; no decoration that does not help a decision.

## Accessibility & Inclusion

Full keyboard navigation, VoiceOver labels on every amount and chart, respect for Reduce Motion and increased contrast, color never the only carrier of meaning (income / reserve / expense / alert).
