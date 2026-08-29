# Evidence Ledger design tokens

Status: Step 28 shared token baseline

The typed `@anarchi/design-tokens` package is the single source for the frozen
Evidence Ledger light and dark themes. The product palette is intentionally
quiet, legible, and evidence-first: the light canvas is `#F4F5F1`, the primary
brand is `#0B756D`, and status colors are explicit rather than color-only
semantics. Dark is a counterpart theme; Blacksite and restrained heritage
accents are not product defaults.

Typography uses Geist Sans for interface text and Geist Mono for evidence,
rules, and numbers, with Inter/system and JetBrains/ui-monospace fallbacks. The
spacing scale is a 4px base grid (`4 / 8 / 12 / 16 / 24 / 32 / 48 / 64`) and
radii are fixed at 4px fields/tags, 6px buttons, 8px cards, and 12px panels.

Screens, web/Tauri clients, and mobile clients must consume these tokens rather
than introduce local palette or spacing authority. Accessibility behavior and
component contracts are later transitions.
