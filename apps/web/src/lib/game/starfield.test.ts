import { describe, it, expect } from "vitest";
import { updateStarfield } from "@/lib/game/starfield";
import type { StarLayer } from "@/lib/game/starfield";
import type { Particle, ParticleContainer } from "pixi.js";

function makeStar(x: number): Particle {
  return { x, scaleX: 1 } as unknown as Particle;
}

function makeLayer(speed: number, stars: Particle[]): StarLayer {
  return { container: {} as unknown as ParticleContainer, stars, speed };
}

describe("updateStarfield", () => {
  it("moves each star left by speed × delta", () => {
    const stars = [makeStar(100), makeStar(110), makeStar(120)];
    const layer = makeLayer(0.3, stars);
    updateStarfield([layer], 1, false, 1000);
    const [a, b, c] = layer.stars;
    if (a === undefined || b === undefined || c === undefined) throw new Error("stars missing");
    expect(a.x).toBeCloseTo(99.7, 5);
    expect(b.x).toBeCloseTo(109.7, 5);
    expect(c.x).toBeCloseTo(119.7, 5);
  });

  it("wraps star x back to width when it goes off-screen left", () => {
    const star = makeStar(0.3);
    const layer = makeLayer(0.5, [star]);
    updateStarfield([layer], 1, false, 500);
    const [s] = layer.stars;
    if (s === undefined) throw new Error("star missing");
    expect(s.x).toBeGreaterThan(0);
  });

  it("increases scaleX toward WARP_SCALE_X when warping=true", () => {
    const star = makeStar(50);
    const layer = makeLayer(0.1, [star]);
    updateStarfield([layer], 1, true, 1000);
    const [s] = layer.stars;
    if (s === undefined) throw new Error("star missing");
    expect(s.scaleX).toBeGreaterThan(1);
  });

  it("decreases scaleX toward 1 when warping=false", () => {
    const star = makeStar(50);
    star.scaleX = 6;
    const layer = makeLayer(0.1, [star]);
    updateStarfield([layer], 1, false, 1000);
    const [s] = layer.stars;
    if (s === undefined) throw new Error("star missing");
    expect(s.scaleX).toBeLessThan(6);
  });

  it("processes slow and fast layers independently", () => {
    const slow = makeLayer(0.1, [makeStar(100)]);
    const fast = makeLayer(0.6, [makeStar(100)]);
    updateStarfield([slow, fast], 1, false, 1000);
    const [slowStar] = slow.stars;
    const [fastStar] = fast.stars;
    if (slowStar === undefined || fastStar === undefined) throw new Error("stars missing");
    expect(fastStar.x).toBeLessThan(slowStar.x);
  });
});
