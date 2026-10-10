"""يولّد مقاطع التنبيه الصوتي لكل تركيبة من الأمراض المزمنة (٢^٦ = ٦٤ مقطعاً) بصوت زارية.
الترقيم: bit0 ضغط الدم، bit1 السكري، bit2 القلب، bit3 الربو، bit4 الصرع، bit5 الحساسية — يطابق ChronicCondition في التطبيق.
النطق: «حَرِجَةٍ» لا تقع قبل وقف (تتبعها «الآنَ») حتى لا تُنطق «حرج»، و«بِالإِسْعَافِ» تتبعها «فَوْرًا» حتى لا تُمدّ ياءً.
"""
import asyncio, os, sys
import edge_tts

OUT = sys.argv[1]
VOICE = "ar-SA-ZariyahNeural"
CONDITIONS = [
    "ارْتِفَاعِ ضَغْطِ الدَّمِ",
    "السُّكَّرِيِّ",
    "أَمْرَاضِ القَلْبِ",
    "الرَّبْوِ",
    "الصَّرَعِ",
    "الحَسَاسِيَّةِ الشَّدِيدَةِ",
]
HEAD = "تَنْبِيهُ طَوَارِئ. صَاحِبُ هَذَا الجِهَازِ فِي حَالَةٍ صِحِّيَّةٍ حَرِجَةٍ الآنَ، "
TAIL = "يُرْجَى الاتِّصَالُ بِالإِسْعَافِ فَوْرًا وَتَقْدِيمُ المُسَاعَدَةِ لَهُ."


def text(mask):
    items = [c for i, c in enumerate(CONDITIONS) if mask >> i & 1]
    if not items:
        return HEAD + TAIL
    first = items[0]
    prep = "مِنَ " if first.startswith("ال") else ("مِنِ " if first.startswith("ارْ") else "مِنْ ")
    listing = prep + "، وَ".join(items)
    return HEAD + "وَيُعَانِي " + listing + " لِذَا " + TAIL


async def one(mask):
    path = os.path.join(OUT, f"alert_{mask}.mp3")
    if os.path.exists(path) and os.path.getsize(path) > 10000:
        return True
    for attempt in range(6):
        try:
            await edge_tts.Communicate(text(mask), VOICE, rate="-5%").save(path)
            if os.path.getsize(path) > 10000:
                return True
        except Exception:
            pass
        await asyncio.sleep(2 + attempt * 2)
    return False


async def main():
    os.makedirs(OUT, exist_ok=True)
    failed = [m for m in range(64) if not await one(m)]
    print("failed:", failed)
    with open(os.path.join(OUT, "..", "AlertVoice_texts.txt"), "w", encoding="utf-8") as f:
        for m in range(64):
            f.write(f"{m}\t{text(m)}\n")

asyncio.run(main())
