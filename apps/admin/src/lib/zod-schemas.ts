import { z } from "zod";

export const ObjectIdString = z.string().regex(/^[a-f0-9]{24}$/i, "invalid object id");

export const MergeCandidatesQuery = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  q: z.string().min(1).max(100).optional(),
});

export const FailBody = z.object({
  reason: z.string().min(1).max(500).optional(),
});

export const RejectBody = z.object({
  reason: z.string().min(1).max(500).optional(),
});

export const MergeBody = z.object({
  targetPlaceId: ObjectIdString,
});
