export const light = {
  canvas: "#F4F5F1",
  surface: "#FFFFFF",
  surfaceRaised: "#FAFBF8",
  surfaceMuted: "#ECEEE9",
  ink: "#151918",
  inkSecondary: "#555D59",
  inkTertiary: "#7B827E",
  border: "#D8DCD7",
  borderStrong: "#B9BFBA",
  brand: "#0B756D",
  brandStrong: "#075B55",
  brandSoft: "#DDF2EE",
  success: "#17734B",
  successSoft: "#E1F1E8",
  warning: "#A85D00",
  warningSoft: "#FAEBD4",
  danger: "#B63B35",
  dangerSoft: "#F7E2E0",
  info: "#356B8A",
  infoSoft: "#E2EDF3",
} as const;

export const dark = {
  canvas: "#0C0F0E",
  surface: "#121615",
  surfaceRaised: "#171C1A",
  surfaceMuted: "#1D2321",
  ink: "#F1F4EF",
  inkSecondary: "#AAB3AE",
  inkTertiary: "#77817C",
  border: "#29312E",
  borderStrong: "#3A4541",
  brand: "#43D4C4",
  brandStrong: "#7AE4D8",
  success: "#53BE87",
  warning: "#E3A145",
  danger: "#E36A62",
} as const;

export const typography = {
  primary: "Geist Sans",
  evidence: "Geist Mono",
  fallback: "Inter, system-ui, sans-serif",
  monoFallback: "JetBrains Mono, ui-monospace, monospace",
  roles: {
    financialHero: { size: "40-48px", weight: 600 },
    pageTitle: { size: "28px", weight: 600 },
    sectionTitle: { size: "18px", weight: 600 },
    card: { size: "14px", weight: 600 },
    body: { size: "14px", weight: 400 },
    table: { size: "13px", weight: 400 },
    metadata: { size: "12px", weight: 400 },
    evidenceId: { size: "11-12px", weight: 400 },
  },
} as const;

export const spacing = [4, 8, 12, 16, 24, 32, 48, 64] as const;

export const radius = {
  field: 4,
  tag: 4,
  button: 6,
  card: 8,
  panel: 12,
} as const;

export const themes = { light, dark } as const;

export type ThemeName = keyof typeof themes;
