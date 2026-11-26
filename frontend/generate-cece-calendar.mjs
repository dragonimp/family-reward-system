// Regenerate parent-app/shared/CeceCalendar.json with lunar-typescript 1.8.7.
// Run from the repository root: node frontend/generate-cece-calendar.mjs
import { writeFileSync } from 'node:fs';
import { URL } from 'node:url';
import { LunarYear, Solar } from 'lunar-typescript';

const boundaries = ['小寒', '立春', '惊蛰', '清明', '立夏', '芒种', '小暑', '立秋', '白露', '寒露', '立冬', '大雪'];
const calendar = { terms: {}, months: {} };

// The surrounding years supply both adjacent jie boundaries and conversions
// for lunar dates near either end of the app's 1901–2099 input range.
for (let year = 1900; year <= 2100; year++) {
  const table = Solar.fromYmd(year, 6, 1).getLunar().getJieQiTable();
  calendar.terms[year] = boundaries.map(name => table[name].toYmdHms());
  calendar.months[year] = LunarYear.fromYear(year).getMonths()
    .filter(month => month.getYear() === year)
    .map(month => [
      month.getMonth(),
      month.getDayCount(),
      Solar.fromJulianDay(month.getFirstJulianDay()).toYmd(),
    ]);
}

writeFileSync(new URL('../parent-app/shared/CeceCalendar.json', import.meta.url), JSON.stringify(calendar) + '\n');
