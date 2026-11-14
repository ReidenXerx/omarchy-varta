import Testing
@testable import VartaCore

// Port of tests/test_regions.py.

let feedRegions: Set<String> = [
    "Івано-Франківська область", "Волинська область", "Вінницька область",
    "Дніпропетровська область", "Донецька область", "Житомирська область",
    "Закарпатська область", "Запорізька область", "Київська область",
    "Кіровоградська область", "Луганська область", "Львівська область",
    "Миколаївська область", "Одеська область", "Полтавська область",
    "Рівненська область", "Севастополь", "Сумська область",
    "Тернопільська область", "Харківська область", "Херсонська область",
    "Хмельницька область", "Черкаська область", "Чернівецька область",
    "Чернігівська область", "м. Київ",
]

@Test func everyFeedRegionIsReachableByCode() {
    #expect(Set(Regions.byISO.values) == feedRegions)
    #expect(Regions.all.count == 26)
}

@Test func codesAreReadInTheShapesServicesSendThem() {
    for code in ["61", "UA-61", "ua-61", " 61 "] {
        #expect(Regions.fromISO(code) == "Тернопільська область", "\(code)")
    }
    #expect(Regions.fromISO("5") == "Вінницька область", "a code without its leading zero")
    #expect(Regions.fromISO("") == nil && Regions.fromISO("99") == nil)
}

@Test func namesFallBackWhenAServiceSendsNoCode() {
    #expect(Regions.fromName("Ternopil Oblast") == "Тернопільська область")
    #expect(Regions.fromName("Ternopil") == "Тернопільська область")
    #expect(Regions.fromName("Ternopils'ka oblast") == "Тернопільська область")
    #expect(Regions.fromName("Ivano-Frankivsk Oblast") == "Івано-Франківська область")
    #expect(Regions.fromName("Transcarpathia") == "Закарпатська область")
    #expect(Regions.fromName("somewhere else entirely") == nil)
}

@Test func kyivCityIsNotKyivOblast() {
    #expect(Regions.fromName("Kyiv") == "м. Київ")
    #expect(Regions.fromName("Kyiv City") == "м. Київ")
    #expect(Regions.fromName("Kyiv Oblast") == "Київська область")
    #expect(Regions.fromName("Kiev region") == "Київська область")
    #expect(Regions.fromISO("30") == "м. Київ" && Regions.fromISO("32") == "Київська область")
}
