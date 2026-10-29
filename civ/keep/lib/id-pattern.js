// Shared bead-id grammar for server readers and browser rendering.
export function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function idPattern(prefix) {
  return new RegExp(`^${escapeRegExp(prefix)}-[\\w.-]+$`);
}
