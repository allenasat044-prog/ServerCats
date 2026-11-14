export const fmt = (x: number) => x >= 2 ** 30 ? (x / 2 ** 30).toFixed(1) + " GB" : x >= 2 ** 20 ? (x / 2 ** 20).toFixed(1) + " MB" : x >= 1024 ? Math.round(x / 1024) + " KB" : x + " B";
export const GITHUB = "https://github.com/allenasat044-prog/labserver";

export type Member = { name: string; role: string; handle: string; url: string };
export const TEAM: Member[] = [
  { name: "Shashank Patel", role: "Linux System Administrator", handle: "allenasat044-prog", url: "https://github.com/allenasat044-prog" },
  { name: "Pankaj Pandurang Tike", role: "Storage & Backup Administrator", handle: "pankajt25", url: "https://github.com/pankajt25" },
  { name: "Anmol Poddar", role: "Automation and Security Engineer", handle: "ANMOL16-IT", url: "https://github.com/ANMOL16-IT" },
  { name: "Shikhar Srivastava", role: "Testing, Documentation & Presentation Lead", handle: "FFloverSHIKHAR2006", url: "https://github.com/FFloverSHIKHAR2006" },
];

// ---- formatting helpers (all values on the site come from public/data.json, written by server/collect.py)
export const dt = (iso?: string | null) => (iso ? new Date(iso).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) : "never");
export const na = (v: unknown) => (v === null || v === undefined || v === "" ? "unavailable" : String(v));
