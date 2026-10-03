import fs from "node:fs";
import path from "node:path";

export function eventFileNames(now = new Date()) {
  return [0, 1].map((daysAgo) => {
    const date = new Date(now.getTime() - daysAgo * 86_400_000);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `events-${year}-${month}-${day}.jsonl`;
  });
}

export function newestEvent(directory, category, fileSystem = fs) {
  if (!fileSystem.existsSync(directory)) return null;
  const names = fileSystem
    .readdirSync(directory)
    .filter((value) => /^events-.*\.jsonl$/.test(value))
    .sort()
    .reverse();
  for (const name of names) {
    let content;
    try {
      content = fileSystem.readFileSync(path.join(directory, name), "utf8");
    } catch {
      continue;
    }
    for (const raw of content.split("\n").reverse()) {
      const event = parseEventLine(raw);
      if (event.category !== category || !event.ts) continue;
      return event;
    }
  }
  return null;
}

export function parseEventLine(raw) {
  try {
    return { ...JSON.parse(raw), raw };
  } catch {
    return { raw, unparseable: true };
  }
}

export class EventTail {
  constructor({ directory, fileSystem = fs, now = () => new Date() }) {
    this.directory = directory;
    this.fs = fileSystem;
    this.now = now;
    this.events = [];
    this.offsets = new Map();
    this.listeners = new Set();
    this.watcher = null;
  }

  load() {
    this.scan();
    return this.events;
  }

  scan() {
    for (const name of eventFileNames(this.now()))
      this.readAppended(path.join(this.directory, name));
    return this.events;
  }

  watch() {
    if (!this.fs.existsSync(this.directory) || this.watcher) return;
    this.watcher = this.fs.watch(this.directory, () => {
      try {
        this.scan();
      } catch {
        // A file can disappear between existsSync and readFileSync; the next tick retries.
      }
    });
  }

  readAppended(file) {
    if (!this.fs.existsSync(file)) return;
    const content = this.fs.readFileSync(file, "utf8");
    const offset = this.offsets.get(file) ?? 0;
    if (content.length < offset) this.offsets.set(file, 0);
    const appended = content.slice(this.offsets.get(file) ?? 0);
    this.offsets.set(file, content.length);
    for (const raw of appended.split("\n")) {
      if (!raw) continue;
      const event = parseEventLine(raw);
      this.events.push(event);
      for (const listener of this.listeners) listener(event);
    }
  }

  onEvent(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  close() {
    this.watcher?.close();
    this.watcher = null;
  }
}
