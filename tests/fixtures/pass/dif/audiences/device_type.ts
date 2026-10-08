// dif/audiences/device_type.ts — bucket users by viewport class.
//
// Returns null on the server (no `window`). Tweak the breakpoints to match
// your design system; the return type union must stay in sync with
// `audience_attributes.values` in dif/config.yaml.
export default function resolve(): "mobile" | "tablet" | "desktop" | null {
  if (typeof window === "undefined") return null;
  if (window.matchMedia("(max-width: 640px)").matches) return "mobile";
  if (window.matchMedia("(max-width: 1024px)").matches) return "tablet";
  return "desktop";
}
