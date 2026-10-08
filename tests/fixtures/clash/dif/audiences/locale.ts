// dif/audiences/locale.ts — resolve the browser's UI locale (e.g. "en-US").
//
// Returns null on the server (no `navigator`); audience predicates referencing
// `locale` therefore fail closed during SSR, which is the correct behavior.
//
// Edit this file freely — once scaffolded, dif treats it as yours. Update the
// matching `audience_attributes` entry in dif/config.yaml if you change the
// return type.
export default function resolve(): string | null {
  if (typeof navigator === "undefined") return null;
  return navigator.language ?? null;
}
