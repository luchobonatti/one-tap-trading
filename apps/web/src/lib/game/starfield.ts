import { ParticleContainer, Particle, Texture } from "pixi.js";
import type { Application } from "pixi.js";

const LAYER_SPEEDS = [0.1, 0.3, 0.6] as const;
const STAR_COUNTS = [80, 50, 30] as const;
const STAR_ALPHAS = [0.3, 0.6, 1.0] as const;
const WARP_SCALE_X = 6;

export type StarLayer = {
  container: ParticleContainer;
  stars: Particle[];
  speed: number;
};

export function createStarfield(app: Application): StarLayer[] {
  const { width, height } = app.screen;

  return LAYER_SPEEDS.map((speed, i) => {
    const container = new ParticleContainer({
      dynamicProperties: { position: true, color: true, vertex: true },
    });
    app.stage.addChild(container);

    const stars: Particle[] = [];
    const count = STAR_COUNTS[i] ?? 50;
    const alpha = STAR_ALPHAS[i] ?? 0.5;

    for (let s = 0; s < count; s++) {
      const star = new Particle({
        texture: Texture.WHITE,
        x: Math.random() * width,
        y: Math.random() * height,
        scaleX: 1,
        scaleY: 1,
        alpha,
      });
      container.addParticle(star);
      stars.push(star);
    }

    return { container, stars, speed };
  });
}

export function updateStarfield(
  layers: StarLayer[],
  delta: number,
  warping: boolean,
  width: number,
): void {
  for (const layer of layers) {
    const targetScaleX = warping ? WARP_SCALE_X : 1;
    for (const star of layer.stars) {
      star.x -= layer.speed * delta;
      if (star.x < 0) star.x = ((star.x % width) + width) % width;
      star.scaleX += (targetScaleX - star.scaleX) * 0.15;
    }
  }
}
