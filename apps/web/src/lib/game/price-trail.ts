import { Graphics } from "pixi.js";
import { GlowFilter } from "pixi-filters";

const BUFFER_SIZE = 200;
const TRAIL_COLOR = 0x00ffff;
const GLOW_OUTER_STRENGTH = 3;
const ALPHA_NEWEST = 0.9;
const ALPHA_OLDEST = 0.1;

export type PriceTrail = {
  buffer: Float64Array;
  head: number;
  count: number;
  graphics: Graphics;
};

export function createPriceTrail(stage: { addChild: (g: Graphics) => void }): PriceTrail {
  const graphics = new Graphics();
  graphics.filters = [new GlowFilter({ outerStrength: GLOW_OUTER_STRENGTH, color: TRAIL_COLOR })];
  stage.addChild(graphics);

  return {
    buffer: new Float64Array(BUFFER_SIZE),
    head: 0,
    count: 0,
    graphics,
  };
}

export function pushPrice(trail: PriceTrail, price: bigint): void {
  trail.buffer[trail.head] = Number(price);
  trail.head = (trail.head + 1) % BUFFER_SIZE;
  if (trail.count < BUFFER_SIZE) trail.count++;
}

export function drawPriceTrail(
  trail: PriceTrail,
  width: number,
  height: number,
): void {
  if (trail.count < 2) return;

  let min = Number.POSITIVE_INFINITY;
  let max = Number.NEGATIVE_INFINITY;

  for (let i = 0; i < trail.count; i++) {
    const idx = (trail.head - trail.count + i + BUFFER_SIZE) % BUFFER_SIZE;
    const val = trail.buffer[idx];
    if (val !== undefined && val < min) min = val;
    if (val !== undefined && val > max) max = val;
  }

  const range = max - min || 1;
  const pad = height * 0.1;
  const drawH = height - pad * 2;

  trail.graphics.clear();

  for (let i = 0; i < trail.count - 1; i++) {
    const idxA = (trail.head - trail.count + i + BUFFER_SIZE) % BUFFER_SIZE;
    const idxB = (idxA + 1) % BUFFER_SIZE;
    const valA = trail.buffer[idxA] ?? min;
    const valB = trail.buffer[idxB] ?? min;

    const xA = (i / (trail.count - 1)) * width;
    const xB = ((i + 1) / (trail.count - 1)) * width;
    const yA = pad + drawH - ((valA - min) / range) * drawH;
    const yB = pad + drawH - ((valB - min) / range) * drawH;

    const alpha = ALPHA_OLDEST + (ALPHA_NEWEST - ALPHA_OLDEST) * ((i + 1) / trail.count);

    trail.graphics
      .moveTo(xA, yA)
      .lineTo(xB, yB)
      .stroke({ color: TRAIL_COLOR, alpha, width: 2 });
  }
}
