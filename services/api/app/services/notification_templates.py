"""Notification message templates keyed by type, field, and locale.

Templates are rendered at response time from Notification.params.
Placeholders use Python str.format syntax, e.g. "{place_name}".
"""

SUPPORTED_LOCALES: tuple[str, ...] = ("ko", "en", "ja", "es")
DEFAULT_LOCALE: str = "ko"

TEMPLATES: dict[str, dict[str, dict[str, str]]] = {
    "place_registration_ack": {
        "title": {
            "ko": "암장 등록 요청이 접수되었습니다",
            "en": "Your gym registration request has been received",
            "ja": "クライミングジム登録リクエストを受け付けました",
            "es": "Tu solicitud de registro de gimnasio ha sido recibida",
        },
        "body": {
            "ko": "{place_name} 등록 요청 감사합니다 🙌 빠르게 확인 후 반영하겠습니다.",
            "en": "Thanks for requesting to register {place_name} 🙌 We'll review and apply it shortly.",
            "ja": "{place_name} の登録リクエストありがとうございます 🙌 早急に確認して反映します。",
            "es": "Gracias por solicitar el registro de {place_name} 🙌 Lo revisaremos y aplicaremos pronto.",
        },
    },
    "place_suggestion_ack": {
        "title": {
            "ko": "장소 정보 수정 제안이 접수되었습니다",
            "en": "Your place info update suggestion has been received",
            "ja": "スポット情報の修正提案を受け付けました",
            "es": "Tu sugerencia de actualización del lugar ha sido recibida",
        },
        "body": {
            "ko": "{place_name}에 대한 소중한 제보 감사합니다 🙌 빠르게 확인 후 반영하겠습니다.",
            "en": "Thanks for your input on {place_name} 🙌 We'll review and apply it shortly.",
            "ja": "{place_name} に関するご提案ありがとうございます 🙌 早急に確認して反映します。",
            "es": "Gracias por tu aporte sobre {place_name} 🙌 Lo revisaremos y aplicaremos pronto.",
        },
    },
    "place_review_passed": {
        "title": {
            "ko": "암장이 등록되었어요",
            "en": "Your gym has been approved",
            "ja": "クライミングジムが登録されました",
            "es": "Tu gimnasio ha sido aprobado",
        },
        "body": {
            "ko": "{place_name} 등록이 승인되었어요. 지금 바로 확인해보세요!",
            "en": "{place_name} has been approved. Check it out!",
            "ja": "{place_name} の登録が承認されました。今すぐ確認してみてください！",
            "es": "¡{place_name} ha sido aprobado. Échale un vistazo!",
        },
    },
    "place_review_failed": {
        "title": {
            "ko": "암장 등록이 반려되었어요",
            "en": "Your gym registration was rejected",
            "ja": "クライミングジムの登録が却下されました",
            "es": "Se rechazó el registro de tu gimnasio",
        },
        "body": {
            "ko": "{place_name} 등록이 반려되었어요.{reason_suffix}",
            "en": "{place_name} was rejected.{reason_suffix}",
            "ja": "{place_name} の登録は却下されました。{reason_suffix}",
            "es": "El registro de {place_name} fue rechazado.{reason_suffix}",
        },
    },
    "place_merged": {
        "title": {
            "ko": "등록한 암장이 병합되었어요",
            "en": "Your gym was merged into an existing one",
            "ja": "登録したジムが既存のスポットに統合されました",
            "es": "Tu gimnasio fue fusionado con uno existente",
        },
        "body": {
            "ko": "{place_name} 은(는) 기존 {target_name}(으)로 병합되었어요. 올려주신 기록은 그대로 옮겨졌습니다.",
            "en": "{place_name} was merged into {target_name}. Your uploads have been moved over.",
            "ja": "{place_name} は {target_name} に統合されました。アップロードいただいた記録はそのまま移動されました。",
            "es": "{place_name} se fusionó con {target_name}. Tus registros se han movido.",
        },
    },
    "place_suggestion_approved": {
        "title": {
            "ko": "수정 제안이 반영되었어요",
            "en": "Your suggestion was applied",
            "ja": "修正提案が反映されました",
            "es": "Se aplicó tu sugerencia",
        },
        "body": {
            "ko": "{place_name}에 대한 수정 제안이 반영되었습니다. 감사합니다 🙌",
            "en": "Your suggestion for {place_name} has been applied. Thank you 🙌",
            "ja": "{place_name} の修正提案が反映されました。ありがとうございます 🙌",
            "es": "Tu sugerencia para {place_name} se aplicó. ¡Gracias! 🙌",
        },
    },
    "place_suggestion_rejected": {
        "title": {
            "ko": "수정 제안이 반려되었어요",
            "en": "Your suggestion was rejected",
            "ja": "修正提案が却下されました",
            "es": "Se rechazó tu sugerencia",
        },
        "body": {
            "ko": "{place_name}에 대한 수정 제안이 반려되었어요.{reason_suffix}",
            "en": "Your suggestion for {place_name} was rejected.{reason_suffix}",
            "ja": "{place_name} の修正提案は却下されました。{reason_suffix}",
            "es": "Tu sugerencia para {place_name} fue rechazada.{reason_suffix}",
        },
    },
}
