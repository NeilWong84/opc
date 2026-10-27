import 'reference_models.dart';

/// Original synthetic reference material based on the MasterGo handoff.
/// File names and document bodies are customer content, never translation keys.
/// Sizes and duration match assets/references/manifest.json; update together.
/// A real adapter must supply server-authorized files and converted previews.
List<TaskReference> inquiryReferenceSamples({int publishedVersion = 3}) =>
    List.unmodifiable([
      TaskReference(
        id: 'inquiry-overview',
        fileName: '画面イメージ_01.png',
        kind: ReferenceKind.image,
        sizeBytes: 137755,
        assetPath: 'assets/references/inquiry-overview.png',
        thumbnailAsset: 'assets/references/inquiry-overview.png',
        publishedVersion: publishedVersion,
        description: '問い合わせ一覧の参考画面',
      ),
      TaskReference(
        id: 'inquiry-detail',
        fileName: '画面イメージ_02.png',
        kind: ReferenceKind.image,
        sizeBytes: 163141,
        assetPath: 'assets/references/inquiry-detail.png',
        thumbnailAsset: 'assets/references/inquiry-detail.png',
        publishedVersion: publishedVersion,
        description: '問い合わせ詳細と対応履歴の参考画面',
      ),
      TaskReference(
        id: 'workflow-video',
        fileName: '操作フロー.mp4',
        kind: ReferenceKind.video,
        sizeBytes: 81322,
        assetPath: 'assets/references/workflow.mp4',
        thumbnailAsset: 'assets/references/workflow-poster.png',
        publishedVersion: publishedVersion,
        durationSeconds: 8,
        description: '問い合わせの登録、担当者の変更、対応状況の更新をまとめた参考動画です。',
      ),
      TaskReference(
        id: 'requirements',
        fileName: '要件整理_v1.docx',
        kind: ReferenceKind.document,
        sizeBytes: 37272,
        assetPath: 'assets/references/requirements.docx',
        publishedVersion: publishedVersion,
        pages: [
          ReferencePage(
            title: 'お問い合わせ管理ツール · 要件整理書',
            paragraphs: [
              '小規模チームの問い合わせを一元管理し、受付から対応完了までの状況を共有します。',
              '利用者はチーム内の担当者です。顧客から寄せられた問い合わせを登録し、対応漏れを防ぎます。',
            ],
          ),
          ReferencePage(
            title: '02 対象範囲',
            paragraphs: ['主な機能', '対象外：外部 CRM 連携・既存データの移行'],
            bullets: ['問い合わせの登録・一覧・検索', '担当者と対応状況の更新', 'チーム用ログインと閲覧権限'],
          ),
          ReferencePage(
            title: '03 確認ポイント',
            paragraphs: ['登録から対応完了まで、チームで状況を確認できることを確かめます。'],
            bullets: ['件名と本文から検索できること', '担当者の変更履歴が残ること', 'スマートフォンから閲覧できること'],
          ),
        ],
      ),
      TaskReference(
        id: 'fields',
        fileName: '項目定義.xlsx',
        kind: ReferenceKind.spreadsheet,
        sizeBytes: 5345,
        assetPath: 'assets/references/fields.xlsx',
        publishedVersion: publishedVersion,
        sheets: inquiryFieldSheets(),
      ),
      TaskReference(
        id: 'sample-data',
        fileName: 'サンプルデータ.csv',
        kind: ReferenceKind.spreadsheet,
        sizeBytes: 200,
        assetPath: 'assets/references/sample.csv',
        publishedVersion: publishedVersion,
        sheets: [
          ReferenceSheet(
            name: 'サンプルデータ',
            rows: [
              ['問い合わせID', '件名', 'ステータス', '担当者'],
              ['INQ-001', '資料の送付について', 'new', '田中'],
              ['INQ-002', '利用方法の確認', 'in_progress', '佐藤'],
              ['INQ-003', '登録情報の変更', 'resolved', '田中'],
            ],
          ),
        ],
      ),
      TaskReference(
        id: 'screens',
        fileName: '画面構成.pptx',
        kind: ReferenceKind.presentation,
        sizeBytes: 312168,
        assetPath: 'assets/references/screens.pptx',
        publishedVersion: publishedVersion,
        description: '問い合わせの登録から対応完了までの流れを確認するための参考資料です。',
        pages: [
          ReferencePage(
            title: 'INQUIRY WORKSPACE',
            paragraphs: ['チームの対応を、ひとつの画面に。'],
            bullets: ['登録', '共有', '対応'],
          ),
          ReferencePage(
            title: '02 サービスの全体像',
            paragraphs: ['問い合わせ一覧から、担当者と対応状況を確認します。'],
            imageAsset: 'assets/references/inquiry-overview.png',
          ),
          ReferencePage(
            title: '03 問い合わせの詳細',
            paragraphs: ['担当者の変更と対応履歴を記録し、チームに共有します。'],
            imageAsset: 'assets/references/inquiry-detail.png',
          ),
        ],
      ),
      TaskReference(
        id: 'workflow-pdf',
        fileName: '業務フロー.pdf',
        kind: ReferenceKind.pdf,
        sizeBytes: 55365,
        assetPath: 'assets/references/workflow.pdf',
        publishedVersion: publishedVersion,
        pages: [
          ReferencePage(
            title: '業務フロー · 受付から対応完了まで',
            paragraphs: ['小規模チームの問い合わせを一元管理し、受付から対応完了までの状況を共有します。'],
          ),
          ReferencePage(
            title: '02 対応の流れ',
            paragraphs: ['対象外：外部 CRM 連携・既存データの移行'],
            bullets: ['問い合わせを登録', '担当者が内容と優先度を確認', '対応履歴を記録して完了'],
          ),
          ReferencePage(
            title: '03 状態の共有',
            paragraphs: ['new → in_progress → resolved', '担当者と更新日時を一覧で確認します。'],
          ),
        ],
      ),
      TaskReference(
        id: 'notes',
        fileName: '補足事項.md',
        kind: ReferenceKind.text,
        sizeBytes: 571,
        assetPath: 'assets/references/notes.md',
        publishedVersion: publishedVersion,
        text: referenceNotes,
      ),
      // Never exposed through the repository. Their existence tests that even
      // names, counts and thumbnails are filtered before a list is returned.
      TaskReference(
        id: 'private-client-memo',
        fileName: '未公開_顧客メモ.md',
        kind: ReferenceKind.text,
        sizeBytes: 571,
        assetPath: 'assets/references/notes.md',
        publishedVersion: 0,
        text: 'この資料は公開されていません。',
      ),
      TaskReference(
        id: 'old-screen',
        fileName: '旧版_画面イメージ.png',
        kind: ReferenceKind.image,
        sizeBytes: 163141,
        assetPath: 'assets/references/inquiry-detail.png',
        thumbnailAsset: 'assets/references/inquiry-detail.png',
        publishedVersion: publishedVersion - 1,
      ),
    ]);

