import type { ObjectId } from "mongodb";

export type GeoJsonPoint = {
  type: "Point";
  /** [longitude, latitude] */
  coordinates: [number, number];
};

export type PlaceStatus = "pending" | "approved" | "rejected" | "merged";

export type PlaceDoc = {
  _id: ObjectId;
  name: string;
  normalizedName: string;
  type: "gym" | "private-gym";
  status: PlaceStatus;
  location?: GeoJsonPoint | null;
  coverImageUrl?: string | null;
  createdBy: ObjectId;
  createdAt: Date;
  mergedIntoPlaceId?: ObjectId | null;
  rejectedReason?: string | null;
};

export type PlaceSuggestionStatus = "pending" | "approved" | "rejected";

export type PlaceSuggestionChanges = {
  name?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  coverImageUrl?: string | null;
};

export type PlaceSuggestionDoc = {
  _id: ObjectId;
  placeId: ObjectId;
  requestedBy: ObjectId;
  status: PlaceSuggestionStatus;
  changes: PlaceSuggestionChanges;
  createdAt: Date;
  readAt?: Date | null;
  reviewedAt?: Date | null;
};

export type ImageDoc = {
  _id: ObjectId;
  url: string;
  filename: string;
  userId: ObjectId;
  placeId?: ObjectId | null;
  isDeleted?: boolean;
  uploadedAt: Date;
};

export type ActivityDoc = {
  _id: ObjectId;
  routeId: ObjectId;
  userId: ObjectId;
  routeSnapshot: {
    title?: string | null;
    gradeType: string;
    grade: string;
    gradeColor?: string | null;
    placeId?: ObjectId | null;
    placeName?: string | null;
    imageUrl?: string | null;
    overlayImageUrl?: string | null;
  };
};

export type UserDoc = {
  _id: ObjectId;
  profileId: string;
  name?: string | null;
  email?: string | null;
  profileImageUrl?: string | null;
  unreadNotificationCount: number;
};

export type NotificationType =
  | "place_registration_ack"
  | "place_suggestion_ack"
  | "place_review_passed"
  | "place_review_failed"
  | "place_merged"
  | "place_suggestion_approved"
  | "place_suggestion_rejected";

export type NotificationDoc = {
  _id?: ObjectId;
  userId: ObjectId;
  type: NotificationType;
  title: string;
  body: string;
  params: Record<string, string>;
  link?: string | null;
  createdAt: Date;
  readAt?: Date | null;
};

export type DeviceTokenDoc = {
  _id: ObjectId;
  userId: ObjectId;
  token: string;
  locale?: string | null;
};
