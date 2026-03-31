import { Graphics, Container, Particle, ParticleContainer, Texture } from "pixi.js";
import type { Application } from "pixi.js";
import { GlowFilter } from "pixi-filters";

const LERP_FACTOR = 0.04;
const BANK_MAX_DEG = 8;
const BANK_RETURN_FRAMES = 30;
const BOB_AMPLITUDE = 3;
const BOB_HZ = 0.8;
const TRAIL_PARTICLES_PER_FRAME = 5;
const SHIP_X_RATIO = 0.5;

export type Spaceship = {
  container: Container;
  hull: Graphics;
  trailContainer: ParticleContainer;
  trailParticles: Particle[];
  targetY: number;
  bankAngle: number;
  bankFrames: number;
  tick: number;
};

export function createSpaceship(app: Application): Spaceship {
  const { width, height } = app.screen;

  const container = new Container();
  container.x = width * SHIP_X_RATIO;
  container.y = height / 2;

  const hull = new Graphics();
  drawHull(hull);
  hull.filters = [new GlowFilter({ distance: 20, outerStrength: 2, color: 0x00ffff })];
  container.addChild(hull);

  const trailContainer = new ParticleContainer({
    dynamicProperties: { position: true, color: true },
  });
  app.stage.addChild(trailContainer);
  app.stage.addChild(container);

  return {
    container,
    hull,
    trailContainer,
    trailParticles: [],
    targetY: height / 2,
    bankAngle: 0,
    bankFrames: 0,
    tick: 0,
  };
}

function drawHull(g: Graphics): void {
  g.clear();
  g.poly([0, -14, 28, 0, 0, 14, 8, 0]);
  g.fill({ color: 0x00ffff });
}

export function updateSpaceship(ship: Spaceship, delta: number): void {
  ship.tick += delta;

  const bob = Math.sin((ship.tick * BOB_HZ * Math.PI * 2) / 60) * BOB_AMPLITUDE;
  ship.container.y += (ship.targetY + bob - ship.container.y) * LERP_FACTOR;

  if (ship.bankFrames > 0) {
    ship.bankFrames -= delta;
    if (ship.bankFrames <= 0) {
      ship.bankAngle = 0;
      ship.bankFrames = 0;
    }
  }
  ship.container.rotation = (ship.bankAngle * Math.PI) / 180;

  emitTrail(ship);
  updateTrailParticles(ship);
}

export function bankSpaceship(ship: Spaceship, direction: "up" | "down"): void {
  ship.bankAngle = direction === "up" ? -BANK_MAX_DEG : BANK_MAX_DEG;
  ship.bankFrames = BANK_RETURN_FRAMES;
}

export function setSpaceshipTargetY(ship: Spaceship, y: number): void {
  const prev = ship.targetY;
  ship.targetY = y;
  const diff = y - prev;
  if (Math.abs(diff) > 2) {
    bankSpaceship(ship, diff < 0 ? "up" : "down");
  }
}

function emitTrail(ship: Spaceship): void {
  for (let i = 0; i < TRAIL_PARTICLES_PER_FRAME; i++) {
    const p = new Particle({
      texture: Texture.WHITE,
      x: ship.container.x - 8 + (Math.random() - 0.5) * 4,
      y: ship.container.y + (Math.random() - 0.5) * 8,
      scaleX: 0.5 + Math.random() * 0.5,
      scaleY: 0.5 + Math.random() * 0.5,
      alpha: 0.8,
      tint: 0x00ffcc,
    });
    ship.trailContainer.addParticle(p);
    ship.trailParticles.push(p);
  }
}

function updateTrailParticles(ship: Spaceship): void {
  const toRemove: Particle[] = [];
  for (const p of ship.trailParticles) {
    p.x -= 2;
    p.alpha -= 0.04;
    if (p.alpha <= 0) toRemove.push(p);
  }
  for (const p of toRemove) {
    ship.trailContainer.removeParticle(p);
    const idx = ship.trailParticles.indexOf(p);
    if (idx !== -1) ship.trailParticles.splice(idx, 1);
  }
}
