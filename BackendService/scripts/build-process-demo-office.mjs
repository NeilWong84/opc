// Copy into .local/process-demo-20261025/build/ with a runtime node_modules junction.
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { Workbook, SpreadsheetFile, Presentation, PresentationFile } from '@oai/artifact-tool';

const root = path.resolve(process.argv[2] ?? '.local/process-demo-20261025');
const runtimePython = process.argv[3];
process.env.RUNTIME_NODE_MODULES = 'C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const skill = 'C:/Users/Administrator/.codex/plugins/cache/openai-primary-runtime/presentations/26.1020.11618/skills/presentations';
const families = JSON.parse(await fs.readFile(path.join(root, 'families.json'), 'utf8'));
const { finalizePresentation } = await import(pathToFileURL(path.join(skill, 'container_tools/artifact_tool_utils.mjs')).href);
const fontFamily = 'Yu Gothic';
await fs.mkdir(path.join(root, 'build'), { recursive: true });

for (const f of families) {
  const workbook = Workbook.create();
  const sheet = workbook.worksheets.add('サンプル');
  const checks = workbook.worksheets.add('検収項目');
  sheet.showGridLines = checks.showGridLines = false;
  sheet.getRange('A2').values = [[f.title + ' データ例']];
  sheet.getRange('A3').values = [['合成デモ資料 / 合成演示资料  2026-10-25']];
  sheet.getRange('A5:E5').values = [f.key === 'booking' ? ['ID', '日付', '時刻', '表示名', '状態'] : ['ID', '種類', 'ファイル名', '公開範囲', '検査状態']];
  sheet.getRange('A6:E8').values = f.rows;
  sheet.getRange('A10:B11').values = [['レコード数 / 记录数', null], ['确认记录 / clean 数', null]];
  sheet.getRange('B10').formulas = [['=COUNTA(A6:A8)']];
  sheet.getRange('B11').formulas = [[`=COUNTIF(E6:E8,"${f.key === 'booking' ? 'confirmed' : 'clean'}")`]];
  checks.getRange('A2').values = [['検収項目 / 验收检查']];
  checks.getRange('A4:D7').values = [
    ['ID', '検査 / 检查内容', '期待結果 / 预期', '合成記録'],
    ['A01', '保存と再読込 / 保存后读取', '同じ内容', '未実施'],
    ['A02', '私有資料の権限 / 私有资料权限', '越権を拒否', '未実施'],
    ['A03', '原本ダウンロード / 原件下载', 'SHA-256 一致', '未実施'],
  ];
  checks.getRange('D5:D7').dataValidation = { rule: { type: 'list', values: ['未実施', '確認済', '要修正'] } };
  for (const s of [sheet, checks]) {
    s.getRange('A2:E12').format.font = { name: fontFamily, size: 11, color: '#24354B' };
    s.getRange('A2:E12').format.rowHeight = 29;
    s.getRange('A2:E12').format.verticalAlignment = 'center';
    s.getRange('A2').format.font = { name: fontFamily, size: 16, bold: true, color: '#142C49' };
    s.getRange('A:A').format.columnWidth = 16;
    s.getRange('B:B').format.columnWidth = 39;
    s.getRange('C:C').format.columnWidth = 32;
    s.getRange('D:D').format.columnWidth = 23;
    s.getRange('E:E').format.columnWidth = 19;
  }
  for (const [s, range] of [[sheet, 'A5:E5'], [checks, 'A4:D4']]) {
    s.getRange(range).format.fill = '#214D78';
    s.getRange(range).format.font = { name: fontFamily, size: 11, color: '#FFFFFF', bold: true };
    s.getRange(range).format.horizontalAlignment = 'center';
  }
  sheet.getRange('A7:E7').format.fill = '#EEF3F8';
  checks.getRange('A6:D6').format.fill = '#EEF3F8';
  workbook.recalculate();
  const result = await workbook.inspect({ kind: 'table', range: 'サンプル!A10:B11', include: 'values,formulas', tableMaxRows: 2, tableMaxCols: 2 });
  console.log(f.key, result.ndjson);
  const errors = await workbook.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#NULL!', options: { useRegex: true, maxResults: 10 } });
  await fs.writeFile(path.join(root, 'qa', f.key + '-workbook-inspect.json'), JSON.stringify({ result, errors }));
  for (const s of [sheet, checks]) {
    const preview = await workbook.render({ sheetName: s.name, range: 'A1:E12', scale: 1.5, format: 'png' });
    await fs.writeFile(path.join(root, 'qa', f.key + '-' + s.name + '.png'), new Uint8Array(await preview.arrayBuffer()));
  }
  await (await SpreadsheetFile.exportXlsx(workbook)).save(path.join(root, 'assets', f.key + '-data.xlsx'));

  const deck = Presentation.create({ slideSize: { width: 1280, height: 720 } });
  const content = [
    [f.title, f.zh, f.goal, '合成デモ資料  2026-10-25'],
    ['実装する範囲', '开发范围', ...f.features],
    ['資料と権限', '资料与权限', '原文添付はお客様と運営のみ参照します。', '经审核选中的参考资料才随当前版本发布。', '納品は内部確認後にお客様へ公開します。'],
    ['検収と変更', '验收与修改', '保存、再取得、原本ダウンロードと権限を確認します。', '修改意见记录具体问题，复交付保留版本。', '报价、内部质检与客户验收均不表示支付。'],
  ];
  const text = (slide, value, x, y, w, h, size, color, bold = false) => {
    const shape = slide.shapes.add({ geometry: 'textbox', position: { left: x, top: y, width: w, height: h }, fill: 'none', line: { fill: 'none', width: 0 } });
    shape.text = value;
    shape.text.style = { typeface: fontFamily, fontSize: size, color, bold };
    return shape;
  };
  for (const [i, lines] of content.entries()) {
    const slide = deck.slides.add();
    slide.background.fill = '#F7F9FC';
    slide.shapes.add({ geometry: 'rect', position: { left: 0, top: 0, width: 18, height: 720 }, fill: '#214D78', line: { fill: 'none', width: 0 } });
    text(slide, 'OPC  DEVELOPMENT DEMO', 70, 38, 900, 35, 18, '#52677F');
    text(slide, lines[0], 70, 112, 1130, 90, 44, '#142C49', true);
    text(slide, lines[1], 70, 210, 1130, 55, 27, '#52677F');
    for (const [n, line] of lines.slice(2).entries()) text(slide, line, 70, 320 + 82 * n, 1130, 68, 25, '#24354B');
    text(slide, `合成資料 / Synthetic fixture                                       ${i + 1} / 4`, 70, 653, 1100, 35, 16, '#52677F');
    const preview = await deck.export({ slide, format: 'png', scale: 1 });
    await fs.writeFile(path.join(root, 'qa', `${f.key}-slide-${i + 1}.png`), new Uint8Array(await preview.arrayBuffer()));
  }
  const candidate = path.join(root, 'build', f.key + '-candidate.pptx');
  await (await PresentationFile.exportPptx(deck)).save(candidate);
  await finalizePresentation({
    workspaceDir: root, candidatePath: candidate, finalPath: path.join(root, 'assets', f.key + '-overview.pptx'),
    pythonExecutable: runtimePython,
    integrityValidatorPath: path.join(skill, 'container_tools/inspect_presentation_package_integrity.py'),
    layoutValidatorPath: path.join(skill, 'container_tools/inspect_presentation_layout_geometry.py'),
    explicitTotalSlideCount: 4, requiredNativeTableOwnerSlides: [], requiredNativeChartOwnerSlides: [],
    layoutArgs: ['--expected-slide-size-emu', '12192000,6858000', '--validate-heading-fit'],
    fontPolicy: { basis: 'design', families: [fontFamily] }, verifyArtifactToolImport: true,
    receiptPath: path.join(root, 'qa', f.key + '-deck-validation.json'),
  });
}
console.log('Two XLSX workbooks and two PPTX presentations exported.');
