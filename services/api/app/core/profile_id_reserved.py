"""
예약어 / 욕설 데이터. profile_id.py의 검증 함수가 이 모듈을 참조한다.

RESERVED_EXACT: 정확히 일치하는 경우만 차단. O(1) 조회를 위해 frozenset.
PROFANITY_SUBSTRINGS: 부분 포함만 돼도 차단. 리스트 짧으니 선형 스캔.
"""

RESERVED_EXACT: frozenset[str] = frozenset(
    {
        # 시스템/관리
        "admin", "administrator", "root", "system", "superuser", "sudo",
        "moderator", "mod", "staff", "owner", "operator",
        # 플랫폼
        "besetter", "besetterofficial", "official", "support", "help",
        "helpdesk", "contact", "info", "faq", "guide", "docs", "notice",
        # API/경로
        "api", "www", "app", "web", "mobile", "ios", "android", "graphql",
        "rest", "static", "assets", "media", "images", "files", "upload",
        "download", "cdn",
        # 인증/보안
        "auth", "login", "logout", "signin", "signup", "register",
        "password", "token", "session", "security", "verify", "oauth", "sso",
        # 유저
        "user", "users", "me", "self", "profile", "account", "guest",
        "anonymous", "null", "undefined", "nobody", "everyone", "all",
        # 컨텐츠
        "home", "explore", "search", "discover", "feed", "trending",
        "popular", "new", "latest", "recommended",
        # 도메인 (클라이밍)
        "route", "routes", "place", "places", "gym", "gyms", "wall", "walls",
        "climb", "climber", "climbing", "boulder", "bouldering", "lead",
        "sport", "trad",
        # 결제/상거래
        "billing", "payment", "payments", "pay", "checkout", "cart", "order",
        "orders", "subscribe", "subscription", "plan", "pricing", "store",
        "shop",
        # 법률
        "terms", "tos", "privacy", "policy", "legal", "license", "copyright",
        "dmca", "abuse", "report",
        # 개발자
        "dev", "developer", "developers", "test", "tests", "testing",
        "staging", "production", "beta", "alpha", "debug",
    }
)

PROFANITY_SUBSTRINGS: tuple[str, ...] = (
    # 영문
    "fuck", "shit", "bitch", "asshole", "bastard", "dick", "pussy", "cock",
    "cunt", "whore", "slut", "faggot", "nigger", "retard", "nazi",
    # 한글 로마자
    "siba", "sibal", "ssibal", "gaesaeki", "gaesaekki", "jotna", "jonna",
    "byungshin", "byungsin", "michinnom", "michinnyeon", "gechaek",
    "gaechaek", "jibjang", "jotmani", "jotmanj", "jotmadchi",
)
