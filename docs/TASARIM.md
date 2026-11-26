# QuestAtlas: Tasarım dokümanı

Bu doküman projenin nasıl kurulduğunu, ATLAS algoritmasının nasıl kullanıldığını ve hangi SOLID
ilkeleriyle tasarım desenlerinin **nerede ve neden** kullanıldığını anlatır. En sondaki
"Olası sorular" bölümü sözlü sınav / sunum hazırlığı içindir.

---

## 1. Mimari özet

```
WoW istemcisi ──olay──> Bootstrap ──> QuestAtlasFacade ──> QuestTracker ──> RoutePlanner ──> RouteStrategy ──> Atlas
   (veya WowMock)        (kurulum)       (tek giriş)         (durum)          (koordinasyon)    (algoritma seçimi)   (graf)
                                             │                    │
                         /qa komutları ──────┤                    └── EventBus ──"TRACKER_UPDATED"──> Facade ──> TrackerFrame
                         pencere butonları ──┘
```

| Katman | Klasör | Sorumluluk |
|---|---|---|
| Çekirdek | `Core/` | Lua için sınıf sistemi (metatable), `Interface` kontrolü, `EventBus`, yardımcılar |
| Algoritma | `Algorithm/` | ATLAS'ın Lua portu: `Atlas`, `Graph`, `Edge`, maliyet stratejileri |
| Alan modeli | `Domain/` | `Location`, `Quest`, `QuestObjective`, `RouteTask`, `Route`, `RouteStep` |
| Veri | `Data/` | Görev veritabanı ve harita ölçüleri (Classic/Forever API'si bunları vermiyor) |
| Servisler | `Services/` | WoW API adaptörü, repository, factory, oyunun harita işaretleri (POI), mesafe hesabı, ayarlar |
| Rota | `Routing/` | Görevleri ATLAS grafına çevirme, strateji seçimi, planlama |
| Takip | `Tracker/` | Güncel durum (görevler, konum, rota); değişince olay yayınlar |
| Arayüz | `UI/` | Presenter (metin üretir) + View (çizer) + WidgetFactory |
| Komutlar | `Commands/` | Her `/qa` komutu ayrı bir sınıf, bir zincir halinde |
| Giriş | `QuestAtlasFacade.lua`, `Bootstrap.lua` | Tek giriş noktası + nesnelerin kurulduğu yer |

Lua'da `class` anahtar kelimesi yok. Sınıflar `Core/Class.lua` içinde metatable'larla taklit edildi
(`ns.Class("Ad", ÜstSınıf)`). Arayüzler `Core/Interface.lua` içinde metot listesi olarak tanımlı ve
nesneler bağlanırken `Interface:assert(obj)` ile gerçekten kontrol ediliyor.

---

## 2. ATLAS algoritması

### 2.1 Ne yapar?

ATLAS (Savaş Takan), bir graftaki **tüm kenarları minimum maliyetle dolaşan** bir yürüyüş üretir.
Asıl kullanım alanı yazılım testi: sonlu durum makinesinin (FSM) her geçişini en az bir kez test eden
kısa bir test dizisi. Çin Postacısı (CPP) gibi yöntemler grafı önce "dengelemek" zorunda; ATLAS ise
grafı ön işlemden geçirmeden **dinamik programlama** ile çalışır.

### 2.2 Adım adım (`Algorithm/Atlas.lua` → `longestPath`)

1. Yürüyüşün son kenarını al (`currentStart`).
2. Bu kenardan başlayarak **kenarlar üzerinde DFS** yap. DFS'in bitiş sırasının tersi, her kenarın
   kendisini keşfeden kenardan sonra geldiği bir sıralama verir. Geri kenarlar yok sayıldığı için graf
   bir DAG (yönlü döngüsüz graf) gibi işlenir.
3. Kenarları bu sırayla işle ve DAG'da en uzun yol hesabı gibi **gevşet**:
   `maliyet[sonraki] = maliyet[kenar] + (sonraki zaten yürüyüşte mi ? 0 : 1)`.
   `comeFrom` her kenarın bir öncekini tutar.
4. Maliyeti en yüksek kenar, en iyi uzantının sonudur. `comeFrom` zinciriyle geri gidip bu uzantıyı
   yürüyüşe ekle.
5. Yeni kenar kazandırmayan bir uzantı kalmayınca dur.

Karmaşıklık: bir tur O(E·Δ), yani her kenar için hedef düğümün çıkış derecesi kadar iş. Tur sayısı en
fazla kapsanacak kenar sayısı + 1. Pratikte görev grafında genelde 2 tur yetiyor.

### 2.3 Java'dan Lua'ya port ve doğrulama

- `Edge.java`, `Graph.java`, `Atlas.java` birebir karşılıklarıyla taşındı (`dfs`, `longestPath`,
  `getTestSuite`, `run`).
- Özyinelemeli DFS, aynı bitiş sırasını üreten **iteratif** bir DFS'e çevrildi. Büyük graflarda Lua
  yığınını taşırmaz; testte 2 450 kenarlı bir graf var.
- **Doğrulama:** `tools/reference/generate_expected.py`, hocanın orijinal Java kodunu derleyip
  çalıştırarak beklenen çıktıları üretir. Lua portu bu 9 grafın hepsinde Java ile **birebir aynı**
  kenar dizisini veriyor: depodaki `bbtas.kiss2.fsm` ve 8 rastgele FSM (`tests/test_atlas.lua`).

### 2.4 Bulgu: Java sürümü yürüyüşün son kenarını düşürüyor

Java'daki döngü her turda `path.removeLast()` ile başlıyor. Ama sonlanma koşulunda
(`cost[current] <= 0`) o kenar geri eklenmeden `return path` yapılıyor. Sonuç olarak yürüyüşün son
kenarı kayboluyor.

`bbtas.kiss2.fsm` örneği (24 kenar):
- Java çıktısı 28 kenarlık bir yürüyüş ve **10 numaralı kenar (`2 --2/0--> 3`) hiç kapsanmıyor**.
- Lua portunda `keepLastEdge = true` (varsayılan): yürüyüş 29 kenar, **24 kenarın hepsi** kapsanıyor.
  İlk 28 kenar Java ile aynı, sonuna 10 ekleniyor.
- `keepLastEdge = false` ile Java davranışı birebir korunuyor. Testler iki modu da doğruluyor.

Ayrıca Java'da hiç gevşetme yapılamazsa (`current = Integer.MIN_VALUE`) dizi indeksi hatası oluşuyor.
Lua sürümü bu durumda yürüyüşü düzgünce bitiriyor.

> Hocaya söylerken: "Algoritmayı birebir taşıdık ve Java çıktısıyla karşılaştırarak test ettik.
> Sonlanmada son kenarın listeye geri eklenmediğini fark ettik; bunu bir seçenek yaptık, iki davranış
> da testli."

---

## 3. Görev problemi ATLAS'a nasıl dönüştü?

"Tüm görevleri bitiren en kısa rota", "tüm **zorunlu** kenarları kapsayan en kısa yürüyüş" olarak
modellendi (`Routing/QuestGraphBuilder.lua`):

| Graf öğesi | Görev dünyasındaki karşılığı |
|---|---|
| Düğüm | Bir yer: oyuncunun konumu, görev NPC'si, hedef bölgesi |
| **Zorunlu kenar** | Bir görev işi (`RouteTask`): ilk durağından son durağına. Ağırlık = görev içinde yürünen mesafe |
| Kendine dönen zorunlu kenar | Sadece teslim kalmış görev (NPC'nin düğümünde) |
| **Opsiyonel kenar** | İki yer arasında yolculuk (tam graf). Ağırlık = yarda cinsinden mesafe. Hiçbir şey "kapsamaz" |
| Başlangıç kenarı | Oyuncunun düğümünde opsiyonel bir döngü. ATLAS yürüyüşe bir kenardan başlar |

Bir görevin durakları her zaman aynı sırada: **al → hedefler → teslim et**
(`Routing/RouteTaskBuilder.lua`). Böylece "hedefi bitirmeden teslim etme" kuralı kendiliğinden korunur.
Aynı güzergâha sahip görevler tek kenarda birleştirilir.

ATLAS'a yapılan iki ekleme (ikisi de opsiyonel, varsayılan davranış Java ile aynı):
- `edge.required`: opsiyonel kenarlar kazanç saymaz. Varsayılan `true`, yani FSM'lerde fark yok.
- **`DistanceAwareCostPolicy`**: önce ATLAS'taki gibi "en çok yeni kenar". Eşitlikte **daha kısa
  mesafe** kazanır. (kazanç, mesafe) çifti tek sayıda saklanır: `kazanç·10⁹ − mesafe`. Böylece iç döngü
  tablo ayırmaz.

**Çok başlangıçlı ATLAS:** DFS'in komşuları hangi sırayla gezdiği, dinamik programlamanın kurabileceği
yolları belirler. `AtlasRouteStrategy` ATLAS'ı 4 farklı keşif sırasıyla çalıştırır ve en kısa rotayı
seçer. 12'den fazla görev varsa hız için tek sıra kullanılır.

**Ölçümler** (`tests/test_routing.lua`, 3–7 görevli 60 rastgele problem, kaba kuvvetle bulunan optimuma göre):

| Strateji | Ortalama fark (optimuma göre) |
|---|---|
| `bruteforce` (tüm sıralamaları dener) | %0 (optimum, ≤ 8 görev) |
| **`atlas`** | **+%5,7** |
| `nearest` (hep en yakın göreve git) | +%5,9 |

Standart Lua 5.1'de (WoW istemcisinin yorumlayıcısı) planlama süresi: 10 görev ≈ 29 ms,
20 görev ≈ 33 ms, 25 görev ≈ 66 ms.

**Gereksiz yeniden hesaplama yok:** `QUEST_LOG_UPDATE` her yaratık öldürmede tetiklenir. `RoutePlanner`
görev duraklarından bir **imza** (signature) üretir. Sadece ilerleme değiştiyse ("3/10" → "4/10"),
imza aynı kalır ve oyuncu 100 yarddan fazla uzaklaşmadıysa `QuestTracker` eski rotayı kullanır.
Kullanıcının elle istediği yenilemeler (`/qa refresh`, buton, strateji) her zaman yeniden hesaplar.

### 3.1 Konum verisi nereden geliyor?

| İstemci | Görev konumu | Sınıf |
|---|---|---|
| WoW: Forever / Classic | Eklentinin veritabanı (`Data/QuestData.lua`) | `QuestRepository` |
| Retail (12.x) | Önce veritabanı; bilinmeyen görevlerde **oyunun harita işareti** (POI) | `GameQuestPoiProvider` |

- `WowApiAdapter:getQuestPoiLocations()` önce `C_QuestLog.GetQuestsOnMap(harita)` ile oyuncunun
  haritasına, sonra üst haritalarına (bölge → kıta) bakar. Bulamadığı görevler için
  `C_QuestLog.GetNextWaypoint(görev)` kullanır. Her çağrı `pcall` ile korunur.
- Oyunun işareti, açık görevde **hedef bölgesini**, hedefler bitince **teslim NPC'sini** gösterir.
  `QuestFactory` bunu duruma göre hedefin ya da teslimin konumu yapar. Teslim yeri bilinmeyen açık
  görevler rotaya sadece hedefleriyle girer.
- Bu API'nin olmadığı istemcilerde `NullQuestPoiProvider` (**Null Object**) kullanılabilir: hiç işaret
  döndürmez, çağıranın `if` yazmasına gerek kalmaz.
- Başka kıtadaki duraklar rotada sona kalır (ceza mesafesi) ve ekranda "başka kıta" yazar.

---

## 4. SOLID

| İlke | Projede nerede | Kısaca |
|---|---|---|
| **S** (Single Responsibility, tek sorumluluk) | `TrackerPresenter` sadece metin üretir, `TrackerFrame` sadece çizer. `QuestLogReader` sadece günlüğü okur. `WowApiAdapter` WoW API'sini çağıran tek sınıftır. Her `/qa` komutu ayrı sınıftır | Değişmesi için tek bir sebebi olan sınıflar |
| **O** (Open/Closed, değişime kapalı, gelişime açık) | Yeni rota algoritması `RouteStrategyFactory:register()` ile eklenir. Yeni görev kaynağı `QuestFactory:registerCreator()` ile eklenir. Yeni komut, bir sınıf yazıp `CommandChainFactory.ORDER`'a eklemekle olur. Yeni dinleyici `EventBus:subscribe()` ile bağlanır | Mevcut sınıflar değişmeden yeni davranış eklenir (testlerde gösteriliyor) |
| **L** (Liskov Substitution, yerine geçebilme) | `atlas`, `nearest`, `bruteforce` aynı `IRouteStrategy` sözleşmesine uyar. Hepsi `RouteAssembler` ile aynı biçimde `Route` döner. Bir test üç stratejiyi 40 rastgele problemde **aynı kurallarla** doğrular | Hangisi verilirse verilsin çağıran fark etmez |
| **I** (Interface Segregation, arayüz ayrımı) | Küçük arayüzler: `IQuestSource` (1 metot), `IPositionProvider` (1), `IDistanceCalculator` (1), `IMapGeometry` (1), `ISettingsStore` (2), `IRouteStrategy` (2) | Kimse kullanmadığı metoda bağımlı değil |
| **D** (Dependency Inversion, bağımlılığın tersine çevrilmesi) | `QuestTracker` somut sınıfları değil arayüzleri alır (constructor injection). Somut sınıfları sadece `Bootstrap.lua` (composition root) bilir. Testler aynı kodu sahte WoW API'siyle çalıştırabiliyor | Üst katman alt katmanın soyutlamasına bağlı |

---

## 5. Tasarım desenleri

| Desen | Sınıf(lar) | Dosya | Neden kullandık? |
|---|---|---|---|
| **Facade** | `QuestAtlasFacade` | `QuestAtlasFacade.lua` | Komutlar, butonlar ve olaylar onlarca sınıf yerine tek bir sınıfla konuşur. Alt sistemi değiştirsek de çağıranlar etkilenmez |
| **Factory Method** (parametreli) | `QuestFactory.create(kind, source)`, `RouteStrategyFactory.create(name)`, `CostPolicyFactory.create(name)`, `WidgetFactory`, `CommandChainFactory` | `Services/QuestFactory.lua`, `Routing/RouteStrategyFactory.lua`, ... | Nesne oluşturma tek bir yerde toplanır. Çağıran somut sınıfı bilmez; yeni tür kayıt edilerek eklenir |
| **Strategy** | `IRouteStrategy` → `AtlasRouteStrategy` / `NearestNeighborRouteStrategy` / `BruteForceRouteStrategy`; `ICostPolicy` → `UnitCostPolicy` / `DistanceAwareCostPolicy`; keşif sıraları (`QuestGraphBuilder.ORDERS`) | `Routing/RouteStrategies.lua`, `Algorithm/CostPolicies.lua` | Algoritma çalışırken değiştirilebilir (`/qa strategy`). ATLAS'ın maliyet fonksiyonu değiştirilebilir |
| **Chain of Responsibility** | `CommandHandler` → `HelpCommand`, `RouteCommand`, ... → `UnknownCommand`; `ChainedMapGeometry` | `Commands/`, `Services/MapGeometry.lua` | Uzun bir `if/elseif` yerine her komut kendi sınıfında. İşleyemeyen bir sonrakine verir. Harita koordinatı önce oyun API'sinden, olmazsa tablodan alınır |
| **Template Method** | `CommandHandler:handle()` sabit; alt sınıflar sadece `execute()` yazar | `Commands/CommandHandler.lua` | Ortak akış ("benim mi? değilse sıradakine ver") tek yerde |
| **Observer** | `EventBus`; `QuestTracker` `TRACKER_UPDATED` yayınlar, arayüz dinler | `Core/EventBus.lua` | Tracker arayüzün varlığından habersiz. Arayüz olmadan da (testlerde) çalışır |
| **Adapter** | `WowApiAdapter` | `Services/WowApiAdapter.lua` | Eski (`GetQuestLogTitle`) ve yeni (`C_QuestLog`) WoW görev API'lerini tek arayüze çevirir. Forever hangisini sunarsa çalışır |
| **Repository** | `QuestRepository` | `Services/QuestRepository.lua` | Görev verisine erişim tek yerden. Veri kaynağı değişse de çağıranlar değişmez |
| **Null Object** | `NullQuestPoiProvider` | `Services/QuestPoiProvider.lua` | "Harita işareti yok" durumu da bir nesne. `QuestLogReader` hiçbir zaman `nil` kontrolü yapmaz |
| **MVP** (Model-View-Presenter) | `TrackerPresenter` + `TrackerFrame` (`ITrackerView`) | `UI/` | Biçimlendirme mantığı oyun olmadan test edilebilir |
| **Composition Root / Dependency Injection** | `ns.CreateApp()` | `Bootstrap.lua` | Tüm somut sınıflar tek yerde birbirine bağlanır |

---

## 6. Olası sorular ve kısa cevaplar

**Facade nedir, neden kullandınız?**
Karmaşık bir alt sisteme basit, tek bir giriş noktası sağlar. Bizde slash komutları, pencere
butonları ve oyun olayları sadece `QuestAtlasFacade`'i çağırıyor. Tracker, planlayıcı, repository ve
API adaptörü arkada gizli. Alt sistem değişse de çağıranlar değişmiyor.

**Factory Method nedir? Sizinki neden "parametreli"?**
Nesne oluşturmayı bir metoda devreder; çağıran `new SomutSınıf()` yazmaz. GoF kitabında
"parameterized factory method" diye bir varyasyon var: metot, hangi ürünü üreteceğini bir parametreyle
seçer. Bizim `QuestFactory:create("log" | "planned", kaynak)` ve
`RouteStrategyFactory:create("atlas" | "nearest" | "bruteforce")` bu türden. Yeni ürün `register`
ile ekleniyor, `create` metodu değişmiyor (Open/Closed).

**Strategy ile Template Method farkı?**
Strategy'de algoritmanın **tamamı** değiştirilebilir bir nesnedir ve çalışma anında değiştirilir
(`/qa strategy nearest`). Template Method'da algoritmanın **iskeleti** üst sınıfta sabittir, alt
sınıflar sadece bazı adımları doldurur (`CommandHandler:handle()` sabit, `execute()` değişir).
Strategy kompozisyonla, Template Method kalıtımla çalışır.

**Chain of Responsibility'nin if-else'e üstünlüğü?**
Yeni komut eklemek mevcut kodu değiştirmeyi gerektirmiyor; bir sınıf yazıp zincire ekleniyor.
Her komut ayrı ayrı test edilebiliyor. Zincirin sonundaki `UnknownCommand` bilinmeyen komutları yakalıyor.

**Observer'ı nerede, neden kullandınız?**
`QuestTracker` rota değişince `EventBus` üzerinden `TRACKER_UPDATED` yayınlıyor. Pencere bunu dinleyip
kendini yeniliyor. Tracker arayüzü bilmiyor, yani arayüz olmadan da test edilebiliyor.

**Adapter neden gerekli?**
WoW'un iki farklı görev API'si var: klasik `GetQuestLogTitle` / `GetQuestLogLeaderBoard` ve yeni
`C_QuestLog`. Forever'ın hangisini sunduğunu bilmediğimiz için `WowApiAdapter` ikisini de aynı düz
tabloya çeviriyor. İkisi de testli.

**Dependency Inversion nerede?**
`QuestTracker` constructor'da `IQuestSource`, `IPositionProvider`, `IDistanceCalculator` gibi
arayüzler alıyor. Somut sınıfları sadece `Bootstrap.lua` biliyor. Bu sayede aynı kod oyunda gerçek
API'yle, testte sahte API'yle çalışıyor.

**Liskov'u nasıl gösterirsiniz?**
`tests/test_routing.lua`: üç strateji de aynı 40 rastgele problemde aynı kurallarla doğrulanıyor.
Her görev bir kez, önce al, sonra hedef, en son teslim; mesafeler tutarlı.

**Lua'da sınıf/arayüz yokken bunları nasıl yaptınız?**
Sınıflar metatable ile (`Core/Class.lua`): `__index` zinciri kalıtımı sağlıyor. Arayüzler metot
isimleri listesi (`Core/Interface.lua`). Bağlama sırasında `assert` ile eksik metot varsa hata
veriliyor.

**ATLAS'ı neden doğrudan TSP gibi kullanmadınız?**
ATLAS kenar kapsama algoritması. Görevleri **kenar**, yolculuğu **opsiyonel kenar** yaparak problemi
onun diline çevirdik. Mesafeyi ikincil ölçüt olarak ekledik. Optimuma ortalama %5,7 uzaklıkta;
açgözlü yöntemden biraz daha iyi.

**Retail'de veritabanı olmadan nasıl rota çıkıyor?**
Oyun görev hedeflerini haritada zaten işaretliyor. `GameQuestPoiProvider` bu işaretleri
`WowApiAdapter` üzerinden okuyor; `QuestFactory` veritabanında olmayan görevlerin konumunu bunlarla
dolduruyor. Böylece aynı ATLAS kodu her iki istemcide çalışıyor (Open/Closed: mevcut sınıflar
değişmeden yeni bir veri kaynağı eklendi).

**Null Object nedir?**
"Yok" durumunu `nil` yerine hiçbir şey yapmayan bir nesneyle temsil etmek. `NullQuestPoiProvider`
boş tablo döndürür; çağıran kod "sağlayıcı var mı?" diye kontrol etmez.

**ATLAS'ın karmaşıklığı?**
Bir tur O(E·Δ), tur sayısı en fazla kapsanacak kenar sayısı + 1. Ön işlem (graf dengeleme) yok;
CPP / H-Switch-Cover'dan farkı bu.

---

## 7. Testler

`luajit tools/run_tests.lua` komutu 82 testi çalıştırır. Testler standart Lua 5.1'de de geçiyor.

| Dosya | Ne test ediliyor |
|---|---|
| `test_core.lua` | sınıf sistemi, arayüzler, EventBus, dil dosyaları (eksik anahtar, `\|` karakteri yasak) |
| `test_atlas.lua` | Java ile birebir aynı çıktı (9 graf), son kenar bulgusu, tam kapsama, ölü uç, büyük graf |
| `test_services.lua` | API adaptörü (iki API türü), harita geometrisi, mesafe, repository, factory, ayarlar |
| `test_routing.lua` | görev → graf, üç stratejinin geçerliliği (Liskov), optimuma yakınlık, factory |
| `test_commands.lua` | tüm `/qa` komutları simüle istemcide |
| `test_integration.lua` | `.toc` yükleme, global sızıntısı yok, oyun senaryoları, `/reload` sonrası ayarlar, butonlar |
| `test_retail.lua` | retail istemci: harita işaretleri, üst harita araması, bozuk API'ye dayanıklılık, bonus hedeflerin atlanması, rota yeniden kullanımı, harita iğnesi, `/qa debug` |

`tools/mock/WowMock.lua` (oyunun yerine geçen katman) bilinçli olarak katı: oyunda hata verecek
şeyler (bilinmeyen olay, şablon, font, çapa noktası) burada da hata veriyor. Bu sayede gerçek bir hata
yakalandı: WoW metindeki `|` karakterini kaçış kodu sayar; `add|remove` oyunda `addemove`
görünüyordu, düzeltildi.

### 7.1 Gerçek oyunda deneme (26.11.2026)

Eklenti retail istemcide (12.1.5, build 70961), yeni bir karakterle Exile's Reach'te denendi.
Ekran görüntüleri `docs/oyun/` klasöründe.

| Ne denendi | Sonuç | Görüntü |
|---|---|---|
| `.toc` yükleme, pencere, Türkçe metin | Hatasız yüklendi, Lua hatası yok | `01-ilk-yukleme.png` |
| İstemci / API tespiti (`/qa debug`) | 12.1.5, arayüz 120105, modern görev API'si, harita işareti ve iğne API'leri var | `02`, `03` |
| Oyuncu konumu | Açılıştaki gemide (harita 1726) oyun koordinat vermiyor; adada (1409) doğru | `02`, `03` |
| Görevin yeri oyunun harita işaretinden (`GetQuestsOnMap`) | Doğru: oyunun işaretiyle aynı nokta, "oyun işareti: 1" | `04`, `05`, `06` |
| `/qa next` → haritaya iğne | İğne konuldu, sohbette onay | `07` |
| Hedefler bitince teslim adımı | "Teslim et: Emergency First Aid @ (61.9, 82.9) - 11 yd", teslim NPC'si tam orada | `08` |

Gemide konum gelmemesi eklentinin hatası değil: oyun o bölümde haritayı (`GetBestMapForUnit`) verip
koordinatı (`GetPlayerMapPosition`) vermiyor. Eklenti bu durumda çökmeden "konum bilinmiyor" gösteriyor;
`/qa debug` hangi haritada olunduğunu da yazıyor. Exile's Reach'in başı sıralı olduğu için (bir görev
bitmeden yenisi açılmıyor) çok görevli rota oyunda değil, simülasyondaki testlerde sınandı.
