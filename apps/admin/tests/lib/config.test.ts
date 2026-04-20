import { beforeEach, describe, expect, test, vi } from "vitest";

vi.unmock("@/lib/config");

const accessSecretVersion = vi.fn();

vi.mock("@google-cloud/secret-manager", () => ({
  SecretManagerServiceClient: vi.fn().mockImplementation(() => ({
    accessSecretVersion,
  })),
}));

beforeEach(() => {
  vi.resetModules();
  accessSecretVersion.mockReset();
});

describe("config", () => {
  test("fetches secret once and caches across get() calls", async () => {
    accessSecretVersion.mockResolvedValue([
      { payload: { data: Buffer.from("mongodb:\n  url: mongodb://example\n  name: besetter\n") } },
    ]);

    const { get } = await import("@/lib/config");
    expect(await get("mongodb.url")).toBe("mongodb://example");
    expect(await get("mongodb.name")).toBe("besetter");
    expect(accessSecretVersion).toHaveBeenCalledTimes(1);
    expect(accessSecretVersion).toHaveBeenCalledWith({
      name: "projects/371038003203/secrets/api-secret/versions/latest",
    });
  });

  test("supports dot-notation nested lookup", async () => {
    accessSecretVersion.mockResolvedValue([
      {
        payload: {
          data: Buffer.from("a:\n  b:\n    c: value\n"),
        },
      },
    ]);
    const { get } = await import("@/lib/config");
    expect(await get("a.b.c")).toBe("value");
  });

  test("throws when key is missing", async () => {
    accessSecretVersion.mockResolvedValue([
      { payload: { data: Buffer.from("mongodb:\n  url: mongodb://example\n") } },
    ]);
    const { get } = await import("@/lib/config");
    await expect(get("mongodb.name")).rejects.toThrow(/mongodb\.name/);
  });
});
