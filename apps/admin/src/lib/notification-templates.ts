import type { NotificationType } from "@/lib/db-types";

export type Locale = "ko" | "en" | "ja" | "es";
export const DEFAULT_LOCALE: Locale = "ko";
export const SUPPORTED_LOCALES: Locale[] = ["ko", "en", "ja", "es"];

type TemplateEntry = Record<"title" | "body", Record<Locale, string>>;

/**
 * Mirrors services/api/app/services/notification_templates.py for the five
 * admin-driven types. When either file changes, update both.
 */
export const TEMPLATES: Record<Extract<
  NotificationType,
  "place_review_passed" | "place_review_failed" | "place_merged" | "place_suggestion_approved" | "place_suggestion_rejected"
>, TemplateEntry> = {
  place_review_passed: {
    title: {
      ko: "암장이 등록되었어요",
      en: "Your gym has been approved",
      ja: "クライミングジムが登録されました",
      es: "Tu gimnasio ha sido aprobado",
    },
    body: {
      ko: "{place_name} 등록이 승인되었어요. 지금 바로 확인해보세요!",
      en: "{place_name} has been approved. Check it out!",
      ja: "{place_name} の登録が承認されました。今すぐ確認してみてください！",
      es: "¡{place_name} ha sido aprobado. Échale un vistazo!",
    },
  },
  place_review_failed: {
    title: {
      ko: "암장 등록이 반려되었어요",
      en: "Your gym registration was rejected",
      ja: "クライミングジムの登録が却下されました",
      es: "Se rechazó el registro de tu gimnasio",
    },
    body: {
      ko: "{place_name} 등록이 반려되었어요.{reason_suffix}",
      en: "{place_name} was rejected.{reason_suffix}",
      ja: "{place_name} の登録は却下されました。{reason_suffix}",
      es: "El registro de {place_name} fue rechazado.{reason_suffix}",
    },
  },
  place_merged: {
    title: {
      ko: "등록한 암장이 병합되었어요",
      en: "Your gym was merged into an existing one",
      ja: "登録したジムが既存のスポットに統合されました",
      es: "Tu gimnasio fue fusionado con uno existente",
    },
    body: {
      ko: "{place_name} 은(는) 기존 {target_name}(으)로 병합되었어요. 올려주신 기록은 그대로 옮겨졌습니다.",
      en: "{place_name} was merged into {target_name}. Your uploads have been moved over.",
      ja: "{place_name} は {target_name} に統合されました。アップロードいただいた記録はそのまま移動されました。",
      es: "{place_name} se fusionó con {target_name}. Tus registros se han movido.",
    },
  },
  place_suggestion_approved: {
    title: {
      ko: "수정 제안이 반영되었어요",
      en: "Your suggestion was applied",
      ja: "修正提案が反映されました",
      es: "Se aplicó tu sugerencia",
    },
    body: {
      ko: "{place_name}에 대한 수정 제안이 반영되었습니다. 감사합니다 🙌",
      en: "Your suggestion for {place_name} has been applied. Thank you 🙌",
      ja: "{place_name} の修正提案が反映されました。ありがとうございます 🙌",
      es: "Tu sugerencia para {place_name} se aplicó. ¡Gracias! 🙌",
    },
  },
  place_suggestion_rejected: {
    title: {
      ko: "수정 제안이 반려되었어요",
      en: "Your suggestion was rejected",
      ja: "修正提案が却下されました",
      es: "Se rechazó tu sugerencia",
    },
    body: {
      ko: "{place_name}에 대한 수정 제안이 반려되었어요.{reason_suffix}",
      en: "Your suggestion for {place_name} was rejected.{reason_suffix}",
      ja: "{place_name} の修正提案は却下されました。{reason_suffix}",
      es: "Tu sugerencia para {place_name} fue rechazada.{reason_suffix}",
    },
  },
};

export function primaryLocale(raw: string | null | undefined): Locale {
  if (!raw) return DEFAULT_LOCALE;
  const primary = raw.split("-", 2)[0].split("_", 2)[0].toLowerCase() as Locale;
  return SUPPORTED_LOCALES.includes(primary) ? primary : DEFAULT_LOCALE;
}

export function renderTemplate(
  type: keyof typeof TEMPLATES,
  locale: Locale,
  params: Record<string, string>,
): { title: string; body: string } {
  const entry = TEMPLATES[type];
  const fill = (s: string) => s.replace(/\{(\w+)\}/g, (_m, k) => params[k] ?? "");
  return { title: fill(entry.title[locale]), body: fill(entry.body[locale]) };
}
