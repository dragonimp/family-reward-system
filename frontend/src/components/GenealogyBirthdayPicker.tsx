import { DatePicker } from 'antd';
import zhCN from 'antd/es/date-picker/locale/zh_CN';
import dayjs, { type Dayjs } from 'dayjs';
import 'dayjs/locale/zh-cn';

dayjs.locale('zh-cn');

export type BirthdayPrecision = 'none' | 'year' | 'month' | 'date';
export type BirthdayParts = { birthYear: string; birthMonth: string; birthDay: string };

type Props = BirthdayParts & {
  precision: BirthdayPrecision;
  onChange: (precision: BirthdayPrecision, parts: BirthdayParts) => void;
};

const calendarValue = (year: string, month: string, day: string) => dayjs('2000-01-01')
  .year(Number(year)).month(Number(month || '1') - 1).date(Number(day || '1'));

export default function GenealogyBirthdayPicker({ precision, birthYear, birthMonth, birthDay, onChange }: Props) {
  const parts = { birthYear, birthMonth, birthDay };
  const selected = birthYear && (precision === 'year' || birthMonth && (precision === 'month' || birthDay))
    ? calendarValue(birthYear, birthMonth, birthDay)
    : null;
  const initial = birthYear
    ? calendarValue(birthYear, birthMonth, '1')
    : dayjs();

  const choose = (value: Dayjs | null) => {
    if (!value) { onChange(precision, { birthYear: '', birthMonth: '', birthDay: '' }); return; }
    onChange(precision, {
      birthYear: String(value.year()),
      birthMonth: precision === 'year' ? '' : String(value.month() + 1),
      birthDay: precision === 'date' ? String(value.date()) : '',
    });
  };

  const changePrecision = (next: BirthdayPrecision) => {
    onChange(next, next === 'none' ? { birthYear: '', birthMonth: '', birthDay: '' }
      : next === 'year' ? { ...parts, birthMonth: '', birthDay: '' }
        : next === 'month' ? { ...parts, birthDay: '' } : parts);
  };

  const pickerProps = { locale: zhCN, value: selected, defaultPickerValue: initial, className: 'w-full', allowClear: true };
  return <div className="rounded-xl border border-emerald-100 bg-emerald-50/40 p-3">
    <label className="block text-xs font-medium text-gray-700" htmlFor="genealogy-birthday-precision">生日精度</label>
    <select id="genealogy-birthday-precision" aria-label="生日精度" value={precision} onChange={(event) => changePrecision(event.target.value as BirthdayPrecision)} className="mt-1 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm">
      <option value="none">不填写</option><option value="year">仅年份</option><option value="month">年和月</option><option value="date">完整日期</option>
    </select>
    {precision !== 'none' && <div className="mt-3">
      <p className="mb-1 text-xs text-gray-600">从日历选择{precision === 'year' ? '年份' : precision === 'month' ? '月份' : '具体日期'}</p>
      {precision === 'year' && <DatePicker {...pickerProps} picker="year" format="YYYY年" onChange={choose} />}
      {precision === 'month' && <DatePicker {...pickerProps} picker="month" format="YYYY年M月" onChange={choose} />}
      {precision === 'date' && <DatePicker {...pickerProps} picker="date" format="YYYY年M月D日" onChange={choose} />}
      <p className="mt-1 text-xs text-gray-500">只保存所选精度；未选定的月、日不会补值。</p>
    </div>}
  </div>;
}
