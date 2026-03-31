"use client";

import {
  useRef,
  useEffect,
  useImperativeHandle,
  forwardRef,
} from "react";
import type { Application, TickerCallback } from "pixi.js";
import type { StarLayer } from "@/lib/game/starfield";
import type { Spaceship } from "@/lib/game/spaceship";
import type { PriceTrail } from "@/lib/game/price-trail";

export type GameCanvasHandle = {
  triggerWarp: () => void;
  triggerWin: () => void;
  triggerLoss: () => void;
};

type Props = {
  priceRef: React.RefObject<bigint>;
};

const VOLATILITY_THRESHOLD = 0.02;
const VOLATILITY_WINDOW_MS = 1000;
const PRICE_WINDOW_SIZE = 60;
const SHIP_Y_EDGE_RATIO = 0.05;

const GameCanvasInner = forwardRef<GameCanvasHandle, Props>(
  function GameCanvasInner({ priceRef }, ref) {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const appRef = useRef<Application | null>(null);
    const warpFlashRef = useRef<((app: Application) => void) | null>(null);
    const stateRef = useRef<{
      starLayers: StarLayer[];
      ship: Spaceship;
      trail: PriceTrail;
      warping: boolean;
      lastPrice: bigint;
      lastPriceTime: number;
      priceWindow: number[];
    } | null>(null);

    useImperativeHandle(ref, () => ({
      triggerWarp() {
        const app = appRef.current;
        if (app !== null && app !== undefined) {
          warpFlashRef.current?.(app);
        }
        if (stateRef.current !== null) {
          stateRef.current.warping = true;
          setTimeout(() => {
            if (stateRef.current !== null) stateRef.current.warping = false;
          }, 800);
        }
      },
      triggerWin() {
        const app = appRef.current;
        const ship = stateRef.current?.ship;
        if (app === null || app === undefined || ship === undefined) return;
        void import("@/lib/game/trade-effects").then(({ winExplosion }) => {
          winExplosion(app, { x: ship.container.x, y: ship.container.y });
        });
      },
      triggerLoss() {
        const app = appRef.current;
        const ship = stateRef.current?.ship;
        if (app === null || app === undefined || ship === undefined) return;
        void import("@/lib/game/trade-effects").then(({ lossDamage }) => {
          lossDamage(app, { x: ship.container.x, y: ship.container.y });
        });
      },
    }));

    useEffect(() => {
      if (canvasRef.current === null) return;
      const canvas = canvasRef.current;
      let app: Application;
      let gameTickerCb: TickerCallback<unknown> | undefined;
      let ro: ResizeObserver | undefined;
      let cancelled = false;

      const init = async () => {
        const { Application } = await import("pixi.js");
        if (cancelled) return;
        const { createStarfield, updateStarfield } = await import("@/lib/game/starfield");
        const { createSpaceship, updateSpaceship, setSpaceshipTargetY } = await import("@/lib/game/spaceship");
        const { createPriceTrail, pushPrice, drawPriceTrail } = await import("@/lib/game/price-trail");
        const { warpFlash } = await import("@/lib/game/trade-effects");
        if (cancelled) return;

        app = new Application();
        await app.init({
          canvas,
          backgroundAlpha: 0,
          resolution: window.devicePixelRatio,
          autoDensity: true,
          width: canvas.offsetWidth,
          height: canvas.offsetHeight,
        });

        if (cancelled) { app.destroy(true, { children: true }); return; }

        appRef.current = app;
        warpFlashRef.current = warpFlash;

        const starLayers = createStarfield(app);
        const ship = createSpaceship(app);
        const trail = createPriceTrail(app.stage);

        stateRef.current = {
          starLayers,
          ship,
          trail,
          warping: false,
          lastPrice: 0n,
          lastPriceTime: Date.now(),
          priceWindow: [],
        };

        ro = new ResizeObserver(([entry]) => {
          if (entry === undefined) return;
          const { width, height } = entry.contentRect;
          app.renderer.resize(width, height);
          const state = stateRef.current;
          if (state !== null) state.ship.container.x = width / 2;
        });
        ro.observe(canvas);

        gameTickerCb = (ticker) => {
          const state = stateRef.current;
          if (state === null) return;

          const price = priceRef.current;
          if (price !== 0n) {
            const now = Date.now();
            if (state.lastPrice !== 0n) {
              const priceDelta =
                Math.abs(Number(price - state.lastPrice)) / Number(state.lastPrice);
              const timeDelta = now - state.lastPriceTime;
              if (timeDelta > 0 && priceDelta / (timeDelta / VOLATILITY_WINDOW_MS) > VOLATILITY_THRESHOLD) {
                if (!state.warping) {
                  state.warping = true;
                  warpFlash(app);
                  setTimeout(() => {
                    if (stateRef.current !== null) stateRef.current.warping = false;
                  }, 600);
                }
              }
            }
            if (price !== state.lastPrice) {
              state.lastPrice = price;
              state.lastPriceTime = now;
              pushPrice(trail, price);

              const priceNum = Number(price);
              state.priceWindow.push(priceNum);
              if (state.priceWindow.length > PRICE_WINDOW_SIZE) {
                state.priceWindow.shift();
              }

              const h = app.screen.height;
              let targetY = h * 0.5;
              if (state.priceWindow.length >= 2) {
                let windowMin = state.priceWindow[0] ?? priceNum;
                let windowMax = windowMin;
                for (const p of state.priceWindow) {
                  if (p < windowMin) windowMin = p;
                  if (p > windowMax) windowMax = p;
                }
                if (windowMax > windowMin) {
                  const norm = 1 - (priceNum - windowMin) / (windowMax - windowMin);
                  targetY = Math.max(
                    h * SHIP_Y_EDGE_RATIO,
                    Math.min(h * (1 - SHIP_Y_EDGE_RATIO), norm * h),
                  );
                }
              }
              setSpaceshipTargetY(ship, targetY);
            }
          }

          const { width, height } = app.screen;
          updateStarfield(state.starLayers, ticker.deltaTime, state.warping, width);
          updateSpaceship(state.ship, ticker.deltaTime);
          drawPriceTrail(state.trail, width / 2, height);
        };
        app.ticker.add(gameTickerCb);
      };

      void init();

      return () => {
        cancelled = true;
        ro?.disconnect();
        if (gameTickerCb !== undefined) app?.ticker.remove(gameTickerCb);
        app?.destroy(true, { children: true });
        appRef.current = null;
        warpFlashRef.current = null;
        stateRef.current = null;
      };
    }, [priceRef]);

    return (
      <canvas
        ref={canvasRef}
        className="h-full w-full"
        style={{ display: "block" }}
      />
    );
  },
);

export const GameCanvas = GameCanvasInner;
