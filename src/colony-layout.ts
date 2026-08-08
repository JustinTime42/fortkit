/**
 * The living fort's stable geometry. Both ambient life and the colony canvas
 * consume this module so an ambient destination cannot name an unmapped place.
 */
export type BuildingLayout = {
  x: number;
  y: number;
  name: string;
  color: string;
};

export const buildingWidth = 210;
export const buildingHeight = 112;
const buildingStartX = 30;
const buildingStride = 245;

export const buildingLayouts = {
  mayor: { x: buildingStartX, y: 35, name: "MAYOR'S OFFICE", color: "#6b4e2d" },
  forge: {
    x: buildingStartX + buildingStride,
    y: 35,
    name: "THE FORGE",
    color: "#48643d",
  },
  warden: {
    x: buildingStartX + buildingStride * 2,
    y: 35,
    name: "WARDEN'S TOWER",
    color: "#3b5a63",
  },
  gate: {
    x: buildingStartX + buildingStride * 3,
    y: 35,
    name: "THE GATE",
    color: "#6b4e2d",
  },
  jobBoard: {
    x: buildingStartX,
    y: 205,
    name: "THE JOB BOARD",
    color: "#785a2d",
  },
  depot: {
    x: buildingStartX + buildingStride,
    y: 205,
    name: "TRADE DEPOT",
    color: "#785a2d",
  },
  dungeon: {
    x: buildingStartX + buildingStride * 2,
    y: 205,
    name: "THE DUNGEON",
    color: "#70404b",
  },
  archive: {
    x: buildingStartX + buildingStride * 3,
    y: 205,
    name: "THE ARCHIVE",
    color: "#3b5a63",
  },
  tavern: { x: buildingStartX, y: 375, name: "THE TAVERN", color: "#6c4c2a" },
  river: {
    x: buildingStartX + buildingStride,
    y: 375,
    name: "THE RIVER",
    color: "#315b74",
  },
  "tinker-bench": {
    x: buildingStartX + buildingStride * 2,
    y: 375,
    name: "TINKER BENCH",
    color: "#765a3d",
  },
  walls: {
    x: buildingStartX + buildingStride * 3,
    y: 375,
    name: "WALLS",
    color: "#5c554a",
  },
} as const satisfies Record<string, BuildingLayout>;

export type FixedAmbientPlace = keyof Pick<
  typeof buildingLayouts,
  "tavern" | "archive" | "walls" | "river" | "tinker-bench"
>;
export type AmbientPlace = `home:${string}` | FixedAmbientPlace;

export const homeStartY = 545;
const homeColumns = 4;

/** Home positions are stable roster slots, never a consequence of bead volume. */
export function homeLayout(index: number): BuildingLayout {
  return {
    x: buildingStartX + (index % homeColumns) * buildingStride,
    y: homeStartY + Math.floor(index / homeColumns) * 145,
    name: "HOME",
    color: "#594536",
  };
}
