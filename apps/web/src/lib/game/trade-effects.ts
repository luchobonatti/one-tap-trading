import { Graphics, Particle, ParticleContainer, Texture } from "pixi.js";
import type { Application, TickerCallback } from "pixi.js";

type Point = { x: number; y: number };

const FLASH_DURATION_MS = 300;
const CONFETTI_COUNT = 60;
const SPARK_COUNT = 40;

export function warpFlash(app: Application): void {
  const flash = new Graphics();
  flash.rect(0, 0, app.screen.width, app.screen.height);
  flash.fill({ color: 0xffffff, alpha: 0.35 });
  app.stage.addChild(flash);

  const start = Date.now();
  const onTick: TickerCallback<unknown> = () => {
    const elapsed = Date.now() - start;
    flash.alpha = Math.max(0, 1 - elapsed / FLASH_DURATION_MS);
    if (elapsed >= FLASH_DURATION_MS) {
      app.stage.removeChild(flash);
      app.ticker.remove(onTick);
    }
  };
  app.ticker.add(onTick);
}

type MovingParticle = Particle & { vx: number; vy: number };

export function winExplosion(app: Application, pos: Point): void {
  const COLORS = [0x00ff88, 0x00ffff, 0xffff00, 0xffffff] as const;
  const container = new ParticleContainer({
    dynamicProperties: { position: true, color: true },
  });
  app.stage.addChild(container);

  const particles: MovingParticle[] = [];
  for (let i = 0; i < CONFETTI_COUNT; i++) {
    const angle = (i / CONFETTI_COUNT) * Math.PI * 2;
    const speed = 2 + Math.random() * 4;
    const tint = COLORS[i % COLORS.length] ?? 0xffffff;
    const p = Object.assign(
      new Particle({ texture: Texture.WHITE, x: pos.x, y: pos.y, alpha: 1, tint }),
      { vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed },
    ) as MovingParticle;
    container.addParticle(p);
    particles.push(p);
  }

  const onTick: TickerCallback<unknown> = () => {
    let alive = false;
    for (const p of particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.1;
      p.alpha -= 0.02;
      if (p.alpha > 0) alive = true;
    }
    if (!alive) {
      app.stage.removeChild(container);
      app.ticker.remove(onTick);
    }
  };
  app.ticker.add(onTick);
}

export function lossDamage(app: Application, pos: Point): void {
  const container = new ParticleContainer({
    dynamicProperties: { position: true, color: true },
  });
  app.stage.addChild(container);

  const particles: MovingParticle[] = [];
  for (let i = 0; i < SPARK_COUNT; i++) {
    const angle = (i / SPARK_COUNT) * Math.PI * 2;
    const speed = 1 + Math.random() * 3;
    const p = Object.assign(
      new Particle({ texture: Texture.WHITE, x: pos.x, y: pos.y, alpha: 1, tint: 0xff2244 }),
      { vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed },
    ) as MovingParticle;
    container.addParticle(p);
    particles.push(p);
  }

  const onTick: TickerCallback<unknown> = () => {
    let alive = false;
    for (const p of particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.alpha -= 0.03;
      if (p.alpha > 0) alive = true;
    }
    if (!alive) {
      app.stage.removeChild(container);
      app.ticker.remove(onTick);
    }
  };
  app.ticker.add(onTick);
}
