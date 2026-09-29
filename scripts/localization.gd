class_name GameLocalization
extends RefCounted

const RUSSIAN := "ru"
const ENGLISH := "en"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"

static var language := RUSSIAN
static var settings_path := DEFAULT_SETTINGS_PATH
static var _cache: Dictionary = {}
static var _dynamic_rules: Array[Dictionary] = []
static var _rules_ready := false

const EN := {
	"Далекий полет": "Far Flight",
	"Далекий полет — Почтовая авиация": "Far Flight — Airmail",
	"ПОЧТОВАЯ АВИАЦИЯ": "AIRMAIL",
	"Об игре": "About",
	"Авторы": "Credits",
	"Назад": "Back",
	"НАЗАД": "BACK",
	"Язык": "Language",
	"ЯЗЫК": "LANGUAGE",
	"Русский": "Russian",
	"Английский": "English",
	"НОВАЯ ИГРА": "NEW GAME",
	"Новая игра": "New game",
	"ПОСАДКА": "LANDING PRACTICE",
	"Посадка": "Landing practice",
	"ТРЕНИРОВКА ПОСАДКИ": "LANDING PRACTICE",
	"Начать игру": "Start game",
	"Начать заново": "Restart",
	"В главное меню": "Main menu",
	"Продолжить": "Continue",
	"Продолжить • seed %d": "Continue • seed %d",
	"Вернуться к итогам": "Return to results",
	"Вернуться к итогам • seed %d": "Return to results • seed %d",
	"Итоги": "Results",
	"Итоги • seed %d": "Results • seed %d",
	"ИТОГИ ПРОХОЖДЕНИЯ": "RUN RESULTS",
	"ПАУЗА": "PAUSED",
	"Статистика полётов": "Flight history",
	"Сохранить и выйти": "Save and quit",
	"Выйти": "Quit",
	"Выход": "Quit",
	"README — подробная справка": "README — full guide",
	"Подробнее обо всех приборах, механиках и управлении:": "Read more about all instruments, mechanics, and controls:",
	"Seed мира — пусто: случайный": "World seed — blank: random",
	"Введите seed от 1 до 2147483647, чтобы воспроизвести тот же мир. Оставьте поле пустым для случайного seed.": "Enter a seed from 1 to 2147483647 to reproduce the same world. Leave it blank for a random seed.",
	"Seed должен быть целым числом.": "Seed must be an integer.",
	"Seed должен находиться в диапазоне от 1 до 2147483647.": "Seed must be between 1 and 2147483647.",
	"Сохранение повреждено или несовместимо с этой версией.": "The save is corrupted or incompatible with this version.",
	"Сохранение не записано: %s%s. Игра не закрыта.": "Save not written: %s%s. The game was not closed.",
	"Итоги прохождения не сохранены: %s%s.": "Run results were not saved: %s%s.",
	"Не удалось прочитать сохранение.": "Could not read the save.",
	"Не удалось восстановить сохранение. Файл не изменён.": "Could not restore the save. The file was not changed.",
	"Можно закрыть вкладку. Сохранения хранятся в этом браузере.": "You may close the tab. Saves are stored in this browser.",
	"Вы — почтальон-пилот. Между затерянными аэродромами почтовая авиация связывает людей: посылки, письма и вести издалека должны добраться до адресата. Выбирайте заказы на почте, загружайте самолёт и составляйте выгодные маршруты для нескольких доставок. Дальние заказы оплачиваются лучше.\n\nНо здесь небо почти никогда не бывает ясным. Уже в ста метрах над землёй начинается сплошная облачность. Дальше — полёт по приборам: курс, высота, скорость, сигналы радиомаяков и ваши пометки на карте. Положение самолёта на ней не отмечено — его предстоит определить самому.\n\nУчитывайте ветер, обходите грозы и планируйте остановки: топливо, еда, гостиницы и ремонтные ангары есть не на каждом аэродроме. Канистры и грузы занимают место, пилоту нужно есть и отдыхать, а самолёт постепенно изнашивается — особенно в грозах и при превышении безопасной скорости. Летайте между аэродромами, доставляйте почту и зарабатывайте деньги на новые рейсы.": "You are an airmail pilot. Between remote airfields, mail aviation keeps people connected: parcels, letters, and news from afar must reach their destinations. Take jobs at the post office, load the aircraft, and plan profitable routes with multiple deliveries. Longer jobs pay better.\n\nThe sky here is almost never clear. A solid cloud layer begins only one hundred metres above the ground. Beyond it, you fly by instruments: heading, altitude, speed, radio beacon signals, and your own marks on the map. Your aircraft position is not shown, so you must determine it yourself.\n\nAccount for the wind, avoid thunderstorms, and plan your stops: fuel, food, hotels, and repair hangars are not available at every airfield. Fuel cans and cargo take space, the pilot needs food and rest, and the aircraft slowly wears out—especially in storms and above its safe speed. Fly between airfields, deliver mail, and earn money for future flights.",

	"НАВИГАЦИОННАЯ КАРТА": "NAVIGATION MAP",
	"Метеосводка: возраст %s": "Weather report age: %s",
	"только что": "just now",
	"%d мин": "%d min",
	"%d ч %02d мин": "%d h %02d min",
	"Колесо: масштаб": "Wheel: zoom",
	"ЛКМ с движением: карта": "LMB drag: pan map",
	"ЛКМ: точка/линия": "LMB: point/line",
	"ПКМ: отмена/стереть": "RMB: cancel/delete",
	"Колесо над приёмником: 1 кГц, с Shift: 10 кГц": "Wheel over receiver: 1 kHz, with Shift: 10 kHz",
	" • колесо вниз: отдалить": " • wheel down: zoom out",
	"10 км": "10 km",
	"%d км": "%d km",
	"%d м": "%d m",
	"V: ветер [%s]": "V: wind [%s]",
	"Ветер: ": "Wind: ",
	"У поверхности": "At surface",
	"у поверхности": "at surface",
	"текущая %.0f м": "current %.0f m",
	"от %03d° • %.0f км/ч • %.0f м": "from %03d° • %.0f km/h • %.0f m",
	"≈%03d° • ≈%d км/ч": "≈%03d° • ≈%d km/h",
	"%.1f км • %s  %s  %.0f м": "%.1f km • %s  %s  %.0f m",
	"%s • путь %.1f км • время %s": "%s • distance %.1f km • time %s",
	"— мин": "— min",
	"%.1f мин": "%.1f min",
	"Линия такой длины и направления выходит за границу карты": "A line of this length and direction extends beyond the map",
	"Связанную линию невозможно обновить": "The linked line cannot be updated",
	"%s %.0f кГц R%.0f": "%s %.0f kHz R%.0f",
	"▲ %.0f м": "▲ %.0f m",
	"%.1f км • %.0f м • %.1f м/с": "%.1f km • %.0f m • %.1f m/s",
	"%.1f км • %.0f м": "%.1f km • %.0f m",
	"%03d° • %.0f км/ч": "%03d° • %.0f km/h",

	"МЕТЕОРАДАР [B]": "WEATHER RADAR [B]",
	"МЕТЕОРАДАР 30 км [B]": "WEATHER RADAR 30 km [B]",
	"КАРТА [B]": "MAP [B]",
	"КАРТА [I]": "MAP [I]",
	"Слабые осадки": "Light precipitation",
	"Сильные осадки": "Heavy precipitation",
	"Грозовое ядро": "Storm core",
	"ЛКМ: точка / линия • тянуть точку: изменить • ПКМ: отменить / стереть • [B]: карта": "LMB: point/line • drag point: edit • RMB: cancel/delete • [B]: map",
	"ТУРБУЛЕНТНОСТЬ": "TURBULENCE",
	"⊥ %s %.1f км": "⊥ %s %.1f km",
	"ΔК %s %03d°": "ΔC %s %03d°",

	"СКОРОСТЬ": "AIRSPEED",
	"ВЫСОТА": "ALTITUDE",
	"ВАРИОМЕТР": "VERTICAL SPEED",
	"КОМПАС": "COMPASS",
	"АВИАГОРИЗОНТ": "ATTITUDE",
	"ПРИЁМНИК 1": "RECEIVER 1",
	"ПРИЁМНИК 2": "RECEIVER 2",
	"ПРИЁМНИК %d": "RECEIVER %d",
	"ЧАСЫ": "CLOCK",
	"ТОПЛИВО": "FUEL",
	"ГАЗ": "THROTTLE",
	"ШТУРВАЛ": "YOKE",
	"ТОРМОЗ": "BRAKE",
	"ЦЕНТР [C]": "CENTER [C]",
	"САЛОН [X]": "CABIN [X]",
	"САЛОН": "CABIN",
	"ВКЛЮЧИТЬ ПИТАНИЕ [P]": "POWER ON [P]",
	"ВЫКЛЮЧИТЬ ПИТАНИЕ [P]": "POWER OFF [P]",
	"ЗАПУСТИТЬ ДВИГАТЕЛЬ [M]": "START ENGINE [M]",
	"ОСТАНОВИТЬ ДВИГАТЕЛЬ [M]": "STOP ENGINE [M]",
	"ПОКАЗАТЬ ТРАЕКТОРИЮ [ENTER]": "SHOW FLIGHT TRACK [ENTER]",
	"ТРАЕКТ.: ВКЛ": "TRACK: ON",
	"ТРАЕКТ.: ВЫКЛ": "TRACK: OFF",
	"ТРАЕКТ.: НЕТ": "TRACK: N/A",
	"ТР: ВКЛ": "TR: ON",
	"ТР: ВЫКЛ": "TR: OFF",
	"ТР: НЕТ": "TR: N/A",
	"ГРОЗЫ: ВКЛ": "STORMS: ON",
	"ГРОЗЫ: ВЫКЛ": "STORMS: OFF",
	"ГР: ВКЛ": "ST: ON",
	"ГР: ВЫКЛ": "ST: OFF",
	"W/S: газ  •  стрелки: штурвал  •  Esc: меню": "W/S: throttle  •  arrows: yoke  •  Esc: menu",
	"ДЕНЬ %d • %02d:%02d:%02d": "DAY %d • %02d:%02d:%02d",
	"ПУТЬ %.1f км • %02d:%02d": "TRIP %.1f km • %02d:%02d",
	"СБРОС [T]": "RESET [T]",
	"По земле %.0f км/ч": "Ground %.0f km/h",
	"%.0f км/ч": "%.0f km/h",
	"%+.1f м/с": "%+.1f m/s",
	"РВ %d м": "RA %d m",
	"РВ —": "RA —",
	"ЗЕМ %d м": "GND %d m",
	"ЗЕМ —": "GND —",
	"РВ 100 м": "RA 100 m",
	"УА %+.1f°": "AOA %+.1f°",
	"ОСТ": "REM",
	"РАСХ": "FLOW",
	"Расход %.2f л/мин": "Flow %.2f L/min",
	"%.1f/%.0f л • запас %.0f км": "%.1f/%.0f L • range %.0f km",
	"%03d кГц": "%03d kHz",
	"%.1f Л": "%.1f L",
	"%.1f км  %03d°/%03d°": "%.1f km  %03d°/%03d°",
	"НЕТ СИГНАЛА": "NO SIGNAL",
	"ILS %03d кГц": "ILS %03d kHz",
	"H %.1f м": "H %.1f m",
	"VS %+.2f м/с": "VS %+.2f m/s",
	"VS %+.2f м/с • НУЖНО %+.2f м/с": "VS %+.2f m/s • TARGET %+.2f m/s",
	"V %.1f км/ч": "V %.1f km/h",
	"УГОЛ %.1f°": "ANGLE %.1f°",
	"УГОЛ —": "ANGLE —",
	"ОТКЛ. ПУТИ %+.1f°": "COURSE DEV %+.1f°",
	"ОСЬ %+.0f м": "AXIS %+.0f m",
	"НОС %+.1f°": "NOSE %+.1f°",
	"ДО ВПП %.2f км": "RWY %.2f km",
	"КАСАНИЕ %+.2f км ОТ ТОРЦА": "TOUCHDOWN %+.2f km FROM THR",
	"КАС. %+.2f км": "TD %+.2f km",
	"КАСАНИЕ — НЕТ СНИЖЕНИЯ": "TOUCHDOWN — NOT DESCENDING",
	"КАСАНИЕ — НЕ ПРОГНОЗИРУЕТСЯ": "TOUCHDOWN — NOT PREDICTED",
	"БОЛЬШОЙ ILS [I]": "LARGE ILS [I]",
	"ПИТАНИЕ ВЫКЛЮЧЕНО": "POWER OFF",
	"FPM — НЕТ СНИЖЕНИЯ": "FPM — NOT DESCENDING",
	"ОТКЛ. ПУТИ %+.2f°": "COURSE DEV %+.2f°",
	"ДО ВПП %.3f км": "RWY %.3f km",
	"КАСАНИЕ %+.3f км": "TOUCHDOWN %+.3f km",
	"КАСАНИЕ %+.3f км ОТ ТОРЦА": "TOUCHDOWN %+.3f km FROM THR",
	"БОК %+.0f м": "LAT %+.0f m",
	"I: КАРТА": "I: MAP",
	"СТВОР": "LOCALIZER",
	"ВНЕ СТВОРА": "OFF LOCALIZER",
	"ГЛИСС": "GLIDESLOPE",
	"ВЫСОКО": "HIGH",
	"НИЗКО": "LOW",
	"ВРЕМЯ %d× [⇧Z]": "TIME %d× [⇧Z]",
	"ПЛАНЕР: %s  %s  %.1f%% • износ %.3f%%/мин": "AIRFRAME: %s  %s  %.1f%% • wear %.3f%%/min",
	"НОРМА": "NORMAL",
	"ИЗНОС": "WORN",
	"КРИТИЧЕСКОЕ": "CRITICAL",
	"Деньги": "Money",
	"Сытость": "Hunger",
	"Бодрость": "Energy",
	"Планер": "Airframe",
	"ВЫСОКАЯ СКОРОСТЬ — ИЗБЕГАТЬ РЕЗКИХ МАНЁВРОВ": "HIGH SPEED — AVOID ABRUPT MANEUVERS",
	"ПРЕВЫШЕНА VNE — УМЕНЬШИТЬ СКОРОСТЬ": "VNE EXCEEDED — REDUCE SPEED",
	"ПРЕДУПРЕЖДЕНИЕ: БОЛЬШОЙ УГОЛ АТАКИ": "WARNING: HIGH ANGLE OF ATTACK",
	"СВАЛИВАНИЕ — ОТДАТЬ ШТУРВАЛ ОТ СЕБЯ": "STALL — PUSH THE YOKE FORWARD",
	"БОЛЬШОЙ УГОЛ АТАКИ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ": "HIGH ANGLE OF ATTACK — RETURN TO THE COCKPIT",
	"СВАЛИВАНИЕ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ": "STALL — RETURN TO THE COCKPIT",

	"РАСЧЁТ ПОЛЁТА  ⋮⋮": "FLIGHT CALCULATOR  ⋮⋮",
	"Набор расчёта %d": "Calculation set %d",
	"Развернуть": "Expand",
	"Свернуть": "Collapse",
	"Расстояние": "Distance",
	"Время": "Time",
	"Возд. скорость": "Airspeed",
	"Верт. скорость": "Vertical speed",
	"Высота 1": "Altitude 1",
	"Высота 2": "Altitude 2",
	"Направление пути": "Ground track",
	"Курс носа": "Heading",
	"Ветер откуда": "Wind from",
	"Скорость ветра": "Wind speed",
	"Текущая": "Current",
	"Текущий": "Current",
	"Обратно": "Reverse",
	"Обновить исходную высоту по высоте самолёта": "Use the aircraft's current altitude",
	"Подставить воздушную скорость самолёта": "Use the aircraft's current airspeed",
	"Подставить вертикальную скорость самолёта": "Use the aircraft's current vertical speed",
	"Подставить текущий курс носа самолёта": "Use the aircraft's current heading",
	"ПРИВЯЗАТЬ К ЛИНИИ": "LINK TO LINE",
	"ОТВЯЗАТЬ ОТ ЛИНИИ": "UNLINK FROM LINE",
	"ОТМЕНИТЬ ВЫБОР ЛИНИИ": "CANCEL LINE SELECTION",
	"Расстояние должно быть больше нуля": "Distance must be greater than zero",
	"Расстояние не может быть обнулено: измените время или скорость": "Distance cannot be reset to zero: change time or speed",
	"Для ненулевого расстояния задайте время больше нуля": "Set a time greater than zero for a non-zero distance",
	"Для расчёта времени нужна скорость больше нуля": "Time calculation requires a speed greater than zero",
	"Для расчёта высоты нужна ненулевая длительность": "Altitude calculation requires a non-zero duration",
	"Для этой высоты задайте набор (+) или снижение (−)": "Set a climb (+) or descent (−) for this altitude",
	"Такое время и расстояние недостижимы при заданных ветре и курсе": "This time and distance are impossible with the selected wind and heading",
	"Боковой ветер слишком силён: выбранный путь удержать невозможно": "The crosswind is too strong to maintain the selected track",
	"Ветер не позволяет продвигаться по выбранному пути": "The wind prevents progress along the selected track",
	"Нет движения над землёй: направление пути не определено": "No movement over the ground: track is undefined",
	"Значения слишком велики для расчёта": "Values are too large to calculate",

	"АЭРОПОРТ «%s»": "AIRPORT “%s”",
	"ЛЁТНАЯ СЛУЖБА": "FLIGHT SERVICE",
	"Лётная служба": "Flight service",
	"ПОЧТА": "POST OFFICE",
	"Почта": "Post office",
	"КАФЕ": "CAFE",
	"Кафе": "Cafe",
	"ГОСТИНИЦА": "HOTEL",
	"Гостиница": "Hotel",
	"ЗАПРАВКА": "FUEL STATION",
	"Заправка": "Fuel station",
	"РЕМОНТНЫЙ АНГАР": "REPAIR HANGAR",
	"Ремонтный ангар": "Repair hangar",
	"СЛУЖБА": "SERVICE",
	"На перрон": "To apron",
	"На ВПП": "To runway",
	"В аэропорт": "To airport",
	"В самолёт": "To aircraft",
	"Стрелки: идти": "Arrows: walk",
	"Enter: %s": "Enter: %s",
	"ВПП / %s": "RWY / %s",
	"ВПП / ": "RWY / ",
	"Enter: выйти из здания • Esc: меню": "Enter: leave building • Esc: menu",
	"ЛКМ: переместиться • клик по двери: перейти • стрелки: идти • Enter: действие • Esc: меню": "LMB: move • click door: enter • arrows: walk • Enter: action • Esc: menu",
	"ЛКМ / стрелки: идти • Enter: действие • X: за штурвал • Esc: меню": "LMB / arrows: walk • Enter: action • X: cockpit • Esc: menu",
	"Клик: действие • Enter: выйти • Esc: меню": "Click: action • Enter: leave • Esc: menu",
	"Esc: меню": "Esc: menu",
	"ДАЛЕКИЙ ПОЛЕТ   /   ПОЧТОВАЯ АВИАЦИЯ": "FAR FLIGHT   /   AIRMAIL",
	"Борт 02 / салон": "Aircraft 02 / cabin",
	"Борт 02 • малый грузовой биплан": "Aircraft 02 • light cargo biplane",
	"Грузовой отсек • самолёт на стоянке": "Cargo hold • aircraft parked",
	"Грузовой отсек • самолёт продолжает полёт": "Cargo hold • flight continues",
	"Грузовой отсек • самолёт на стоянке • колесо вниз: отдалить": "Cargo hold • aircraft parked • wheel down: zoom out",
	"Грузовой отсек • самолёт продолжает полёт • колесо вниз: отдалить": "Cargo hold • flight continues • wheel down: zoom out",
	"Вид вниз вдоль пути • полёт продолжается • Esc: меню": "View down along the track • flight continues • Esc: menu",
	"Колесо: масштаб • Enter / Esc: в салон • X: за штурвал": "Wheel: zoom • Enter / Esc: cabin • X: cockpit",
	"СТОЛ": "TABLE",
	"КРОВАТЬ": "BED",
	"В кресло пилота": "Pilot seat",
	"сесть за стол": "sit at table",
	"лечь на кровать": "lie on bed",
	"перейти к заправке": "go to fuel station",
	"Enter: заправить самолёт": "Enter: refuel aircraft",
	"Enter: съесть еду": "Enter: eat food",
	"Enter: встать с кровати": "Enter: get out of bed",
	"Возьмите еду и принесите её к столу": "Take food and bring it to the table",
	"Подойдите к лестнице и нажмите ↓, чтобы заправить самолёт": "Go to the ladder and press ↓ to refuel the aircraft",
	"ЗАПРАВИТЬ": "REFUEL",
	"СЪЕСТЬ": "EAT",
	"УЛОЖИТЬ": "STORE",
	"ВЫБРОСИТЬ": "DISCARD",
	"ЕДА": "FOOD",
	"ПОЧТА → %s": "MAIL → %s",
	"ПОЧТА\n%s": "MAIL\n%s",
	"ПОЧТА — %s": "MAIL — %s",
	"КАНИСТРА • %.1f Л": "FUEL CAN • %.1f L",
	"Еда • восстанавливает 1 деление сытости": "Food • restores 1 hunger segment",
	"Посылка • аэропорт «%s» • оплата %d монет": "Parcel • airport “%s” • reward %d coins",
	"Канистра • %.1f/%d л топлива": "Fuel can • %.1f/%d L",
	"Топливо в баке: %.1f/%.0f л": "Fuel in tank: %.1f/%.0f L",
	"Объём: %.1f л • клик или перетаскивание": "Amount: %.1f L • click or drag",
	"Заправить %.1f л • останется %.1f л • бак %.1f/%.0f л": "Transfer %.1f L • %.1f L left • tank %.1f/%.0f L",
	"Слот пуст": "Empty slot",
	"Нет свободных слотов": "No free slots",
	"Предмет уложен": "Item stored",
	"Предмет уложен в грузовой отсек": "Item stored in cargo hold",
	"Предмет выброшен": "Item discarded",
	"Вы взяли: ": "Picked up: ",
	"Вы взяли: %s": "Picked up: %s",
	"Перед сном освободите руки": "Free your hands before sleeping",
	"Вы легли отдохнуть • каждые 20 минут +1, не выше 2": "You lie down to rest • +1 every 20 minutes, up to 2",
	"Отдых: %d/20 мин • бодрость %d/6 (не выше 2)": "Rest: %d/20 min • energy %d/6 (up to 2)",
	"Вы уже сыты": "You are already full",
	"Поесть можно только за столом в салоне": "You can only eat at the cabin table",

	"ОБСЛУЖИВАНИЕ САМОЛЁТА": "AIRCRAFT SERVICE",
	"Топливо: %.1f / %.0f л": "Fuel: %.1f / %.0f L",
	"Подготовка или смена ВПП: %d монет": "Preparation or runway change: %d coins",
	"ОБНОВИТЬ МЕТЕОСВОДКУ • %s": "UPDATE WEATHER REPORT • %s",
	"ПОДГОТОВИТЬ К ВЫЛЕТУ • ВПП %03d° • %d МОНЕТ": "PREPARE FOR DEPARTURE • RWY %03d° • %d COINS",
	"ПОДГОТОВЛЕНО • ВПП %03d° • БЕСПЛАТНО": "READY • RWY %03d° • FREE",
	"СМЕНИТЬ ВПП НА %03d° • %d МОНЕТ": "CHANGE TO RWY %03d° • %d COINS",
	"СТАТУС: ПОДГОТОВЛЕН К ВЫЛЕТУ С ВПП %03d°": "STATUS: READY FOR DEPARTURE FROM RWY %03d°",
	"СТАТУС: САМОЛЁТ НЕ ПОДГОТОВЛЕН К ВЫЛЕТУ": "STATUS: AIRCRAFT NOT READY FOR DEPARTURE",
	"СТАТИСТИКА ПОЛЁТОВ • %d": "FLIGHT HISTORY • %d",
	"ВЫЙТИ В АЭРОПОРТ [ENTER]": "EXIT TO AIRPORT [ENTER]",
	"Метеосводка обновлена • положение гроз зафиксировано на %02d:%02d": "Weather report updated • storm positions fixed at %02d:%02d",
	"Самолёт уже подготовлен к вылету с ВПП %03d° • оплата не требуется": "Aircraft is already ready for RWY %03d° • no payment required",
	"Самолёт подготовлен к вылету курсом %03d°": "Aircraft prepared for departure on heading %03d°",
	"Самолёт подготовлен к вылету": "Aircraft prepared for departure",
	"Не хватает денег на стоянку и подготовку • выбранная ВПП не изменена": "Not enough money for parking and preparation • selected runway unchanged",
	"Не хватает денег на стоянку и подготовку": "Not enough money for parking and preparation",
	"Готов к взлёту с аэродрома «%s»": "Ready for departure from “%s”",
	"требуется подготовка к следующему вылету": "preparation required for the next departure",
	"подготовка к вылету сохранена": "departure preparation retained",

	"ИСТОРИЯ ПОЛЁТОВ • НОВЫЕ СВЕРХУ": "FLIGHT HISTORY • NEWEST FIRST",
	"СТАТИСТИКА ПОЛЁТОВ": "FLIGHT HISTORY",
	"%s → %s • ВСЕГО ПОЛЁТОВ: %d • РЕКОРД СВЕРХУ": "%s → %s • TOTAL FLIGHTS: %d • BEST FIRST",
	"Завершённых полётов пока нет": "No completed flights yet",
	" • всего полётов: %d • Enter: рекорды": " • total flights: %d • Enter: records",
	"РЕКОРД • ": "RECORD • ",
	"%.1f км • %s • %s → %s": "%.1f km • %s • %s → %s",
	"день %d %02d:%02d:%02d": "day %d %02d:%02d:%02d",
	"Колесо / ↑↓: прокрутка • Enter: открыть рекорды маршрута • кнопка «Назад»: вернуться": "Wheel / ↑↓: scroll • Enter: route records • Back button: return",

	"%s • %d монет": "%s • %d coins",
	"СДАТЬ ПОСЫЛКУ • %d монет": "DELIVER PARCEL • %d coins",
	"%s • маршрут %.0f км • %d монет%s": "%s • route %.0f km • %d coins%s",
	" • надбавка +%d%%": " • bonus +%d%%",
	" • оплачено %d монет": " • paid %d coins",
	"Самолёт подготовлен к вылету курсом %03d° • оплачено %d монет": "Aircraft prepared for departure on heading %03d° • paid %d coins",
	"КУПИТЬ ЕДУ С СОБОЙ • %d монет%s": "BUY TAKEAWAY FOOD • %d coins%s",
	"ПОЕСТЬ В КАФЕ • %d монет%s": "EAT AT CAFE • %d coins%s",
	"ОТДОХНУТЬ 20 МИНУТ • %d монет%s": "REST 20 MINUTES • %d coins%s",
	"КУПИТЬ ПУСТУЮ КАНИСТРУ • %d": "BUY EMPTY FUEL CAN • %d",
	"КУПИТЬ %.1f Л • %d монет%s": "BUY %.1f L • %d coins%s",
	"ПРОДАТЬ КАНИСТРУ И ТОПЛИВО": "SELL FUEL CAN AND FUEL",
	"Точное состояние: %.1f/100 • %.1f мон./ед.": "Exact condition: %.1f/100 • %.1f coins/point",
	"РЕМОНТ ДО 100 • %d монет%s": "REPAIR TO 100 • %d coins%s",
	"дешево": "cheap",
	"средне": "average",
	"дорого": "expensive",
	"топливо": "fuel",
	"кафе": "cafe",
	"гостиница": "hotel",
	"ремонт": "repair",
	"почта": "post office",
	"лётная служба": "flight service",
	"Не хватает денег или руки заняты": "Not enough money or your hands are occupied",
	"Не хватает денег": "Not enough money",
	"Вы не голодны": "You are not hungry",
	"Еда куплена — отнесите её в самолёт": "Food purchased — take it to the aircraft",
	"Еда съедена • сытость %d/%d": "Meal eaten • hunger %d/%d",
	"Сытость %d/6": "Hunger %d/6",
	"Посылка получена — отнесите её в самолёт": "Parcel accepted — take it to the aircraft",
	"Сначала освободите руки": "Free your hands first",
	"Доставлено: +%d монет": "Delivered: +%d coins",
	"Отдых 20 минут • бодрость %d/6": "Rested 20 minutes • energy %d/6",
	"Канистра куплена": "Fuel can purchased",
	"Возьмите канистру или проверьте деньги": "Take a fuel can or check your money",
	"Возьмите канистру": "Take a fuel can",
	"Выбрано %.1f л": "Selected %.1f L",
	"Куплено %.1f л топлива": "Purchased %.1f L of fuel",
	"Получено %d монет": "Received %d coins",
	"Нужна канистра с топливом или бак уже полон": "A fuel can is required or the tank is already full",
	"Перелито %.1f л • в баке %.1f/%.0f л": "Transferred %.1f L • tank %.1f/%.0f L",
	"Не хватает денег на ремонт": "Not enough money for repairs",
	"Самолёт уже полностью исправен": "Aircraft is already fully repaired",
	"Отремонтировано %.1f • состояние %.1f/100": "Repaired %.1f • condition %.1f/100",

	"Питание включено": "Power on",
	"Питание выключено": "Power off",
	"Питание и двигатель выключены": "Power and engine off",
	"Двигатель запущен": "Engine started",
	"Двигатель остановлен": "Engine stopped",
	"Двигатель остановлен • %s": "Engine stopped • %s",
	"Запуск двигателя невозможен: включите питание": "Cannot start engine: turn on electrical power",
	"Запуск и взлёт запрещены: оплатите подготовку и выберите полосу в лётной службе": "Engine start and departure prohibited: pay for preparation and select a runway at flight service",
	"Взлёт выполнен": "Takeoff complete",
	"Уход на второй круг": "Go-around",
	"Касание": "Touchdown",
	"Жёсткое касание": "Hard touchdown",
	"%s ВПП «%s» на %.1f км/ч — газ 0%%, удерживайте S для торможения": "%s RWY “%s” at %.1f km/h — throttle 0%%, hold S to brake",
	"Успешная посадка": "Successful landing",
	"Успешная посадка в аэропорту «%s»": "Successful landing at “%s”",
	"Выход доступен после остановки на ВПП": "Exit is available after stopping on the runway",
	"Счётчик пройденного пути сброшен": "Trip counter reset",
	"Самолёт заправлен: %.0f л": "Aircraft fuelled: %.0f L",
	"Самолёт покинул район полётов": "Aircraft left the flight area",
	"Выехали за пределы ВПП «%s»: боковое отклонение %.1f м": "Left RWY “%s”: lateral deviation %.1f m",
	"Выехали за торец ВПП «%s»": "Ran beyond the end of RWY “%s”",
	"Выкатились за пределы ВПП «%s»: скорость %.1f км/ч": "Ran off RWY “%s” at %.1f km/h",
	"Касание до ВПП «%s»: %.0f м": "Touchdown before RWY “%s”: %.0f m",
	"Касание после конца ВПП «%s»: %.0f м": "Touchdown beyond RWY “%s”: %.0f m",
	"Касание вне ВПП «%s»: боковое отклонение %.0f м": "Touchdown outside RWY “%s”: lateral deviation %.0f m",
	"жёсткое касание %+.2f м/с": "hard touchdown %+.2f m/s",
	"Посадка не засчитана на ВПП «%s»": "Landing not registered on RWY “%s”",
	"Посадка не удалась: %s": "Landing failed: %s",
	"Столкновение с рельефом: высота земли %.0f м": "Terrain collision: ground elevation %.0f m",
	"Разрушение планера: скорость %.1f км/ч превысила предел прочности": "Airframe failure: speed %.1f km/h exceeded structural limit",
	"Разрушение планера из-за превышения допустимой скорости (%.1f км/ч)": "Airframe failure due to excessive speed (%.1f km/h)",
	"Самолёт разрушился в воздухе: конструкция полностью изношена": "Aircraft broke up in flight: airframe completely worn out",
	"%s: %03d° %.0f км/ч": "%s: %03d° %.0f km/h",
	"%s: ветер %03d° %.0f км/ч • %s": "%s: wind %03d° %.0f km/h • %s",
	"гроз нет": "no storms",
	"гроза %.0f км": "storm %.0f km",
	"Вы умерли от голода": "You died of hunger",
	"Вы умерли от усталости": "You died of exhaustion",
	"ПОЛЁТ ЗАВЕРШЁН — КРУШЕНИЕ": "FLIGHT ENDED — CRASH",
	"ИГРА ОКОНЧЕНА": "GAME OVER",
	"Самолёт находился в сваливании.\n": "The aircraft was stalled.\n",
	"Enter: траектория полёта • Esc: меню": "Enter: flight track • Esc: menu",
	"Северный": "Northern",
	"Озёрный": "Lakeside",
	"Речной": "Riverside",
	"Степной": "Steppe",
	"Туманный": "Misty",
	"Каменный": "Stonefield",
	"Западный": "Western",
	"Дальний": "Farfield",
	"км": "km",
	"км/ч": "km/h",
	"м": "m",
	"м/с": "m/s",
	"мин": "min",
	"Л": "L",
	"корневой снимок не является словарём": "root snapshot is not a dictionary",
	"%s: ожидался массив": "%s: expected an array",
	"%s: повреждена линия": "%s: malformed line",
	"некорректная история полётов": "invalid flight history",
	"некорректное состояние метеосводки": "invalid weather report state",
	"некорректное состояние расчёта полёта": "invalid flight calculator state",
	"некорректный аэродром подготовки к вылету": "invalid departure-preparation airport",
	"некорректный текущий аэродром самолёта": "invalid current aircraft airport",
	"одно из полей игрового состояния имеет несовместимый тип или значение": "a game-state field has an incompatible type or value",
}

