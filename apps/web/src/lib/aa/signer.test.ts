import { describe, it, expect } from "vitest";
import { buildKernelCallData } from "@/lib/aa/signer";
import {
  OPEN_POSITION_SELECTOR,
  CLOSE_POSITION_SELECTOR,
} from "@/lib/aa/session-key";

describe("buildKernelCallData", () => {
  it("returns a 0x-prefixed hex string", () => {
    const result = buildKernelCallData(
      "0xe35486669A5D905CF18D4af477Aaac08dF93Eab0",
      "0x5a6c3d4a",
    );
    expect(result).toMatch(/^0x/);
  });

  it("encodes the execute(bytes32,bytes) selector 0xe9ae5c53", () => {
    const result = buildKernelCallData(
      "0xe35486669A5D905CF18D4af477Aaac08dF93Eab0",
      "0x5a6c3d4a",
    );
    expect(result.startsWith("0xe9ae5c53")).toBe(true);
  });

  it("encodes the target address in the execution calldata", () => {
    const target = "0xe35486669a5d905cf18d4af477aaac08df93eab0";
    const result = buildKernelCallData(
      target as `0x${string}`,
      "0xabcdef" as `0x${string}`,
    );
    expect(result.toLowerCase()).toContain(target.slice(2).toLowerCase());
  });
});

describe("selectors", () => {
  it("OPEN_POSITION_SELECTOR is 4 bytes hex", () => {
    expect(OPEN_POSITION_SELECTOR).toMatch(/^0x[0-9a-f]{8}$/i);
  });

  it("CLOSE_POSITION_SELECTOR is 4 bytes hex", () => {
    expect(CLOSE_POSITION_SELECTOR).toMatch(/^0x[0-9a-f]{8}$/i);
  });

  it("selectors are different", () => {
    expect(OPEN_POSITION_SELECTOR).not.toBe(CLOSE_POSITION_SELECTOR);
  });
});
