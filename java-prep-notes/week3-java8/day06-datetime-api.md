# Day 6: Date/Time API

The modern, immutable, thread-safe java.time package that replaced Date and Calendar.

---

## Quick Definition

`java.time` (JSR-310, Java 8) is the modern date/time API. Its core types are **immutable** and **thread-safe**, with a clean separation between human time (`LocalDate`), machine time (`Instant`), and zoned time (`ZonedDateTime`).

| Class | Represents | Example |
|:------|:-----------|:--------|
| `LocalDate` | date, no time/zone | `2026-06-15` |
| `LocalTime` | time, no date/zone | `14:30:00` |
| `LocalDateTime` | date + time, no zone | `2026-06-15T14:30` |
| `Instant` | a point on the timeline (UTC) | `2026-06-15T12:30:00Z` |
| `ZonedDateTime` | date + time + zone | `2026-06-15T14:30+01:00[Europe/London]` |
| `OffsetDateTime` | date + time + UTC offset | `2026-06-15T14:30+02:00` |
| `Duration` | time-based amount | `PT2H30M` (2h 30m) |
| `Period` | date-based amount | `P1Y2M3D` (1y 2m 3d) |

---

## Why the legacy API was broken

```java
// java.util.Date / Calendar problems:
// 1. Mutable -> not thread-safe, defensive copies needed
// 2. Months are 0-based (January = 0)  <-- endless bugs
// 3. Year is offset from 1900 in Date(int, int, int)
// 4. SimpleDateFormat is NOT thread-safe (shared instance = corruption)
// 5. No clean concept of "date only" or "time only"
// 6. Confusing API, poor zone handling

Calendar cal = Calendar.getInstance();
cal.set(2026, 5, 15);   // month 5 == JUNE, not May!  Off-by-one trap
```

`java.time` fixes all of these: immutable, 1-based months via the `Month` enum, thread-safe formatters, and dedicated types.

---

## Core classes

```java
// LocalDate - date only
LocalDate date = LocalDate.of(2026, 6, 15);    // 2026-06-15 (month is 1-based!)
LocalDate viaEnum = LocalDate.of(2026, Month.JUNE, 15);

// LocalTime - time only
LocalTime time = LocalTime.of(14, 30, 15);     // 14:30:15

// LocalDateTime - date + time, NO zone
LocalDateTime dt = LocalDateTime.of(2026, 6, 15, 14, 30);

// Instant - a machine timestamp on the UTC timeline
Instant instant = Instant.ofEpochSecond(1_700_000_000);

// ZonedDateTime - date + time + zone (handles DST)
ZonedDateTime zdt = ZonedDateTime.of(dt, ZoneId.of("Europe/London"));

// OffsetDateTime - date + time + fixed offset (no zone rules / DST)
OffsetDateTime odt = OffsetDateTime.of(dt, ZoneOffset.ofHours(2));
```

> Use `LocalDateTime` for "wall clock" values with no zone, `Instant` for timestamps/logging, `ZonedDateTime` when DST and named zones matter, and `OffsetDateTime` for storage/APIs where you want a fixed offset.

---

## Common operations

All mutators return a **new** instance (immutability).

```java
LocalDate date = LocalDate.of(2026, 6, 15);

LocalDate tomorrow = date.plusDays(1);          // 2026-06-16
LocalDate lastMonth = date.minusMonths(1);      // 2026-05-15
LocalDate nextYear = date.plusYears(1);         // 2027-06-15

// date is UNCHANGED - the original is immutable
System.out.println(date);                       // still 2026-06-15

// Comparisons
boolean before = date.isBefore(tomorrow);       // true
boolean after = date.isAfter(lastMonth);        // true

// Field access
int year = date.getYear();                      // 2026
Month month = date.getMonth();                  // JUNE
DayOfWeek dow = date.getDayOfWeek();            // MONDAY
boolean leap = date.isLeapYear();               // false
```

---

## Duration vs Period

This distinction is a favourite interview question.

| | `Duration` | `Period` |
|:--|:-----------|:---------|
| Measures | **time** (seconds/nanos) | **dates** (years/months/days) |
| Use with | `Instant`, `LocalTime`, `LocalDateTime` | `LocalDate` |
| Format | `PT...` (e.g. `PT2H30M`) | `P...` (e.g. `P1M`) |
| DST-aware | based on exact seconds | based on calendar |

