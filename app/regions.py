"""ISO 3166-2:UA codes to the names the alert feed uses.

Matching on English names ("Ternopil Oblast", "Ternopils'ka oblast",
"Ternopil") is a guessing game; the ISO code is one short string both sides
agree on. The feed covers 26 regions — every oblast, Kyiv city and Sevastopol.
"""

BY_ISO = {
    "05": "Вінницька область",
    "07": "Волинська область",
    "09": "Луганська область",
    "12": "Дніпропетровська область",
    "14": "Донецька область",
    "18": "Житомирська область",
    "21": "Закарпатська область",
    "23": "Запорізька область",
    "26": "Івано-Франківська область",
    "30": "м. Київ",
    "32": "Київська область",
    "35": "Кіровоградська область",
    "40": "Севастополь",
    "46": "Львівська область",
    "48": "Миколаївська область",
    "51": "Одеська область",
    "53": "Полтавська область",
    "56": "Рівненська область",
    "59": "Сумська область",
    "61": "Тернопільська область",
    "63": "Харківська область",
    "65": "Херсонська область",
    "68": "Хмельницька область",
    "71": "Черкаська область",
    "74": "Чернігівська область",
    "77": "Чернівецька область",
}

# A fallback for services that give a name and no code. Deliberately keyed on
# the distinctive stem, so "Ternopil", "Ternopil Oblast" and "Ternopils'ka
# oblast" all land in the same place.
BY_STEM = {
    "vinnyts": "05", "volyn": "07", "luhans": "09", "dnipropetrov": "12",
    "donets": "14", "zhytomyr": "18", "zakarpat": "21", "transcarpath": "21",
    "zaporiz": "23", "ivano": "26", "frankiv": "26", "kirovohrad": "35",
    "kropyvnyts": "35", "sevastopol": "40", "lviv": "46", "mykolaiv": "48",
    "odes": "51", "poltav": "53", "rivne": "56", "sum": "59", "ternopil": "61",
    "kharkiv": "63", "kherson": "65", "khmelnyts": "68", "cherkas": "71",
    "chernihiv": "74", "chernivts": "77",
}


def from_iso(code: str) -> str | None:
    if not code:
        return None
    return BY_ISO.get(str(code).strip().upper().removeprefix("UA-").zfill(2))


def from_name(name: str) -> str | None:
    """Kyiv is the trap: the city and the oblast share a stem, so it is decided
    before anything else and only on an exact-enough reading."""
    if not name:
        return None
    text = name.strip().lower()
    if "kyiv" in text or "kiev" in text:
        return BY_ISO["32"] if "oblast" in text or "region" in text else BY_ISO["30"]
    for stem, code in BY_STEM.items():
        if stem in text:
            return BY_ISO[code]
    return None