static func initialize(path: String = DEFAULT_SETTINGS_PATH) -> void:
	settings_path = path
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		var saved := str(config.get_value("interface", "language", RUSSIAN))
		language = saved if saved in [RUSSIAN, ENGLISH] else RUSSIAN
	else:
		language = RUSSIAN
	_cache.clear()

static func set_language(value: String, persist := true) -> void:
	language = value if value in [RUSSIAN, ENGLISH] else RUSSIAN
	_cache.clear()
	if not persist:
		return
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value("interface", "language", language)
	config.save(settings_path)

static func is_english() -> bool:
	return language == ENGLISH

static func text(source_value: Variant) -> String:
	var source := str(source_value)
	if language != ENGLISH or source.is_empty():
		return source
	if _cache.has(source):
		return _cache[source]
	_prepare_rules()
	var translated: String = EN.get(source, "")
	if translated.is_empty():
		for rule in _dynamic_rules:
			var captures := _match_template(source, rule.literals)
			if not captures.is_empty() or int(rule.placeholder_count) == 0:
				translated = _fill_template(String(rule.target), captures)
				break
	if translated.is_empty():
		translated = source
	for fragment in ["Северный", "Озёрный", "Речной", "Степной", "Туманный", "Каменный", "Западный", "Дальний", "лётная служба", "почта", "топливо", "кафе", "гостиница", "ремонт", "дешево", "средне", "дорого"]:
		translated = translated.replace(fragment, String(EN[fragment]))
	if _cache.size() > 4096:
		_cache.clear()
	_cache[source] = translated
	return translated