```java
// Duration - machine time
Duration twoHours = Duration.ofHours(2);
Duration gap = Duration.between(
        LocalTime.of(9, 0), LocalTime.of(17, 30));
System.out.println(gap);             // PT8H30M
System.out.println(gap.toMinutes()); // 510

// Period - calendar amount
Period p = Period.between(
        LocalDate.of(2026, 1, 15), LocalDate.of(2027, 3, 20));
System.out.println(p);               // P1Y2M5D
System.out.println(p.getMonths());   // 2  (the months COMPONENT, not total)
```

> **Gotcha:** `period.getMonths()` returns only the months *component* (here 2), not the total months across the whole period. For totals use `ChronoUnit`.

---

## ChronoUnit - measuring totals

```java
LocalDate start = LocalDate.of(2026, 1, 1);
LocalDate end = LocalDate.of(2026, 6, 15);

long days = ChronoUnit.DAYS.between(start, end);     // 165
long months = ChronoUnit.MONTHS.between(start, end); // 5  (total whole months)
long weeks = ChronoUnit.WEEKS.between(start, end);   // 23

// until() does the same thing
long daysUntil = start.until(end, ChronoUnit.DAYS);  // 165
```

---

## DateTimeFormatter

Unlike `SimpleDateFormat`, `DateTimeFormatter` is **immutable and thread-safe** - share a single static instance.

```java
LocalDateTime dt = LocalDateTime.of(2026, 6, 15, 14, 30, 45);

// Predefined
String iso = dt.format(DateTimeFormatter.ISO_LOCAL_DATE_TIME); // 2026-06-15T14:30:45

// Custom pattern
DateTimeFormatter fmt = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm");
String formatted = dt.format(fmt);                             // 15/06/2026 14:30

// Localized
DateTimeFormatter human = DateTimeFormatter.ofPattern("EEEE, MMM d yyyy", Locale.US);
System.out.println(dt.format(human));                          // Monday, Jun 15 2026

// Parsing (note: parse is a static method on the type)
LocalDate parsed = LocalDate.parse("2026-06-15");              // ISO by default
LocalDate custom = LocalDate.parse("15/06/2026",
        DateTimeFormatter.ofPattern("dd/MM/yyyy"));
```

> Pattern letters: `y`=year, `M`=month, `d`=day, `H`=hour(0-23), `h`=hour(1-12), `m`=minute, `s`=second, `E`=day-of-week, `a`=AM/PM. Case matters: `mm` (minutes) vs `MM` (months) is a classic bug.

---

## Time zones & ZoneId

```java
ZoneId london = ZoneId.of("Europe/London");
ZoneId tokyo = ZoneId.of("Asia/Tokyo");

LocalDateTime meeting = LocalDateTime.of(2026, 6, 15, 9, 0);
ZonedDateTime londonTime = meeting.atZone(london);

// Convert to another zone - same instant, different wall clock
ZonedDateTime tokyoTime = londonTime.withZoneSameInstant(tokyo);
System.out.println(londonTime);  // 2026-06-15T09:00+01:00[Europe/London]
System.out.println(tokyoTime);   // 2026-06-15T17:00+09:00[Asia/Tokyo]

ZoneId systemZone = ZoneId.systemDefault();
```

---

## TemporalAdjusters - relative dates

```java
LocalDate date = LocalDate.of(2026, 6, 15);

LocalDate firstOfMonth = date.with(TemporalAdjusters.firstDayOfMonth());     // 2026-06-01
LocalDate lastOfMonth = date.with(TemporalAdjusters.lastDayOfMonth());       // 2026-06-30
LocalDate nextMonday = date.with(TemporalAdjusters.next(DayOfWeek.MONDAY));  // 2026-06-22
LocalDate firstFriday = date.with(
        TemporalAdjusters.firstInMonth(DayOfWeek.FRIDAY));                   // 2026-06-05
```

---

## Conversions: legacy <-> java.time

```java
// java.util.Date -> Instant -> LocalDateTime
Date legacy = new Date();
Instant instant = legacy.toInstant();
LocalDateTime ldt = LocalDateTime.ofInstant(instant, ZoneId.systemDefault());

// java.time -> java.util.Date
Date back = Date.from(ldt.atZone(ZoneId.systemDefault()).toInstant());

// Calendar -> Instant
Calendar cal = Calendar.getInstance();
Instant fromCal = cal.toInstant();

// SQL
java.sql.Date sqlDate = java.sql.Date.valueOf(LocalDate.of(2026, 6, 15));
LocalDate fromSql = sqlDate.toLocalDate();
```

