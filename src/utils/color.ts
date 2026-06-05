// ASS colour helpers.
//
// ASS stores colours as "&HAABBGGRR" — alpha first, then blue/green/red (reversed
// from the usual RGB). Alpha 00 = fully opaque, FF = fully transparent.
// The UI uses HTML "#RRGGBB" pickers, so we convert and preserve alpha separately.

/** "&H00FFCC00" -> "#00CCFF" (drops alpha). Falls back to white. */
export function assColorToHex(ass: string): string {
  const m = ass.match(/&H([0-9A-Fa-f]{2})?([0-9A-Fa-f]{6})/);
  if (!m) return "#FFFFFF";
  const bgr = m[2];
  const bb = bgr.slice(0, 2);
  const gg = bgr.slice(2, 4);
  const rr = bgr.slice(4, 6);
  return `#${rr}${gg}${bb}`.toUpperCase();
}

/** Extract the alpha byte ("00" when absent). */
export function assAlpha(ass: string): string {
  const m = ass.match(/&H([0-9A-Fa-f]{2})[0-9A-Fa-f]{6}/);
  return m ? m[1].toUpperCase() : "00";
}

/** "#00CCFF" + alpha -> "&HAABBGGRR". */
export function hexToAssColor(hex: string, alpha = "00"): string {
  const h = hex.replace("#", "");
  const rr = h.slice(0, 2);
  const gg = h.slice(2, 4);
  const bb = h.slice(4, 6);
  return `&H${alpha}${bb}${gg}${rr}`.toUpperCase();
}