static func draw_string(canvas: CanvasItem, font: Font, position: Vector2, value: Variant,
		alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font_size := 16,
		modulate := Color.WHITE) -> void:
	canvas.draw_string(font, position, text(value), alignment, width, font_size, modulate)

static func _prepare_rules() -> void:
	if _rules_ready:
		return
	_rules_ready = true
	for source in EN:
		if not String(source).contains("%"):
			continue
		var parsed := _template_literals(String(source))
		_dynamic_rules.append({
			"literals": parsed.literals,
			"placeholder_count": parsed.placeholder_count,
			"target": EN[source],
		})
	_dynamic_rules.sort_custom(func(a: Dictionary, b: Dictionary):
		return _literal_weight(a.literals) > _literal_weight(b.literals)
	)

static func _template_literals(template: String) -> Dictionary:
	var literals: Array[String] = [""]
	var placeholders := 0
	var index := 0
	while index < template.length():
		if template[index] != "%":
			literals[-1] += template[index]
			index += 1
			continue
		if index + 1 < template.length() and template[index + 1] == "%":
			literals[-1] += "%"
			index += 2
			continue
		var end := index + 1
		while end < template.length() and template[end] not in ["s", "d", "f"]:
			end += 1
		if end >= template.length():
			literals[-1] += "%"
			index += 1
			continue
		placeholders += 1
		literals.append("")
		index = end + 1
	return {"literals": literals, "placeholder_count": placeholders}