---

## Immutability & thread-safety

```java
LocalDate date = LocalDate.of(2026, 6, 15);
date.plusDays(10);                  // RESULT IGNORED - common bug!
System.out.println(date);           // still 2026-06-15

LocalDate later = date.plusDays(10); // must capture the returned value
```

Because all `java.time` types are immutable, they are inherently thread-safe and can be freely shared and cached (including `DateTimeFormatter`).

---

## Interview Questions

### Q1: Why was `java.time` introduced over `Date`/`Calendar`?

The legacy classes are mutable (not thread-safe), have 0-based months and 1900-offset years, `SimpleDateFormat` is not thread-safe, and there is no clean date-only/time-only concept. `java.time` is immutable, thread-safe, type-safe, and has a much clearer API.

### Q2: Difference between `Duration` and `Period`?

`Duration` is time-based (seconds/nanos), used with `Instant`/`LocalTime`/`LocalDateTime`. `Period` is date-based (years/months/days), used with `LocalDate`. `Period` respects calendar boundaries; `Duration` is exact elapsed seconds.

### Q3: Difference between `LocalDateTime`, `ZonedDateTime`, `OffsetDateTime`, and `Instant`?

`LocalDateTime` has no zone (wall clock). `Instant` is a point on the UTC timeline (machine time). `OffsetDateTime` adds a fixed UTC offset but no zone rules. `ZonedDateTime` adds a full time zone, including DST rules.

### Q4: Are `java.time` classes thread-safe?

Yes - all core types are immutable, so they are inherently thread-safe and can be shared across threads, including `DateTimeFormatter` (unlike `SimpleDateFormat`).

### Q5: `period.getMonths()` vs `ChronoUnit.MONTHS.between()`?

`getMonths()` returns only the months *component* of a `Period` (e.g. 2 in `P1Y2M5D`). `ChronoUnit.MONTHS.between()` returns the *total* whole months between two dates. Confusing them is a common bug.

### Q6: Why is `SimpleDateFormat` dangerous and what replaces it?

`SimpleDateFormat` is mutable and not thread-safe; a shared instance under concurrency corrupts output or throws. `DateTimeFormatter` is immutable and thread-safe and should replace it.

### Q7: How do you convert between `Date` and `java.time`?

`date.toInstant()` then `LocalDateTime.ofInstant(instant, zone)`. Reverse via `Date.from(zdt.toInstant())`. For SQL use `java.sql.Date.valueOf(localDate)` / `sqlDate.toLocalDate()`.

### Q8: What's the difference between `mm` and `MM` in a pattern?

`mm` is minutes, `MM` is months. Mixing them up (e.g. `yyyy-mm-dd`) silently produces wrong output. Likewise `HH` (0-23) vs `hh` (1-12 with `a`).

### Q9: How do you convert a time to another zone keeping the same instant?

`zonedDateTime.withZoneSameInstant(otherZone)` keeps the same point in time and recomputes the wall-clock. `withZoneSameLocal` keeps the wall-clock and changes the instant.

### Q10: What does `TemporalAdjusters` give you?

Reusable, named date adjustments like `firstDayOfMonth`, `lastDayOfMonth`, `next(DayOfWeek)`, `firstInMonth(...)`, applied via `date.with(adjuster)` - far cleaner than manual arithmetic.

---

## Practice Code

📁 `java-prep-practice/com/prep/week3_java8/day06_datetime/DateTimeDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week3_java8/day06_datetime/DateTimeDemo.java
java -cp java-prep-practice com.prep.week3_java8.day06_datetime.DateTimeDemo
```

---

## Checklist

- [ ] I can explain why `Date`/`Calendar` were replaced
- [ ] I know LocalDate / LocalTime / LocalDateTime / Instant / ZonedDateTime / OffsetDateTime
- [ ] I understand `Duration` vs `Period`
- [ ] I can use `ChronoUnit` and `until` for totals
- [ ] I know `DateTimeFormatter` is thread-safe (unlike SimpleDateFormat)
- [ ] I can build custom patterns and parse strings
- [ ] I can convert between zones with `withZoneSameInstant`
- [ ] I understand that java.time types are immutable
- [ ] I can use `TemporalAdjusters`
- [ ] I can convert between legacy `Date` and `java.time`

---

[← Day 5: Optional](day05-optional.md) | [Next: Day 1 - Generics →](../week4-advanced/day01-generics.md)
