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
}