static func _match_template(value: String, literals: Array) -> Array[String]:
	if literals.size() <= 1:
		return []
	var captures: Array[String] = []
	var cursor := 0
	var first := String(literals[0])
	if not value.begins_with(first):
		return []
	cursor = first.length()
	for index in range(1, literals.size()):
		var next_literal := String(literals[index])
		if index == literals.size() - 1 and next_literal.is_empty():
			captures.append(value.substr(cursor))
			cursor = value.length()
			continue
		var next_position := value.find(next_literal, cursor)
		if next_position < 0:
			return []
		captures.append(value.substr(cursor, next_position - cursor))
		cursor = next_position + next_literal.length()
	if cursor != value.length():
		return []
	return captures

static func _fill_template(template: String, captures: Array[String]) -> String:
	var result := ""
	var capture_index := 0
	var index := 0
	while index < template.length():
		if template[index] != "%":
			result += template[index]
			index += 1
			continue
		if index + 1 < template.length() and template[index + 1] == "%":
			result += "%"
			index += 2
			continue
		var end := index + 1
		while end < template.length() and template[end] not in ["s", "d", "f"]:
			end += 1
		if end >= template.length() or capture_index >= captures.size():
			result += "%"
			index += 1
			continue
		result += text(captures[capture_index])
		capture_index += 1
		index = end + 1
	return result

static func _literal_weight(literals: Array) -> int:
	var weight := 0
	for literal in literals:
		weight += String(literal).length()
	return weight
