import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "app"))
from regions import BY_ISO, from_iso, from_name  # noqa: E402


def test_every_feed_region_is_reachable_by_code():
    feed = {
        "Івано-Франківська область", "Волинська область", "Вінницька область",
        "Дніпропетровська область", "Донецька область", "Житомирська область",
        "Закарпатська область", "Запорізька область", "Київська область",
        "Кіровоградська область", "Луганська область", "Львівська область",
        "Миколаївська область", "Одеська область", "Полтавська область",
        "Рівненська область", "Севастополь", "Сумська область",
        "Тернопільська область", "Харківська область", "Херсонська область",
        "Хмельницька область", "Черкаська область", "Чернівецька область",
        "Чернігівська область", "м. Київ",
    }
    assert set(BY_ISO.values()) == feed, set(BY_ISO.values()) ^ feed


def test_codes_are_read_in_the_shapes_services_send_them():
    for code in ("61", 61, "UA-61", "ua-61", " 61 "):
        assert from_iso(code) == "Тернопільська область", code
    assert from_iso("5") == "Вінницька область", "a code without its leading zero"
    assert from_iso("") is None and from_iso("99") is None


def test_names_fall_back_when_a_service_sends_no_code():
    assert from_name("Ternopil Oblast") == "Тернопільська область"
    assert from_name("Ternopil") == "Тернопільська область"
    assert from_name("Ternopils'ka oblast") == "Тернопільська область"
    assert from_name("Ivano-Frankivsk Oblast") == "Івано-Франківська область"
    assert from_name("Transcarpathia") == "Закарпатська область"
    assert from_name("somewhere else entirely") is None


def test_kyiv_city_is_not_kyiv_oblast():
    assert from_name("Kyiv") == "м. Київ"
    assert from_name("Kyiv City") == "м. Київ"
    assert from_name("Kyiv Oblast") == "Київська область"
    assert from_name("Kiev region") == "Київська область"
    assert from_iso("30") == "м. Київ" and from_iso("32") == "Київська область"


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn(); print("  ok   " + name[5:].replace("_", " "))
        except AssertionError as e:
            failed += 1; print(f"  FAIL {name[5:].replace('_',' ')}\n       {e}")
    print(f"\n{failed} failing" if failed else "\nall passing")
    sys.exit(1 if failed else 0)
