import { describe, expect, test } from "vitest";
import { normalizeName } from "@/lib/normalize";

describe("normalizeName", () => {
  test("strips spaces and symbols, lowercases latin", () => {
    expect(normalizeName("The Climbing Park!")).toBe("theclimbingpark");
  });
  test("preserves Korean characters", () => {
    expect(normalizeName("강남 클라이밍 파크")).toBe("강남클라이밍파크");
  });
  test("preserves Japanese characters", () => {
    expect(normalizeName("クライミング ジム")).toBe("クライミングジム");
  });
  test("strips underscores", () => {
    expect(normalizeName("Gym_One_Two")).toBe("gymonetwo");
  });
  test("preserves digits", () => {
    expect(normalizeName("Gym 42")).toBe("gym42");
  });
});
