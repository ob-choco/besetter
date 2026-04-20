import { describe, expect, test } from "vitest";
import { primaryLocale, renderTemplate } from "@/lib/notification-templates";

describe("primaryLocale", () => {
  test.each([
    [null, "ko"],
    [undefined, "ko"],
    ["", "ko"],
    ["ko-KR", "ko"],
    ["en-US", "en"],
    ["ja_JP", "ja"],
    ["de-DE", "ko"],
    ["es", "es"],
  ])("%s → %s", (input, expected) => {
    expect(primaryLocale(input as string | null)).toBe(expected);
  });
});

describe("renderTemplate", () => {
  test("place_review_passed ko", () => {
    const { title, body } = renderTemplate("place_review_passed", "ko", { place_name: "X짐" });
    expect(title).toBe("암장이 등록되었어요");
    expect(body).toContain("X짐");
  });
  test("place_review_failed with reason_suffix", () => {
    const { body } = renderTemplate("place_review_failed", "ko", {
      place_name: "X짐",
      reason_suffix: " 사유: 중복 등록",
    });
    expect(body).toContain("사유: 중복 등록");
  });
  test("place_review_failed without reason_suffix", () => {
    const { body } = renderTemplate("place_review_failed", "ko", {
      place_name: "X짐",
      reason_suffix: "",
    });
    expect(body).not.toContain("사유");
  });
  test("place_merged contains both names", () => {
    const { body } = renderTemplate("place_merged", "ko", {
      place_name: "A",
      target_name: "B",
    });
    expect(body).toContain("A");
    expect(body).toContain("B");
  });
});