List<ReferenceSheet> inquiryFieldSheets() => List.unmodifiable([
  ReferenceSheet(
    name: '項目定義',
    rows: [
      ['項目名', '型', '必須'],
      ['問い合わせID', '文字列', 'はい'],
      ['件名', '文字列', 'はい'],
      ['本文', '長文', 'はい'],
      ['ステータス', '選択', 'はい'],
      ['担当者', 'ユーザー', 'いいえ'],
      ['受付日時', '日時', '自動'],
      ['更新日時', '日時', '自動'],
    ],
  ),
  ReferenceSheet(
    name: 'ステータス',
    rows: [
      ['状態値', '表示名', '内容'],
      ['new', '新規', '問い合わせの受付直後'],
      ['in_progress', '対応中', '担当者が内容を確認'],
      ['resolved', '完了', '対応履歴を記録済み'],
    ],
  ),
  ReferenceSheet(
    name: '権限',
    rows: [
      ['操作', '担当者', '管理担当'],
      ['問い合わせ閲覧', '可', '可'],
      ['担当者変更', '可', '可'],
      ['チーム設定', '不可', '可'],
    ],
  ),
]);

List<TaskReference> quoteReferenceSamples({int publishedVersion = 1}) =>
    List.unmodifiable([
      TaskReference(
        id: 'quote-template',
        fileName: '見積テンプレート.xlsx',
        kind: ReferenceKind.spreadsheet,
        sizeBytes: 3916,
        assetPath: 'assets/references/quote-template.xlsx',
        publishedVersion: publishedVersion,
        sheets: [
          ReferenceSheet(
            name: '見積明細',
            rows: [
              ['品名', '数量', '単価（円）', '金額（円）'],
              ['要件整理', '1', '30000', '30000'],
              ['開発作業', '1', '120000', '120000'],
              ['合計', '', '', '150000'],
            ],
          ),
        ],
      ),
    ]);

const referenceNotes = '''# 開発にあたっての補足

最終更新：2026.10.13

## 利用シーン

小規模チームが日々の問い合わせを整理し、担当者ごとの対応状況を共有するために使います。

## 確認したいポイント

- 件名と本文から検索できること
- 担当者の変更履歴が残ること
- スマートフォンから閲覧できること

## 初回の開発範囲

外部システムとの連携は、今回の開発には含めません。

## サンプルの状態値

`new → in_progress → resolved`
''';
