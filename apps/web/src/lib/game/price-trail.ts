import { Graphics } from "pixi.js";
import { GlowFilter } from "pixi-filters";

const BUFFER_SIZE = 200;
const TRAIL_COLOR = 0x00ffff;
const GLOW_OUTER_STRENGTH = 3;
const ALPHA_NEWEST = 0.9;
const ALPHA_OLDEST = 0.1;
const HEADER_HEIGHT = 44;
const FOOTER_HEIGHT = 56;
const SPLINE_TENSION = 0.3;
const EMA_ALPHA = 0.15;

export type PriceTrail = {
  buffer: Float64Array;
  head: number;
  count: number;
  graphics: Graphics;
  lastY: number;
  ema: number;
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
    lastY: 0,
    ema: 0,
  };
}

export function pushPrice(trail: PriceTrail, price: bigint): void {
  const raw = Number(price);
  const smoothed = trail.ema === 0 ? raw : trail.ema + EMA_ALPHA * (raw - trail.ema);
  trail.ema = smoothed;

  trail.buffer[trail.head] = smoothed;
  trail.head = (trail.head + 1) % BUFFER_SIZE;
  if (trail.count < BUFFER_SIZE) trail.count++;
}

function clamp(value: number, lo: number, hi: number): number {
  return value < lo ? lo : value > hi ? hi : value;
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
    const val = trail.buffer[idx] ?? 0;
    if (val < min) min = val;
    if (val > max) max = val;
  }

  const range = max - min || 1;
  const padTop = HEADER_HEIGHT + 16;
  const padBottom = FOOTER_HEIGHT + 16;
  const drawH = height - padTop - padBottom;
  const yMin = padTop;
  const yMax = padTop + drawH;

  const xs: number[] = [];
  const ys: number[] = [];

  for (let i = 0; i < trail.count; i++) {
    const idx = (trail.head - trail.count + i + BUFFER_SIZE) % BUFFER_SIZE;
    const val = trail.buffer[idx] ?? min;
    xs.push((i / (trail.count - 1)) * width);
    ys.push(clamp(padTop + drawH - ((val - min) / range) * drawH, yMin, yMax));
  }

  trail.graphics.clear();

  trail.graphics.moveTo(xs[0] ?? 0, ys[0] ?? 0);

  for (let i = 0; i < trail.count - 1; i++) {
    const x0 = xs[i] ?? 0;
    const y0 = ys[i] ?? 0;
    const x1 = xs[i + 1] ?? x0;
    const y1 = ys[i + 1] ?? y0;

    const xPrev = i > 0 ? (xs[i - 1] ?? x0) : x0;
    const yPrev = i > 0 ? (ys[i - 1] ?? y0) : y0;
    const xNext = i + 2 < trail.count ? (xs[i + 2] ?? x1) : x1;
    const yNext = i + 2 < trail.count ? (ys[i + 2] ?? y1) : y1;

    const cp1x = x0 + (x1 - xPrev) * SPLINE_TENSION;
    const cp1y = clamp(y0 + (y1 - yPrev) * SPLINE_TENSION, yMin, yMax);
    const cp2x = x1 - (xNext - x0) * SPLINE_TENSION;
    const cp2y = clamp(y1 - (yNext - y0) * SPLINE_TENSION, yMin, yMax);

    const alpha = ALPHA_OLDEST + (ALPHA_NEWEST - ALPHA_OLDEST) * ((i + 1) / trail.count);

    trail.graphics
      .moveTo(x0, y0)
      .bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x1, y1)
      .stroke({ color: TRAIL_COLOR, alpha, width: 2 });
  }

  trail.lastY = ys[trail.count - 1] ?? height / 2;
}
