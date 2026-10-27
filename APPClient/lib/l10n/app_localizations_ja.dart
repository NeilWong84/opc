// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get apiRefresh => '更新';

  @override
  String get apiWorkspace => 'ワークスペース';

  @override
  String get apiEmpty => '記録がありません。更新して最新の状態を確認できます。';

  @override
  String get apiNewRequest => '開発の相談を送る';

  @override
  String get apiNewRequestTab => '依頼する';

  @override
  String get apiRequestTitle => '開発の相談';

  @override
  String get apiDescription => '目的・利用場面・希望する成果';

  @override
  String get apiTiming => '希望完了日';

  @override
  String get apiPickCompletionDate => '希望完了日を選択してください';

  @override
  String get apiBudget => '予算の希望（JPY）';

  @override
  String get apiDraftSaved => '下書きをサーバーに保存しました';

  @override
  String get apiSaveDraft => '下書きを保存';

  @override
  String get apiSubmitRequest => '運営の審査に提出';

  @override
  String get apiSubmitted => '相談を提出しました。運営の審査をお待ちください';

  @override
  String get apiReviewNotice =>
      'コンプライアンス審査と技術整理が完了した後に公開されます。添付は非公開資料として保存され、公開資料は運営が別途確認します。';

  @override
  String get apiFiles => '添付資料';

  @override
  String get apiPickFile => 'ファイルを選んでアップロード';

  @override
  String get apiUploaded =>
      '添付はサーバーに保存されています。安全確認待ちの添付付きで相談を提出できます。確認完了後にプレビュー・ダウンロード・納品への利用が可能になります。';

  @override
  String get apiFilePending => '安全確認待ち';

  @override
  String get apiFileReady => '安全確認済み';

  @override
  String get apiFileBlocked => '利用できないファイル';

  @override
  String get apiFileTooLarge => '20 MB 以下の空でないファイルを選択してください';

  @override
  String get apiRemoveFile => '添付を外す';

  @override
  String get apiRequired => '入力してください';

  @override
  String get apiDetails => '詳細と進捗';

  @override
  String get apiVersion => '現在のバージョン';

  @override
  String get apiPendingTerms => '協業条件の確認待ち';

  @override
  String get apiTerms => '協業条件';

  @override
  String get apiTermsConfirmed => 'この条件を確認済みです。相手の確認をお待ちください';

  @override
  String get apiConfirmTerms => '現在の協業条件に同意';

  @override
  String get apiConfirmTermsBody =>
      '表示中のバージョンの範囲・見積・納品条件に同意します。双方の確認後に納品を提出できます。';

  @override
  String get apiConfirmed => '確認しました';

  @override
  String get apiAmount => '見積金額（JPY）';

  @override
  String get apiDueAt => '期限（JST）';

  @override
  String get apiMessages => 'メッセージ';

  @override
  String get apiMessageInput => 'メッセージを入力';

  @override
  String get apiSend => '送信';

  @override
  String get apiMessageSent => 'メッセージを送信しました';

  @override
  String get apiReply => '追加情報を送る';

  @override
  String get apiConsult => '運営に問い合わせ';

  @override
  String get apiConsultNotice => '問い合わせでは案件の受注や協業は確定しません。合意済みの関係を運営が記録します。';

  @override
  String get apiDelivery => '納品成果';

  @override
  String get apiOpenDelivery => '納品物を提出';

  @override
  String get providerOverview => '担当プロジェクトの概要';

  @override
  String get providerIntro => '相談・開発・納品の状況を確認し、案件一覧から公開中の案件を探せます。';

  @override
  String get providerCommunicating => '相談中';

  @override
  String get providerDelivered => '提出済み';

  @override
  String get providerDeliveredHelp =>
      '提出済みには内部確認中・検収待ち・完了の案件が含まれます。各案件の状態をご確認ください。';

  @override
  String get providerHall => '案件一覧';

  @override
  String get providerHallHelp => '審査済みで公開中、かつ協業がまだ開始されていない案件を表示します。';

  @override
  String get providerViewAll => 'すべて見る';

  @override
  String get negotiationTitle => '協業相談と条件';

  @override
  String get negotiationStart => '案件について相談';

  @override
  String get negotiationProvider => '担当者';

  @override
  String get negotiationPropose => '条件を提出してお客様に確認を依頼';

  @override
  String get negotiationProposed => '条件を提出しました。お客様の確認をお待ちください';

  @override
  String get negotiationApprove => '今回の範囲と条件を確認';

  @override
  String get negotiationApproveBody =>
      '今回の公開範囲、担当者、条件、金額、期限を確認し、この条件での受注に同意します。確認後、担当者が受注することで開始します。支払いは発生しません。';

  @override
  String get negotiationApproved => 'お客様が範囲と条件を確認しました。担当者の受注待ちです';

  @override
  String get negotiationAwaiting => 'お客様による今回の範囲と条件の確認待ちです';

  @override
  String get negotiationClaim => '案件を受注';

  @override
  String get negotiationClaimBody =>
      'お客様が確認した現在の範囲と条件で受注します。案件は現在のアカウントに割り当てられ、進行中になります。';

  @override
  String get negotiationClaimed => '受注しました。案件はご自身の担当となり、開始されました';

  @override
  String get negotiationEdit => '条件を変更して再確認を依頼';

  @override
  String get negotiationUnavailable => 'この案件は公開終了または協業開始済みのため受注できません。';

  @override
  String get negotiationOutdated => '公開範囲が変更されました。現在の条件を再提出し、お客様に確認を依頼してください。';

  @override
  String get negotiationOptionalAmount => '合意金額（JPY、任意）';

  @override
  String get negotiationOptionalDue => '期限を選択（JST 18:00、任意）';

  @override
  String get negotiationFormError => '条件を入力してください。金額は有効な非負の整数で入力してください。';

  @override
  String get apiSubmitDelivery => '納品を確認に提出';

  @override
  String get apiSourceRepo => 'ソースリポジトリの HTTPS URL';

  @override
  String get apiSourceCommit => '固定バージョン（40 または 64 桁 commit SHA）';

  @override
  String get apiSourceFile => 'ソースアーカイブ';

  @override
  String get apiSourceArchiveRef => 'お客様がソースを取得できるアーカイブの証跡';

  @override
  String get apiSourceHelp =>
      'HTTPS リポジトリ URL、完全な commit SHA、お客様が取得できるアーカイブの証跡を入力するか、安全確認済みのソースアーカイブを選択してください。';

  @override
  String get apiGuide => '操作・デプロイ手順';

  @override
  String get apiTestEvidence => '実施したテストのコマンドと結果';

  @override
  String get apiDeliveryNote => '納品の説明';

  @override
  String get apiDeliverySubmitted => '納品を保存しました。運営の確認後にお客様へ公開されます';

  @override
  String get apiAccept => '検収を確定';

  @override
  String get apiAcceptBody =>
      '現在の納品バージョン、ソース、操作手順を確認し、合意範囲を満たすことを検証しました。検収を記録します。支払は行いません。';

  @override
  String get apiRevision => '修正を依頼';

  @override
  String get apiRevisionReason => '問題と修正内容';

  @override
  String get apiChanged => '状態を更新しました';

  @override
  String get apiUnpublishedDelivery => '運営の確認待ち';

  @override
  String get apiPublishedDelivery => 'お客様へ公開済み';

  @override
  String get apiNotifications => '通知';

  @override
  String get apiMarkRead => '既読にする';

  @override
  String get apiNoNotifications => '通知はありません';

  @override
  String get apiProfile => 'アカウント';

  @override
  String get apiLogout => 'ログアウト';

  @override
  String get apiSessionNotice =>
      'アプリを再起動した場合はログインしてください。言語設定は端末に、業務記録はサーバーに保存されます。';

  @override
  String get apiPasswordHelp => 'パスワード再設定メールは未対応です。運営にお問い合わせください。';

  @override
  String get apiPasswordLength => '登録パスワードは 12 文字以上';

  @override
  String get apiFilePreview => 'ファイルのプレビュー';

  @override
  String get apiOfficeUnavailable =>
      'Office/PDF のオンライン変換は未対応です。原本をダウンロードし、端末のアプリで開けます。';

  @override
  String get apiDownload => '原本をダウンロード';

  @override
  String get apiOpenFile => 'ファイルを開く';

  @override
  String get apiExportFile => 'ファイルアプリに保存';

  @override
  String get apiDownloadDone => 'アプリに原本を保存しました';

  @override
  String get apiExportDone => 'ファイルを保存しました';

  @override
  String get apiFileActionFailed => '開く・保存操作が完了していません。再試行するか別のアプリを選択してください。';

  @override
  String get apiRetry => '再試行';

  @override
  String get apiCancel => 'キャンセル';

  @override
  String get apiLoading => '読み込み中…';

  @override
  String get apiNetworkError => 'サーバーに接続できません。接続を確認して再試行してください。';

  @override
  String get apiConflict => '記録が更新されています。更新して最新バージョンを確認してから提出してください。';

  @override
  String get apiForbidden => 'この操作を行う権限がありません。更新または再ログインしてください。';

  @override
  String get apiUnexpected => 'サービスを利用できません。しばらくしてから再試行してください。';

  @override
  String get apiApiSetup =>
      'サービス URL が未設定です。OPC_API_BASE_URL に HTTPS API を設定してください。ローカルデバッグのみループバック HTTP を許可します。';

  @override
  String get apiDraft => '下書き';

  @override
  String get apiPlay => '再生 / 一時停止';

  @override
  String get apiNoPreview => 'この形式はアプリ内プレビュー未対応です。原本をダウンロードして開いてください。';

  @override
  String get apiSafetyNotice =>
      'アップロード後は運営の安全確認をお待ちください。完了後に更新して提出してください。確認前のファイルは正式な添付として提出できません。';

  @override
  String get apiScopeIncluded => '対象範囲';

  @override
  String get apiScopeExcluded => '対象外の範囲';

  @override
  String get apiScopeDeliverables => '合意した成果物';

  @override
  String get apiScopeAcceptance => '検収基準';

  @override
  String get apiScopeRevision => '修正条件';

  @override
  String get apiWithdrawn => '取り下げ済み';

  @override
  String get apiRejected => '審査で却下';

  @override
  String get apiCancelled => 'キャンセル済み';

  @override
  String get apiTextTruncated => '原文の一部のみ表示しています。全文は原本をダウンロードして確認してください。';

  @override
  String get apiRequestUpdated => '相談が更新されました';

  @override
  String get apiTermsUpdated => '協業条件が更新されました。再確認してください';

  @override
  String get apiDeliveryReviewed => '納品の内部確認が完了しました';

  @override
  String get apiDeliveryWithdrawn => '納品が取り下げられました。更新をお待ちください';

  @override
  String get apiPublicationWithdrawn => '案件が一覧から取り下げられました';

  @override
  String get apiFileUnavailable => 'ファイルにアクセスできないか、安全確認が未完了です。状態を更新してください。';

  @override
  String get classificationPlatform => '開発対象';

  @override
  String get classificationType => '開発システム種別';

  @override
  String get classificationAll => 'すべて';

  @override
  String get classificationUnclassified => '未分類';

  @override
  String get classificationClear => '分類の絞り込みを解除';

  @override
  String get classificationOptional => '任意：主な開発対象とシステム種別を選択できます。未選択の場合は未分類です。';

  @override
  String get authDemoAccounts => 'デモアカウント';

  @override
  String get authDemoInfo =>
      'データはこのアプリ内のサンプルです。実際の登録・送信・アップロードは行いません。再起動でデータはリセットされますが、言語設定は保存されます。';

  @override
  String get authTryCustomer => 'お客様として試す';

  @override
  String get authTryMember => '内部メンバーとして試す';

  @override
  String get authResetTitle => 'パスワードの再設定';

  @override
  String get authResetHelp =>
      'デモ環境ではメールを送信しません。デモアカウントのパスワードは demo1234 です。\n\n新しく登録したアカウントはアプリの再起動またはデモのリセットで削除されます。';

  @override
  String get authTheme => 'テーマを切り替える';

  @override
  String get authEyebrow => 'AI DEVELOPMENT, TOGETHER';

  @override
  String get authRegisterHero => 'アイデアを、\nここから一緒に。';

  @override
  String get authLoginHero => 'つくりたいを、\n動くかたちに。';

  @override
  String get authIntro => 'アイデアの相談から、開発・納品まで。\nあなたの一歩を、OPC がサポートします。';

  @override
  String get authNoExpertise => '専門知識はなくても大丈夫';

  @override
  String get authReviewHelp => '運営がご依頼を確認し、要件を整理します。';

  @override
  String get authName => 'お名前';

  @override
  String get authNameHint => 'お名前を入力';

  @override
  String get authNameRequired => 'お名前を入力してください';

  @override
  String get authEmail => 'メールアドレス';

  @override
  String get authEmailInvalid => 'メールアドレスを確認してください';

  @override
  String get authPassword => 'パスワード';

  @override
  String get authPasswordNewHint => '8文字以上で入力';

  @override
  String get authPasswordHint => 'パスワードを入力';

  @override
  String get authShowPassword => 'パスワードを表示';

  @override
  String get authHidePassword => 'パスワードを隠す';

  @override
  String get authPasswordRequired => 'パスワードを入力してください（登録時は8文字以上）';

  @override
  String get authForgot => 'パスワードをお忘れですか？';

  @override
  String get authBusy => '確認しています…';

  @override
  String get authRegisterSubmit => '登録して相談をはじめる';

  @override
  String get authLogin => 'ログインする';

  @override
  String get authExisting => 'アカウントをお持ちの方';

  @override
  String get authNew => 'はじめてご利用の方';

  @override
  String get authBackLogin => 'ログインに戻る';

  @override
  String get authRegister => '新規登録して相談する';

  @override
  String get authInternalLogin => '内部アカウントをお持ちの方も、こちらからログイン';

  @override
  String get authLegalTitle => '利用規約・プライバシー';

  @override
  String get authLegalHelp =>
      '現在は合成データによる デモです。正式な利用規約・個人情報の取扱いは本番提供前に設定します。実際の個人情報や秘密情報を入力しないでください。';

  @override
  String get hallTitle => '案件一覧';

  @override
  String get hallSubtitle => 'あなたの技術を、次のプロジェクトへ';

  @override
  String get hallNotifications => 'お知らせ';

  @override
  String get hallInternal => '内部アカウント';

  @override
  String get hallPublishedWork => '公開済みの開発案件';

  @override
  String get hallSearch => 'キーワードで案件を探す';

  @override
  String get hallSort => '更新が新しい順';

  @override
  String get hallEmpty => '該当する案件はありません';

  @override
  String get hallEmptyHelp => 'キーワードや条件を変えてお試しください。';

  @override
  String get hallPublished => '公開中';

  @override
  String get hallStructured => '要件整理済み';

  @override
  String get hallView => '詳細を見る';

  @override
  String get hallDetail => '案件詳細';

  @override
  String get hallDevelopment => '開発サービス';

  @override
  String get hallConsult => '案件について相談する';

  @override
  String get hallNotAssigned => '相談の送信だけでは、担当は確定しません。';

  @override
  String get hallDuration => '開発期間の目安';

  @override
  String get hallMethod => '進め方';

  @override
  String get hallOnline => 'オンライン';

  @override
  String get hallScope => '今回つくるもの';

  @override
  String get hallScopeHelp => '具体的な機能・対象範囲は、公開された説明をもとに運営と確認します。';

  @override
  String get hallDeliverables => '交付物と確認ポイント';

  @override
  String get hallFiles => 'ソースコード / 操作説明書 / テスト結果';

  @override
  String get hallIndividualScope => '納品物の内容・確認ポイントは、運営が整理した範囲に沿って個別に確認します。';

  @override
  String get hallPrivateHelp =>
      '詳細な資料と担当範囲は、運営との相談時に確認します。非公開の添付資料は案件一覧に表示されません。';

  @override
  String get hallConsultHelp => '確認したいことや対応できる範囲をお伝えください。担当の確定方法は運営が別途ご案内します。';

  @override
  String get hallConsultHint => '相談内容を入力';

  @override
  String get hallConsultRequired => '相談内容を入力してください';

  @override
  String get hallSending => '送信中…';

  @override
  String get hallSend => '相談を送信する';

  @override
  String get hallSent => '相談を送信しました。担当はまだ確定していません。';

  @override
  String get coreBack => '戻る';

  @override
  String get coreBackLogin => 'ログイン画面へ戻る';

  @override
  String get coreActionFailed => '処理できませんでした。もう一度お試しください。';

  @override
  String get coreNeedsInfo => '回答が必要';

  @override
  String get coreReviewing => '内容を確認中';

  @override
  String get corePublished => '公開中';

  @override
  String get coreDeveloping => '開発中';

  @override
  String get coreInternalReview => '運営が確認中';

  @override
  String get coreAwaitingAcceptance => 'ご確認待ち';

  @override
  String get coreRevision => '修正対応中';

  @override
  String get coreCompleted => '検収完了';

  @override
  String get coreClose => '閉じる';

  @override
  String get coreLanguage => '表示言語';

  @override
  String get coreJapanese => '日本語';

  @override
  String get coreChinese => '简体中文';

  @override
  String get coreLanguageSaveFailed => '言語設定を保存できませんでした。再起動後は元の言語に戻る場合があります。';

  @override
  String get coreSetup => '接続設定が必要です。現在のバージョンはデモ専用です。';

  @override
  String get coreAll => 'すべて';

  @override
  String get coreWeb => 'Web アプリ';

  @override
  String get coreAutomation => '業務自動化';

  @override
  String get coreAi => 'AI 開発';

  @override
  String get errorSessionChanged => 'アカウントの状態が変わりました。画面を開き直してください。';

  @override
  String get errorNetwork => 'デモ通信に失敗しました。内容を確認して、もう一度お試しください。';

  @override
  String get errorUnauthenticated => 'ログインしてください。';

  @override
  String get errorInactive => 'このアカウントは停止中です。';

  @override
  String get errorCustomer => 'お客様のアカウントでご利用ください。';

  @override
  String get errorProvider => '有効な内部承接権限が必要です。';

  @override
  String get errorNotFound => 'この案件を表示できません。';

  @override
  String get errorCredentials => 'メールアドレスまたはパスワードをご確認ください。';

  @override
  String get errorName => 'お名前を80文字以内で入力してください。';

  @override
  String get errorEmail => '有効なメールアドレスを入力してください。';

  @override
  String get errorPassword => 'パスワードは8文字以上で入力してください。';

  @override
  String get errorEmailExists => 'このメールアドレスは登録済みです。';

  @override
  String get errorDescription => 'ご相談内容を10〜4,000文字で入力してください。';

  @override
  String get errorRequest => '希望時期とご予算の意向を選んでください。';

  @override
  String get errorAttachments => '添付資料は5件以内で指定してください。';

  @override
  String get errorMessage => '内容を1〜4,000文字で入力してください。';

  @override
  String get errorState => '案件の状態が変わりました。最新の状態を確認してください。';

  @override
  String get errorVersion => '公開中の最新納品バージョンを確認してください。';

  @override
  String get errorDelivery => '固定ソース・操作説明・テスト資料・提出コメントを入力してください。';

  @override
  String get errorSource => 'ソースの固定バージョンまたはチェックサムを指定してください。';

  @override
  String hallCount(int count) {
    return '開発案件 $count件';
  }

  @override
  String hallEstimate(String duration) {
    return '目安：$duration';
  }

  @override
  String hallVersion(int version) {
    return '整理済み要件 v$version.0';
  }

  @override
  String get customerRequestsTitle => 'ご依頼一覧';

  @override
  String get customerWorkspaceSubtitle => 'お客様向けワークスペース';

  @override
  String get customerNotifications => 'お知らせ';

  @override
  String get customerHeroTitle => 'つくりたいこと、\n相談してみませんか。';

  @override
  String get customerHeroSubtitle => '専門用語は不要です。運営が一緒に整理します。';

  @override
  String get customerCreateRequest => '開発を相談する';

  @override
  String get customerContinueDraft => '保存した下書きを続ける';

  @override
  String get customerActiveRequests => '進行中のご依頼';

  @override
  String get customerNoRequests => 'まだご依頼はありません';

  @override
  String get customerNoRequestsHint => '「開発を相談する」から、アイデアをお聞かせください。';

  @override
  String get customerProgressHint => 'ご依頼の進捗をご確認いただけます';

  @override
  String get customerDraftSaved => 'このデモの下書きに保存しました';

  @override
  String get customerAddReference => '参考資料を追加';

  @override
  String get customerAttachmentNote => 'サンプル名を選択します。端末のファイル選択・アップロードは行いません。';

  @override
  String get customerAssistTitle => '相談内容の整理案';

  @override
  String get customerAssistNote => '端末内の定型ルールによる提案です。AI への送信・自動審査は行いません。';

  @override
  String get customerKeepOriginal => '元の内容を使う';

  @override
  String get customerAdoptSuggestion => 'この案を採用';

  @override
  String get customerConfirmTitle => 'ご相談内容の確認';

  @override
  String get customerFormTitle => '開発のご相談';

  @override
  String get customerConfirmSubtitle => '送信前に内容をご確認ください';

  @override
  String get customerFormSubtitle => 'アイデアから、一緒にはじめましょう';

  @override
  String get customerProcessing => '処理中…';

  @override
  String get customerSubmitRequest => 'この内容で相談する';

  @override
  String get customerProceedConfirmation => '確認画面へ';

  @override
  String get customerEditRequest => '内容を修正する';

  @override
  String get customerSaveDraft => '下書きとして保存';

  @override
  String get customerFormStep => '1  ご相談内容';

  @override
  String get customerConfirmStep => '2  内容の確認';

  @override
  String get customerServiceCategory => '開発・AI 開発システム';

  @override
  String get customerGoalLabel => '実現したいこと';

  @override
  String get customerTimingLabel => 'ご希望の時期';

  @override
  String get customerBudgetLabel => 'ご予算の目安';

  @override
  String get customerReferenceLabel => '参考資料';

  @override
  String get customerNoAttachments => '資料なし';

  @override
  String get customerConfirmNotice =>
      '運営が合規性と技術要件を確認・整理します。送信だけで案件一覧には公開されません。予算はご希望の目安であり、お支払いは発生しません。';

  @override
  String get customerFormIntro => 'まだアイデア段階でも大丈夫です。\n実現したいことを、ご自身の言葉で教えてください。';

  @override
  String get customerGoalQuestion => 'どんなことを実現したいですか？';

  @override
  String get customerRequired => '必須';

  @override
  String get customerGoalHint => '実現したいことを教えてください';

  @override
  String get customerGoalValidation => '実現したいことを10文字以上でご入力ください';

  @override
  String get customerAssistAction => 'AI で相談内容を整理する';

  @override
  String get customerOptionalReference => '参考資料（任意）';

  @override
  String get customerAddFiles => '資料や画像を追加';

  @override
  String get customerSampleReference => 'サンプル資料';

  @override
  String get customerSubmitNotice => '送信後、運営が内容を確認・整理します。\nこの時点では案件一覧に公開されません。';

  @override
  String get customerReviewTitle => 'ご依頼の確認状況';

  @override
  String get customerReviewSubtitle => '運営が内容を確認・整理しています';

  @override
  String get customerReplyAction => '質問に回答する';

  @override
  String get customerBackToRequests => 'ご依頼一覧へ';

  @override
  String get customerPublished => '公開済み';

  @override
  String get customerUnderReview => '内容を確認中';

  @override
  String get customerReviewSteps => '公開までのステップ';

  @override
  String get customerReceivedStep => 'ご依頼を受付';

  @override
  String get customerReceivedStepDetail => '内容を受け付けました';

  @override
  String get customerComplianceStep => '合規性の確認';

  @override
  String get customerComplianceComplete => '運営による確認が完了しました';

  @override
  String get customerCompliancePending => '運営による確認をお待ちください';

  @override
  String get customerRequirementsStep => '要件を整理';

  @override
  String get customerRequirementsComplete => '技術要件の整理が完了しました';

  @override
  String get customerRequirementsNeedsInfo => '追加の情報をお待ちしています';

  @override
  String get customerRequirementsPending => '運営が内容を確認・整理します';

  @override
  String get customerPublicationStep => '案件一覧に公開';

  @override
  String get customerPublicationComplete => '確認済みのバージョンを公開しました';

  @override
  String get customerPublicationPending => 'すべての確認が終わってから公開';

  @override
  String get customerOperatorQuestion => '運営からの確認事項';

  @override
  String get customerOperatorAwaitingReply => 'OPC 運営 · 回答をお待ちしています';

  @override
  String get customerOperatorReplyReceived => 'OPC 運営 · 回答を受け付けました';

  @override
  String get customerSupplementConversation => '補足・やりとり';

  @override
  String get customerPublicationNotice => '審査を通過した公開バージョンのみ、案件一覧に表示されます。';

  @override
  String get customerUnpublishedNotice => 'この依頼は、まだ案件一覧に公開されていません。';

  @override
  String get customerReplySuccess => '回答を送信しました。運営の確認をお待ちください。';

  @override
  String get customerReplyLabel => 'ご回答';

  @override
  String get customerReplyHint => '例：利用者は30名ほど、参考資料はPDFです。';

  @override
  String get customerReplyValidation => '回答をご入力ください';

  @override
  String get customerReplyNotice => '回答は運営が確認します。送信後も自動的には審査・公開されません。';

  @override
  String get customerSending => '送信中…';

  @override
  String get customerSendReply => '回答を送信';

  @override
  String get customerRequestDetail => 'ご依頼の詳細';

  @override
  String get customerNoNotifications => '新しいお知らせはありません。';

  @override
  String get customerWorkspace => 'ワークスペース';

  @override
  String get customerTasks => '案件';

  @override
  String get customerHome => 'ホーム';

  @override
  String get customerProjects => 'プロジェクト';

  @override
  String get customerRequests => 'ご依頼';

  @override
  String get customerMessages => 'メッセージ';

  @override
  String get customerProfile => 'マイページ';

  @override
  String get customerMessageListSubtitle => 'ご依頼ごとのやり取り';

  @override
  String get customerRequestListSubtitle => '進行状況をいつでも確認';

  @override
  String get customerEmptyWorkspace => 'まだご依頼はありません。ホームから開発の相談をはじめましょう。';

  @override
  String get customerViewDetails => '詳細を確認する';

  @override
  String get customerSendMessage => '送信する';

  @override
  String get customerMessageSent => 'メッセージを送信しました';

  @override
  String get customerConversationNote => 'このご依頼に関する運営とのやり取りです。';

  @override
  String get customerNoMessages => 'メッセージはまだありません。';

  @override
  String get customerMessageHint => 'メッセージを入力';

  @override
  String get customerProfileSubtitle => 'アカウントと表示設定';

  @override
  String get customerInternalAccount => '内部アカウント';

  @override
  String get customerCustomerAccount => 'お客様アカウント';

  @override
  String get customerInternalAuthorization =>
      '内部の案件対応権限が付与されています。OPC 正式認定とは異なります。';

  @override
  String get customerAppearance => '画面の表示';

  @override
  String get customerThemeSystem => 'システム';

  @override
  String get customerThemeLight => 'ライト';

  @override
  String get customerThemeDark => 'ダーク';

  @override
  String get customerBusinessRegion => '日本向けサービス · 日本円（JPY）· 日本標準時（JST）';

  @override
  String get customerAbout => 'このアプリについて';

  @override
  String get customerAboutNote =>
      'OPC V1 / 0.1.0\nデモ環境です。業務データは端末のメモリ上に保存され、アプリの再起動で初期化されます。実際の認証・ファイル送信・決済は行いません。';

  @override
  String get customerDemoScenarios => 'デモシナリオ';

  @override
  String get customerLogout => 'ログアウト';

  @override
  String get customerDemoSubtitle => 'デモ操作 · 実際の管理操作ではありません';

  @override
  String get customerDemoNotice =>
      'バックエンドの審査結果を再現する開発用操作です。実運用では管理端とサーバーだけが審査・公開を実行します。';

  @override
  String get customerSimulateDelivery => '内部確認後の納品公開を再現';

  @override
  String get customerSimulatePublication => '審査・要件整理後の公開を再現';

  @override
  String get customerDemoUpdated => 'デモの状態を更新しました';

  @override
  String get customerFailNextAction => '次の送信を失敗させる';

  @override
  String get customerFailNextNotice => '次の送信でエラーを再現します。内容を保ったまま再試行できます。';

  @override
  String get customerResetDemo => 'デモを初期状態に戻す';

  @override
  String get customerResetDemoTitle => 'デモをリセットしますか？';

  @override
  String get customerResetDemoNotice =>
      'このデモで追加した登録・ご依頼・メッセージが消去され、ログイン画面に戻ります。';

  @override
  String get customerBack => '戻る';

  @override
  String get customerReset => 'リセット';

  @override
  String customerRequestCount(int count) {
    return '$count件';
  }

  @override
  String customerDeliveryPrompt(String id) {
    return '$id · 納品内容をご確認ください';
  }

  @override
  String customerRemoveAttachment(String name) {
    return '$name を削除';
  }

  @override
  String customerAssistedDescription(String original) {
    return '実現したいこと：\n$original\n\n利用する方：社内の社員（人数は相談時に確認）\n確認したいこと：利用する資料の形式、必要な機能、完成後の運用方法。';
  }

  @override
  String customerReceivedDate(int year, int month, int day, String time) {
    return '$year年$month月$day日 $time（JST）';
  }

  @override
  String customerReceivedAt(String date) {
    return '受付：$date';
  }

  @override
  String customerMessageDate(int month, int day, String time) {
    return '$month月$day日 $time JST';
  }

  @override
  String get customerTimingMonth => '1か月以内を希望';

  @override
  String get customerTimingQuarter => '2〜3か月以内を希望';

  @override
  String get customerTimingDiscuss => '時期は相談したい';

  @override
  String get customerBudgetDiscuss => '相談して決めたい';

  @override
  String get customerBudgetUnder100k => '10万円未満';

  @override
  String get customerBudget100to300k => '10万〜30万円';

  @override
  String get customerBudget300to500k => '30万〜50万円';

  @override
  String get customerBudgetOver500k => '50万円以上';

  @override
  String get customerLanguage => '言語';

  @override
  String get customerLanguageNote =>
      '表示言語のみを切り替えます。ご依頼やメッセージの原文・通貨・時刻・権限は変わりません。';

  @override
  String get fileSaveToPhone => '端末のファイルに保存';

  @override
  String get filePreviewFailed => 'プレビューできません。再試行するか、原本を端末に保存して開いてください。';

  @override
  String get fileInlineAttachment => 'ファイルを表示';

  @override
  String get fileOriginal => '原本をダウンロード';

  @override
  String get mediaFullscreen => '全画面再生';

  @override
  String get mediaExitFullscreen => '全画面を終了';

  @override
  String get mediaPause => '一時停止';

  @override
  String get mediaReplay => 'もう一度再生';

  @override
  String get mediaBackward => '10秒戻る';

  @override
  String get mediaForward => '10秒進む';

  @override
  String get mediaMute => 'ミュート';

  @override
  String get mediaUnmute => 'ミュートを解除';

  @override
  String get mediaSpeed => '再生速度';

  @override
  String get homeIntro => 'ご依頼・進捗・パートナーからの連絡をまとめて確認';

  @override
  String homeGreeting(String name) {
    return '$name さん、こんにちは';
  }

  @override
  String get homeOverview => 'プロジェクトの概要';

  @override
  String homeSummary(int requests, int projects) {
    return 'ご依頼 $requests 件 · 協業プロジェクト $projects 件';
  }

  @override
  String get homeReviewing => '確認中';

  @override
  String get homeActive => '進行中';

  @override
  String get homeAcceptance => '検収待ち';

  @override
  String get homeCompleted => '完了';

  @override
  String get homeAll => 'すべて見る';

  @override
  String get homeClearFilter => 'すべての依頼を表示';

  @override
  String get homeTodos => 'ご対応が必要なこと';

  @override
  String get homeNoTodos => '現在、ご対応が必要なことはありません';

  @override
  String get homeNoTodosHelp => '追加情報、協業条件、納品内容の確認が必要な場合に表示します。';

  @override
  String get homeReplyHelp => '運営から追加の確認があります。ご回答後に手続きを進めます。';

  @override
  String get homeAgreementHelp => '範囲・見積もり・納品条件を確認し、現在の協業条件に同意してください。';

  @override
  String get homeAcceptanceHelp => '納品内容を公開しました。内容を確認し、検収または修正依頼に進んでください。';

  @override
  String get homeReviews => 'ご依頼の確認・公開状況';

  @override
  String get homeNoReviews => '確認中・協業待ちのご依頼はありません';

  @override
  String get homeReviewHelp => '運営がご依頼を確認し、技術的な範囲を整理しています。';

  @override
  String get homePublishedHelp => 'ご依頼を公開しました。協業関係の確定をお待ちください。';

  @override
  String get homeProjects => 'プロジェクトの進捗';

  @override
  String get homeNoProjects => '進行中の協業プロジェクトはありません';

  @override
  String get homeNoProjectsHelp => '協業確定後、現在の段階・納期・連絡内容を確認できます。';

  @override
  String get homeStageReview => '依頼確認';

  @override
  String get homeStageAgreement => '協業確認';

  @override
  String get homeStageDevelopment => '開発・納品';

  @override
  String get homeStageAcceptance => '検収';

  @override
  String get homeWorkingHelp => 'パートナーが合意した範囲で作業を進めています。連絡や成果を確認できます。';

  @override
  String get homeInternalHelp => '成果物を内部確認中です。公開後に内容の確認・検収ができます。';

  @override
  String get homeRevisionHelp => 'パートナーが修正に対応しています。連絡内容をご確認ください。';

  @override
  String get homeFeedback => 'パートナーからの最新連絡';

  @override
  String get homeNoFeedback => 'パートナーからの連絡はまだありません';

  @override
  String get homeNoFeedbackHelp => 'プロジェクトの担当パートナーから届いたメッセージをまとめて表示します。';

  @override
  String get homeProvider => '担当パートナー';

  @override
  String homeUnread(int count) {
    return '未読の通知 $count 件';
  }

  @override
  String get homeStart => '最初のご依頼から始めましょう';

  @override
  String get homeStartHelp => '解決したいことをお聞かせください。確認・開発・納品の状況をここで追跡できます。';

  @override
  String get homeDraft => '保存したご相談の入力を続ける';

  @override
  String get homeMoreTodos => '対応事項をすべて見る';

  @override
  String get previewTitle => 'プレビュー';

  @override
  String get previewImageTitle => '画像を見る';

  @override
  String get previewVideoTitle => '動画を再生';

  @override
  String get previewDocumentTitle => '文書プレビュー';

  @override
  String get previewPdfTitle => 'PDF プレビュー';

  @override
  String get previewTableTitle => '表プレビュー';

  @override
  String get previewSlidesTitle => 'スライドプレビュー';

  @override
  String get previewTextTitle => 'テキストプレビュー';

  @override
  String get previewReadOnly => '読み取り専用';

  @override
  String get previewPrevious => '前へ';

  @override
  String get previewNext => '次へ';

  @override
  String get previewZoomIn => '拡大';

  @override
  String get previewZoomOut => '縮小';

  @override
  String get previewResetZoom => '拡大率をリセット';

  @override
  String get previewImageHint => 'ピンチで拡大。拡大していない時はスワイプ、矢印やサムネイルで画像を切り替えます。';

  @override
  String get previewPages => 'ページへ移動';

  @override
  String get previewPageNumber => 'ページ番号';

  @override
  String get previewGo => '移動';

  @override
  String get previewCancel => 'キャンセル';

  @override
  String get previewDocumentHint => '上下にスクロールして閲覧。ページ番号から移動できます。';

  @override
  String get previewFixtureNotice =>
      '同梱のサンプル資料を表示しています。任意の Office ファイルを変換する機能はまだ接続されていません。';

  @override
  String get previewFullscreen => '全画面';

  @override
  String get previewExitFullscreen => '全画面を閉じる';

  @override
  String get previewSlideHint => '左右のボタンやサムネイルでページを切り替えます。';

  @override
  String get previewOriginal => '原文';

  @override
  String get previewFormatted => '書式付き';

  @override
  String get previewTextSize => '文字サイズ';

  @override
  String get previewSmallerText => '文字を小さく';

  @override
  String get previewLargerText => '文字を大きく';

  @override
  String get previewTextHint =>
      '内容は原文のまま表示します。TXT は自動改行、Markdown は見出し・箇条書き・コードなどの基本書式に対応します。';

  @override
  String get previewSearch => '表内を検索';

  @override
  String get previewClearSearch => '検索をクリア';

  @override
  String get previewNoMatches => '一致するセルはありません。';

  @override
  String get previewTableHint => '左右にスクロールして列を確認できます。CSV は単一の表として表示します。';

  @override
  String get previewPlay => '再生';

  @override
  String get previewPause => '一時停止';

  @override
  String get previewMute => 'ミュート';

  @override
  String get previewUnmute => 'ミュート解除';

  @override
  String get previewSeek => '再生位置';

  @override
  String get previewVideoLoading => '動画を読み込んでいます';

  @override
  String get previewVideoFailed => '動画を再生できませんでした';

  @override
  String get previewVideoHint => 'タップして再生します。自動再生はしません。';

  @override
  String get previewPreparing => 'プレビューを準備中';

  @override
  String get previewPreparingHint => '原本はダウンロードできます。準備状況を再確認できます。';

  @override
  String get previewCheckPreparation => '準備状況を確認';

  @override
  String get previewFailed => 'プレビューできませんでした';

  @override
  String get previewFailedHint => '再試行するか、原本をダウンロードして確認してください。';

  @override
  String get previewRetry => '再試行';

  @override
  String get previewUnsupported => 'プレビュー非対応';

  @override
  String get previewUnsupportedHint => '原本をダウンロードして確認できます。';

  @override
  String get previewAccessDenied => 'この資料へのアクセス権がありません';

  @override
  String get previewAccessDeniedHint => '閲覧を停止しました。必要な場合は運営担当者にお問い合わせください。';

  @override
  String get previewEmpty => '表示できる内容がありません';

  @override
  String get previewImageFailed => '画像を読み込めませんでした';

  @override
  String get previewSelectedCell => '選択したセル';

  @override
  String previewImageCount(int current, int total) {
    return '画像 $current / $total';
  }

  @override
  String previewPageCount(int current, int total) {
    return '$current / $total';
  }

  @override
  String previewPageRange(int total) {
    return '1〜$total のページ番号を入力してください';
  }

  @override
  String previewSearchMatches(int count) {
    return '一致するセル $count 件';
  }

  @override
  String previewSheetCount(int count) {
    return '$count シート';
  }

  @override
  String previewThumbnail(int index) {
    return '$index ページを開く';
  }

  @override
  String get projectTitle => 'プロジェクト';

  @override
  String get projectProviderSubtitle => '担当プロジェクトのワークスペース';

  @override
  String get projectCustomerSubtitle => 'ご依頼の進行状況を確認しましょう';

  @override
  String get projectInfoTitle => 'プロジェクト情報';

  @override
  String get projectInternalReviewPending => '提出内容を運営が確認中です。お客様にはまだ公開されていません。';

  @override
  String get projectAwaitingOperations => '運営の確認待ち';

  @override
  String get projectSubmitRevision => '修正版を提出する';

  @override
  String get projectSubmitDelivery => '成果物を提出する';

  @override
  String get projectReviewDelivery => '納品内容を確認する';

  @override
  String get projectSendMessage => 'メッセージを送る';

  @override
  String get projectConsultation => 'プロジェクトの相談';

  @override
  String get projectConsultationHint => '確認したいことはメッセージからお知らせください。';

  @override
  String get projectOpenMessages => 'メッセージを開く';

  @override
  String get projectNoMessages => 'まだメッセージはありません。';

  @override
  String get projectNoProviderDeliveries => '提出済みの成果物はまだありません。下のボタンから提出できます。';

  @override
  String get projectNoCustomerDeliveries => 'お客様向けの納品ファイルは、運営の確認後に表示されます。';

  @override
  String get projectEditFixedVersion => '固定バージョンを編集';

  @override
  String get projectFixedVersion => 'リリース・固定コミット';

  @override
  String get projectFixedVersionHint => '例：v0.3.0 · 8f3a2c1';

  @override
  String get projectFixedVersionHelp =>
      '提出するソースを特定できるタグ・コミットを入力してください。サンプルの記録です。';

  @override
  String get projectSave => '保存する';

  @override
  String get projectSubmitted => '運営に確認を依頼しました。お客様への公開は内部確認後です。';

  @override
  String get projectDeliveryTitle => '成果物の提出';

  @override
  String get projectDeliveryUnauthorized => 'このプロジェクトの担当者だけが成果物を提出できます。';

  @override
  String get projectDeliverySubtitle => '確認できる形で、成果をまとめましょう';

  @override
  String get projectSubmitting => '提出しています…';

  @override
  String get projectRequestReview => '運営に確認を依頼する';

  @override
  String get projectSourceCode => 'ソースコード';

  @override
  String get projectRequired => '必須';

  @override
  String get projectSourceSelected => '18.4 MB · 選択済み';

  @override
  String get projectGuideAndTest => '操作説明・確認資料';

  @override
  String get projectGuideSelected => '1.2 MB · 選択済み';

  @override
  String get projectTestSelected => '84 KB · 選択済み';

  @override
  String get projectChanges => '今回の変更点';

  @override
  String get projectChangesHint => '変更内容と確認方法を入力してください';

  @override
  String get projectChangesRequired => '変更内容を入力してください';

  @override
  String get projectDeliveryReviewNotice =>
      '提出後、運営が内容を確認します。\nお客様への公開は、内部確認後に行います。';

  @override
  String get projectAttachmentsNotice =>
      '添付はサンプル名のみです。実ファイルのアップロード・テスト実行は行いません。';

  @override
  String get projectAcceptConfirmTitle => '検収を完了しますか？';

  @override
  String get projectBack => '戻る';

  @override
  String get projectCompleteAcceptance => '検収を完了する';

  @override
  String get projectAccepted => '検収が完了しました。ご確認ありがとうございます。';

  @override
  String get projectRequestRevision => '修正を依頼する';

  @override
  String get projectRevisionContent => '修正してほしい内容';

  @override
  String get projectRevisionHint => '画面・操作手順・期待した結果をお知らせください';

  @override
  String get projectRevisionHelp => '運営がご依頼を確認します。修正依頼後は、新しい公開版の到着をお待ちください。';

  @override
  String get projectRevisionRequested => '修正のご依頼を記録しました。運営が内容を確認します。';

  @override
  String get projectAcceptanceTitle => '納品内容の確認';

  @override
  String get projectNoPublishedDelivery =>
      'お客様向けに公開された納品内容はまだありません。運営の確認後に表示されます。';

  @override
  String get projectAcceptanceSubtitle => '仕上がりを、ご自身で確かめましょう';

  @override
  String get projectAcceptedNotice => '公開版の検収が完了しました。';

  @override
  String get projectRevisionPendingNotice => '修正依頼を受け付けました。新しい公開版をお待ちください。';

  @override
  String get projectCheckAllHint => 'すべての項目を確認すると、検収を完了できます。';

  @override
  String get projectAcceptanceComplete => '検収完了';

  @override
  String get projectWatchDemo => '操作デモを見る';

  @override
  String get projectDemoSummary => '登録から対応完了までをご案内';

  @override
  String get projectPublishedFiles => '納品ファイル・操作説明書';

  @override
  String get projectPublishedFileCount => '公開版の資料 3件';

  @override
  String get projectAcceptanceChecklist => 'ご確認いただきたいこと';

  @override
  String get projectRevisionReviewing => '修正のご依頼を運営が確認しています。';

  @override
  String get projectAcceptedFilesNotice =>
      'ご確認ありがとうございます。納品ファイルは引き続きこの画面から確認できます。';

  @override
  String get projectRevisionInvitation =>
      '気になる点は、修正のご依頼からお知らせください。運営が内容を確認します。';

  @override
  String get projectProgressTab => '進行状況';

  @override
  String get projectMessagesTab => 'メッセージ';

  @override
  String get projectFilesTab => 'ファイル';

  @override
  String get projectMilestones => 'マイルストーン';

  @override
  String get projectRequirementsMilestone => '要件確認';

  @override
  String get projectDevelopmentMilestone => '開発';

  @override
  String get projectInternalMilestone => '内部確認';

  @override
  String get projectCustomerMilestone => 'お客様確認';

  @override
  String get projectRevisionMilestoneDescription => 'ご依頼いただいた修正内容を確認';

  @override
  String get projectRequirementsMilestoneDescription => '対象範囲と確認基準を確定';

  @override
  String get projectDevelopmentMilestoneDescription => '検索画面と回答機能を実装中';

  @override
  String get projectInternalMilestoneDescription => '運営が品質・資料を確認';

  @override
  String get projectCustomerMilestoneDescription => '公開された納品内容を検収';

  @override
  String get projectMessageAvatar => 'メ';

  @override
  String get projectReplaceFile => 'ファイルを差し替える';

  @override
  String get projectDeliveryPublished => 'お客様公開済み';

  @override
  String get projectDeliveryInternal => '内部確認用';

  @override
  String get projectGuideMetadata => '操作説明';

  @override
  String get projectTestMetadata => '確認資料';

  @override
  String get projectMessageSent => 'メッセージを送信しました';

  @override
  String get projectMessageHint => 'メッセージを入力';

  @override
  String get projectMessageRequired => 'メッセージを入力してください';

  @override
  String get projectMessageSendTooltip => 'メッセージを送信';

  @override
  String get projectSelectFile => 'ファイルを選択';

  @override
  String get projectFilePickerNotice => 'サンプル名を選択・編集できます。実際のファイルは送信されません。';

  @override
  String get projectSampleFilename => 'サンプルファイル名';

  @override
  String get projectFilenameRequired => 'ファイル名を入力してください';

  @override
  String get projectUseSample => 'このサンプルを使用する';

  @override
  String get projectCancel => 'キャンセル';

  @override
  String get projectClose => '閉じる';

  @override
  String get projectSourcePreview =>
      'ソースコード一式\n\n・アプリケーションのソース\n・環境設定のサンプル\n・起動手順（README）\n\n固定バージョンに紐づく構成例です。この画面ではコードの実行やダウンロードを行いません。';

  @override
  String get projectGuidePreview =>
      '操作説明のサンプル\n\n1. 一覧画面で登録済みの項目を確認します。\n2. キーワードを入力して検索します。\n3. 詳細画面で内容を確認・更新します。\n4. 保存後、一覧で変更結果を確認します。';

  @override
  String get projectTestPreview =>
      '確認資料のサンプル\n\n・登録・検索シナリオ\n・更新・保存シナリオ\n・操作説明の確認\n\nこの資料は画面確認用の合成データです。実際のテスト結果や品質保証を示すものではありません。';

  @override
  String get projectFileAccessNotice => '実ファイルの取得・配信は、今後の API 接続で対応します。';

  @override
  String get projectDemoTitle => '操作デモ';

  @override
  String get projectDemoRegister => '1. 問い合わせを登録';

  @override
  String get projectDemoSearch => '2. 一覧から検索';

  @override
  String get projectDemoUpdate => '3. 対応状況を更新';

  @override
  String get projectDemoRegisterDescription =>
      '件名と内容を入力して保存すると、一覧に新しい問い合わせが表示されます。';

  @override
  String get projectDemoSearchDescription => 'キーワードで対象を絞り込み、問い合わせの詳細を確認します。';

  @override
  String get projectDemoUpdateDescription => '担当者と対応状況を変更し、保存後の内容を一覧で確認します。';

  @override
  String get projectDemoRestart => '最初から見る';

  @override
  String get projectDemoNext => '次の操作へ';

  @override
  String get projectDemoNotice => '画面内のサンプルガイドです。実際の納品環境や動画には接続していません。';

  @override
  String get projectInfoMessageNotice => '変更点やご不明点は、プロジェクトのメッセージからご相談ください。';

  @override
  String get projectNextDeveloping => '次の予定：10月16日 デモ確認';

  @override
  String get projectNextInternalReview => '次の予定：運営による内容確認';

  @override
  String get projectNextAcceptance => '次の予定：お客様による納品内容の確認';

  @override
  String get projectNextRevision => '次の予定：修正内容の確認と再提出';

  @override
  String get projectNextCompleted => '公開版の検収が完了しました';

  @override
  String get projectNextDefault => '進行に合わせて次の予定をご案内します';

  @override
  String get projectCheckFaqSearch => '質問を入力し、関連する資料を検索できる';

  @override
  String get projectCheckFaqSources => '回答の根拠となる資料を確認できる';

  @override
  String get projectCheckGuide => '操作説明を読み、利用方法を確認した';

  @override
  String get projectCheckSearch => '問い合わせを登録・検索できる';

  @override
  String get projectCheckUpdate => '担当者と対応状況を更新できる';

  @override
  String projectSubmissionDestination(String id) {
    return '$id · 提出先：OPC 運営';
  }

  @override
  String projectAcceptConfirmBody(int version) {
    return '公開版 v$version.0.0 の確認を完了します。\n\nこの操作は納品内容の検収記録です。支払いや精算は行いません。';
  }

  @override
  String projectCustomerVersion(int version) {
    return 'お客様向け公開版 v$version.0.0';
  }

  @override
  String projectSubmittedVersion(int version) {
    return '提出バージョン $version';
  }

  @override
  String projectFieldRequired(String label) {
    return '$labelを入力してください';
  }

  @override
  String projectTargetVersion(String version) {
    return '対象バージョン：$version';
  }

  @override
  String projectDemoVersion(String version) {
    return '公開版 $version · サンプルガイド';
  }

  @override
  String projectConfirmedScope(int version) {
    return '確認済みの対象範囲：バージョン $version';
  }

  @override
  String get refTitle => '参考資料';

  @override
  String refPublishedVersion(String taskId, int version) {
    return '$taskId · 公開要件 v$version.0';
  }

  @override
  String get refPublishedNotice => '現在の公開要件に含まれる参考資料のみ表示しています。';

  @override
  String refViewAll(int count) {
    return 'すべて見る $count';
  }

  @override
  String refImages(int count) {
    return '画像 $count';
  }

  @override
  String refVideos(int count) {
    return '動画 $count';
  }

  @override
  String refFiles(int count) {
    return '資料 $count';
  }

  @override
  String get refImageHint => '画面イメージ';

  @override
  String get refVideoHint => '操作イメージ';

  @override
  String get refAttachments => '添付ファイル';

  @override
  String refCount(int count) {
    return '$count 件';
  }

  @override
  String get refOpenHint => 'タップして閲覧・再生。すべての資料を個別に保存できます。';

  @override
  String get refEmpty => '公開されている参考資料はありません。';

  @override
  String get refPreview => 'プレビュー';

  @override
  String get refDownload => '原本をダウンロード';

  @override
  String get refImageDownload => '画像をダウンロード';

  @override
  String get refVideoDownload => '動画をダウンロード';

  @override
  String refDownloading(int percent) {
    return 'ダウンロード中 · $percent%';
  }

  @override
  String get refCancel => '中止';

  @override
  String get refCancelled => 'ダウンロードを中止しました';

  @override
  String get refDownloadFailed => 'ダウンロードに失敗しました';

  @override
  String get refRetry => '再試行';

  @override
  String get refDownloaded => 'ダウンロード完了';

  @override
  String get refSavedInApp => 'アプリ内に保存しました。端末のファイルに保存するには「書き出す」を選んでください。';

  @override
  String get refLocalSample => 'このアプリに同梱したサンプルの原本を保存します。';

  @override
  String get refOpen => '開く';

  @override
  String get refExport => '書き出す';

  @override
  String get refActionFailed => 'ファイルを開くか書き出す操作を完了できませんでした。対応アプリや保存先を確認してください。';

  @override
  String get refAccessDenied => 'この資料へのアクセス権がありません。必要な場合は運営担当者にお問い合わせください。';

  @override
  String get refScenarios => '資料の表示状態';

  @override
  String get refScenarioHelp => '公開済みのサンプル資料で表示状態を確認できます。資料やアカウントの権限は変更しません。';

  @override
  String get refReady => 'プレビュー可能';

  @override
  String get refPreparing => 'プレビューを準備中';

  @override
  String get refPreviewFailed => 'プレビュー失敗';

  @override
  String get refUnsupported => 'プレビュー非対応';

  @override
  String get refDownloadFailureCase => 'ダウンロード失敗と再試行';

  @override
  String get refDownloadCancelCase => 'ダウンロード進捗と中止';
}
