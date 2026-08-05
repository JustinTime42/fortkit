import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import { worldPage } from "../src/server.js";
import { readWorld } from "../src/world.js";

const fixtureRoot = fileURLToPath(new URL("./fixtures", import.meta.url));
const registryPath = join(fixtureRoot, "world-civilization.json");

describe("world view", () => {
  test("projects available, absent, and malformed fort sources without inventing health", async () => {
    const forts = await readWorld(registryPath);
    expect(forts).toHaveLength(3);
    expect(forts[0]).toMatchObject({
      name: "Alpha",
      beads: { ready: 1, malformed: 1 },
      inProgress: [
        {
          id: "b",
          title: "Build a bridge",
          seat: "forge",
          model: "gpt-5.6-terra",
        },
      ],
      announcements: [
        "Watch the gate",
        "Build a bridge",
        "UTC next day",
        "Earlier instant",
      ],
      watcherAlerts: ["Watch the gate"],
    });
    expect(forts[0]?.gaps).toContain("1 malformed Beads record(s)");
    expect(forts[1]).toMatchObject({
      name: "No Beads",
      beads: null,
      inProgress: [],
      gaps: ["Beads export ABSENT", "event stream ABSENT"],
    });
    expect(forts[2]).toMatchObject({
      name: "Missing",
      present: false,
      gaps: ["fort directory is absent"],
    });
  });

  test("has a self-contained polling page", () => {
    expect(worldPage).toContain("fetch('/world')");
    expect(worldPage).toContain("setInterval(load,5000)");
  });
});
