# NYC Supplier Schedule — Mon 9/14 & Tue 9/15

Windows: **Monday 11:30 AM – 12:45 PM** · **Tuesday 8:00 AM – 1:30 PM**  
Priority: (1) hard timing constraints · (2) linear walking (south → north), minimize zigzags

---

## Monday, September 14 — Chelsea (18th → 20th)

| Time | Supplier | Location | Notes |
|------|----------|----------|-------|
| 11:30 AM – 12:00 PM | **Triangle** | Eichholtz Manhattan, 155 W 18th St | Only fit in-window: they need Mon 10–12 (Tue 2–4 is outside our Tue window) |
| 12:00 PM – 12:10 PM | *Walk* | ~2 blocks north | |
| 12:10 PM – 12:40 PM | **Lichtenberg** | 37 West 20th Street, 5th Floor | Adjacent to Triangle; no timing restriction |
| 12:40 PM – 12:45 PM | Buffer / end | | |

**Path:** 18th St → 20th St (straight, ~2 blocks)

### Monday conflict (not scheduled)

| Supplier | Why deferred |
|----------|----------------|
| **J. Queen** | Available Mon 11:00 AM or after 2:00 PM, but showroom is **38 W 39th St** — ~21 blocks from Triangle. Cannot walk both inside 11:30–12:45. Triangle cannot move (no in-window alternative). Book J. Queen separately (e.g. Mon after 2:00 outside this window, or confirm Tue). |
| **PHF** | Mon 4:00–5:00 PM only — outside window |
| **bedsure** | Anytime Mon, no showroom — optional café add-on if you extend past 12:45 |
| **Flyingstar** | Skip (low potential / no meeting needed) |

---

## Tuesday, September 15 — Flatiron → NoMad → Midtown

Hard pins: **KKP 9:00–10:00** · **nuLOOM 10:30–12:00** · **Home City 11:00** · **Twopages morning** · **amrapur anytime except 10:00–11:00**

| Time | Supplier | Location | Notes |
|------|----------|----------|-------|
| 8:00 AM – 8:30 AM | **Hangzhou Loutu (Twopages)** | Bourke St Bakery, 15 E 28th St | Tue morning only; no showroom |
| 8:30 AM – 9:00 AM | **Wells** | Bourke St Bakery, 15 E 28th St | No restrictions / no showroom — stack at same café |
| 9:00 AM – 9:10 AM | *Walk north* | ~5 blocks to 33rd | |
| 9:10 AM – 9:40 AM | **KKP** | **34 West 33rd Street, Suite 1009** | Must be Tue 9:00–10:00 *(address corrected — was wrongly listed as 230 5th)* |
| 9:40 AM – 9:50 AM | *Walk south* | ~4 blocks to 29th | **Only forced backtrack:** nuLOOM/Home City are south of KKP and pinned after 10:30 / at 11:00 |
| 9:50 AM – 10:20 AM | **Alok** | Coffee shop near 29th St | Fills gap before nuLOOM window opens |
| 10:20 AM – 10:30 AM | *Walk* | to nuLOOM | |
| 10:30 AM – 10:55 AM | **nuLOOM** | 134 West 29th Street | Available 10:30 AM – 12:00 PM; no showroom (office) |
| 10:55 AM – 11:00 AM | *Walk east* | ~1.5 blocks to 5th Ave | |
| 11:00 AM – 11:30 AM | **Home City** | 267 5th Ave, Lower Level, Suite 101 | Requested Tue 11:00 AM |
| 11:30 AM – 11:40 AM | *Walk south* | ~2 blocks to 27th / 5th | Short hop (same corridor) |
| 11:40 AM – 12:10 PM | **amrapur** | **230 5th Ave, Suite 1015** | Avoids their Tue 10:00–11:00 blackout *(address corrected)* |
| 12:10 PM – 12:40 PM | **Evergrace** *(or I Enjoy)* | 230 5th Ave, Rm #1518 *(or Suite 210)* | Same building as amrapur — zero walk; Evergrace OK any time ≠ 3:30–4:30 |
| 12:40 PM – 12:50 PM | *Walk* | stay near 27th–28th | |
| 12:50 PM – 1:20 PM | **Utopia** | Near 28th St / 5th Ave (TBD café or lobby) | Closes the day without another uptown leg |
| 1:20 PM – 1:30 PM | Buffer / end | | |

**Path summary:** 28th (café) → **north** to 33rd (KKP) → **south** to 29th (Alok / nuLOOM / Home City) → **south** 2 blocks to 230 5th (amrapur / Evergrace) → stay local for Utopia.

### Why the one zigzag exists

KKP is locked to **9:00–10:00 at 33rd St**, while nuLOOM (**10:30–12**) and Home City (**11:00**) are at **29th**. Timing wins over geography, so the only backtrack is 33rd → 29th after KKP. Everything else stays on a single north-then-settle corridor.

---

## Address corrections vs prior draft

| Supplier | Prior (incorrect) | Correct |
|----------|-------------------|---------|
| KKP | 230 5th Ave, Suite 1015 | **34 West 33rd Street, Suite 1009** |
| amrapur | 385 5th Ave, 4th Floor | **230 5th Ave, Suite 1015** |
| Lichtenberg | 34 West 33rd Street, Suite 1009 | **37 West 20th Street, 5th Floor** (moved to Monday next to Triangle) |
| J. Queen | 37 West 20th Street | **38 W 39th St, 2nd Floor** (not walkable with Triangle in Mon window) |

---

## Overflow / optional (if time opens up)

| Supplier | Constraint | Suggested slot |
|----------|------------|----------------|
| **southpoint** | None listed | Tue after Home City going **north** instead of amrapur block — only if you drop Evergrace/Utopia south and accept skipping same-building efficiency at 230 5th |
| **J. Queen** | Mon 11:00 or after 2:00 | Separate booking; do not pair with Triangle on foot |
| **I Enjoy** | Mon windows listed; showroom at 230 5th Suite 210 | Swap with Evergrace Tue 12:10–12:40 if preferred |
| **Nanfeng** | Before 2:30 PM; no showroom | Optional café insert Tue before 1:30 |
| **bedsure** | Anytime Monday; no showroom | Optional Mon café if window extends |

---

## Walking map (street spine)

```
Mon:  18th (Triangle) ──► 20th (Lichtenberg)

Tue:  28th (Twopages/Wells)
        │
        ▼ north
      33rd (KKP)
        │
        ▼ south (forced)
      29th (Alok → nuLOOM → Home City)
        │
        ▼ south 2 blk
      27th / 230 5th (amrapur → Evergrace) → Utopia nearby
```
