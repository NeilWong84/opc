// Copy beside the Office builder in the ignored build directory before running.
import fs from 'node:fs/promises';
import path from 'node:path';
import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const root = path.resolve(process.argv[2] ?? '.local/process-demo-20261025');
const evidence = [];
for (const [family, expected] of [['booking', 2], ['media', 3]]) {
  const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(root, 'assets', family + '-data.xlsx')));
  const sheet = workbook.worksheets.getItem('サンプル');
  const original = sheet.getRange('E6').values[0][0];
  const read = () => Number(sheet.getRange('B11').values[0][0]);
  workbook.recalculate();
  if (read() !== expected) throw new Error(family + ': imported formula result incorrect');
  sheet.getRange('E6').values = [['non-matching-test-value']];
  workbook.recalculate();
  if (read() !== expected - 1) throw new Error(family + ': dependency recalculation failed');
  sheet.getRange('E6').values = [[original]];
  workbook.recalculate();
  if (read() !== expected) throw new Error(family + ': restored input result incorrect');
  evidence.push({ family, before: expected, changed: expected - 1, restored: expected, saved_file_modified: false });
}
await fs.writeFile(path.join(root, 'qa', 'workbook-recalculation.json'), JSON.stringify(evidence, null, 2));
console.log('Both exported workbooks: imported formulas, changed input and restored input verified; originals unchanged.');
